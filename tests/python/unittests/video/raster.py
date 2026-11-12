"""Modelo de referência da imagem VGA e captura das linhas da saída."""

from dataclasses import dataclass, field

from cocotb.triggers import ClockCycles, FallingEdge

from tests.python.unittests.video import bus
from tests.python.unittests.video.registers import (
    DIRECT_PIXEL_BITS,
    FORMAT,
    GEOMETRY,
    H_SYNC,
    H_TOTAL,
    H_VISIBLE,
    HS_BEGIN,
    PALETTE_ENTRIES,
    PALETTE_PIXEL_BITS,
    V_SYNC,
    V_TOTAL,
    V_VISIBLE,
    VS_BEGIN,
)
from tests.python.unittests.video.signals import VideoDut

Color = tuple[int, int, int]
BLACK: Color = (0, 0, 0)
HALF_WORD_MASK = 0b0011
CHANNEL_MASK = 0xF


@dataclass(frozen=True)
class Geometry:
    """Dimensões do framebuffer lidas dos registradores do periférico.

    Attributes
    ----------
    fb_width : int
        Largura em pixels.
    fb_height : int
        Altura em pixels.
    pixel_bits : int
        Bits por pixel.
    scale : int
        Fator de ampliação.
    addr_width : int
        Largura do endereço de palavra da janela.
    """

    fb_width: int
    fb_height: int
    pixel_bits: int
    scale: int
    addr_width: int

    @property
    def pixels_per_word(self) -> int:
        """Pixels em cada palavra de 32 bits."""
        return 32 // self.pixel_bits

    @property
    def words(self) -> int:
        """Palavras do framebuffer."""
        return self.fb_width * self.fb_height // self.pixels_per_word

    @property
    def x_off(self) -> int:
        """Primeira coluna da imagem na tela."""
        return (H_VISIBLE - self.fb_width * self.scale) // 2

    @property
    def y_off(self) -> int:
        """Primeira linha da imagem na tela."""
        return (V_VISIBLE - self.fb_height * self.scale) // 2

    @property
    def window(self) -> int:
        """Endereço de palavra do início da janela do framebuffer."""
        return 1 << (self.addr_width - 1)


async def read_geometry(dut: VideoDut) -> Geometry:
    """Lê a geometria e o formato dos registradores.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.

    Returns
    -------
    Geometry
        As dimensões do periférico.
    """
    size = await bus.read(dut, GEOMETRY)
    fmt = await bus.read(dut, FORMAT)
    return Geometry(
        fb_width=size & 0xFFFF,
        fb_height=size >> 16,
        pixel_bits=fmt & 0xFF,
        scale=fmt >> 8,
        addr_width=len(dut.i_address),
    )


@dataclass
class Model:
    """Conteúdo esperado do framebuffer e da paleta.

    Attributes
    ----------
    geo : Geometry
        Dimensões do framebuffer.
    words : list[int]
        Palavras do framebuffer.
    palette : list[int]
        Entradas da paleta de 12 bits.
    """

    geo: Geometry
    words: list[int] = field(default_factory=list[int])
    palette: list[int] = field(default_factory=list[int])

    def __post_init__(self) -> None:
        """Zera o framebuffer e a paleta."""
        self.words = [0] * self.geo.words
        self.palette = [0] * PALETTE_ENTRIES

    def write(self, index: int, data: int, mask: int) -> None:
        """Aplica uma escrita no framebuffer; fora da faixa é ignorada.

        Parameters
        ----------
        index : int
            Índice de palavra dentro da janela.
        data : int
            Dado de 32 bits.
        mask : int
            Habilitação de bytes.
        """
        if not 0 <= index < len(self.words):
            return
        word = self.words[index]
        for lane in range(4):
            if (mask >> lane) & 1:
                keep = ~(0xFF << (8 * lane)) & 0xFFFFFFFF
                word = (word & keep) | (data & (0xFF << (8 * lane)))
        self.words[index] = word

    def write_palette(self, index: int, data: int, mask: int) -> None:
        """Aplica uma escrita na paleta; exige as duas faixas baixas.

        Parameters
        ----------
        index : int
            Índice da entrada.
        data : int
            Dado de 32 bits.
        mask : int
            Habilitação de bytes.
        """
        if (
            self.geo.pixel_bits == PALETTE_PIXEL_BITS
            and mask & HALF_WORD_MASK == (HALF_WORD_MASK)
        ):
            self.palette[index] = data & 0xFFF

    def pixel_color(self, x: int, y: int) -> Color:
        """Cor do pixel (x, y) do framebuffer.

        Parameters
        ----------
        x : int
            Coluna do framebuffer.
        y : int
            Linha do framebuffer.

        Returns
        -------
        Color
            Vermelho, verde e azul de 4 bits.
        """
        geo = self.geo
        number = y * geo.fb_width + x
        word = self.words[number // geo.pixels_per_word]
        slot = number % geo.pixels_per_word
        raw = (word >> (geo.pixel_bits * slot)) & ((1 << geo.pixel_bits) - 1)
        rgb = (
            raw & 0xFFF
            if geo.pixel_bits == DIRECT_PIXEL_BITS
            else self.palette[raw]
        )
        return (
            (rgb >> 8) & CHANNEL_MASK,
            (rgb >> 4) & CHANNEL_MASK,
            rgb & CHANNEL_MASK,
        )

    def screen_color(self, x: int, y: int) -> Color:
        """Cor esperada do pixel (x, y) da tela de 800x525.

        Parameters
        ----------
        x : int
            Coluna da tela.
        y : int
            Linha da tela.

        Returns
        -------
        Color
            Vermelho, verde e azul de 4 bits.
        """
        geo = self.geo
        fx, fy = x - geo.x_off, y - geo.y_off
        width, height = geo.fb_width * geo.scale, geo.fb_height * geo.scale
        if 0 <= fx < width and 0 <= fy < height:
            return self.pixel_color(fx // geo.scale, fy // geo.scale)
        return BLACK


@dataclass(frozen=True)
class Sample:
    """Estado dos pinos VGA em um ciclo de pixel.

    Attributes
    ----------
    color : Color
        Vermelho, verde e azul.
    hs : int
        Sincronismo horizontal.
    vs : int
        Sincronismo vertical.
    """

    color: Color
    hs: int
    vs: int


def sample(dut: VideoDut) -> Sample:
    """Lê os pinos VGA.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.

    Returns
    -------
    Sample
        O estado dos pinos.
    """
    return Sample(
        color=(
            int(dut.o_vga_r.value),
            int(dut.o_vga_g.value),
            int(dut.o_vga_b.value),
        ),
        hs=int(dut.o_vga_hs.value),
        vs=int(dut.o_vga_vs.value),
    )


async def seek(dut: VideoDut, line: int, column: int) -> None:
    """Para na amostra (coluna, linha) do próximo quadro.

    A referência é a borda de descida de o_vga_vs, que marca a coluna 0
    da linha 490; as amostras são tomadas no meio do ciclo de pixel.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    line : int
        Linha da tela.
    column : int
        Coluna da tela.
    """
    await FallingEdge(dut.o_vga_vs)
    await FallingEdge(dut.i_pixel_clk)
    skip = ((line - VS_BEGIN) % V_TOTAL) * H_TOTAL + column
    if skip:
        await ClockCycles(dut.i_pixel_clk, skip, rising=False)


async def capture(dut: VideoDut, first: int, count: int) -> list[list[Sample]]:
    """Captura linhas consecutivas da tela, de 800 amostras cada.

    A captura começa na coluna 0 da primeira linha e amostra os pinos no
    meio de cada ciclo de pixel.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    first : int
        Primeira linha da tela a capturar.
    count : int
        Número de linhas.

    Returns
    -------
    list[list[Sample]]
        As linhas capturadas.
    """
    await seek(dut, first, 0)
    rows: list[list[Sample]] = []
    for _ in range(count):
        row: list[Sample] = []
        for _ in range(H_TOTAL):
            row.append(sample(dut))
            await FallingEdge(dut.i_pixel_clk)
        rows.append(row)
    return rows


def check_row(model: Model, line: int, row: list[Sample]) -> None:
    """Confere uma linha capturada contra o modelo e os sincronismos.

    Parameters
    ----------
    model : Model
        Conteúdo esperado.
    line : int
        Número da linha da tela.
    row : list[Sample]
        As 800 amostras da linha.

    Raises
    ------
    AssertionError
        Se algum pixel ou sincronismo difere do esperado.
    """
    vs_low = VS_BEGIN <= line < VS_BEGIN + V_SYNC
    for column, got in enumerate(row):
        hs_low = HS_BEGIN <= column < HS_BEGIN + H_SYNC
        want = Sample(
            model.screen_color(column, line) if column < H_VISIBLE else BLACK,
            0 if hs_low else 1,
            0 if vs_low else 1,
        )
        if got != want:
            message = f"linha {line} coluna {column}: {got} != {want}"
            raise AssertionError(message)

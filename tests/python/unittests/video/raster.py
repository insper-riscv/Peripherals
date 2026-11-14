"""Modelo de referência da imagem de vídeo e captura da saída."""

from dataclasses import dataclass, field

from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

from tests.python.unittests.video import bus
from tests.python.unittests.video.registers import (
    COLOR_CHANNELS,
    FORMAT,
    GEOMETRY,
    INDEXED_FLAG,
    PALETTE_ENTRIES,
    Mode,
    read_mode,
)
from tests.python.unittests.video.signals import VideoDut

Color = tuple[int, int, int]
BLACK: Color = (0, 0, 0)
BITS_PER_BYTE = 8


@dataclass(frozen=True)
class Geometry:
    """Dimensões e formato do framebuffer lidos do periférico.

    Attributes
    ----------
    fb_width : int
        Largura em pixels.
    fb_height : int
        Altura em pixels.
    pixel_bits : int
        Bits que cada pixel ocupa no framebuffer.
    scale : int
        Fator de ampliação.
    channel_bits : int
        Bits de cada canal de cor.
    indexed : bool
        Formato indexado (com paleta) quando verdadeiro.
    addr_width : int
        Largura do endereço de palavra da janela.
    mode : Mode
        Temporização do modo de vídeo.
    """

    fb_width: int
    fb_height: int
    pixel_bits: int
    scale: int
    channel_bits: int
    indexed: bool
    addr_width: int
    mode: Mode

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
        return (self.mode.h_visible - self.fb_width * self.scale) // 2

    @property
    def y_off(self) -> int:
        """Primeira linha da imagem na tela."""
        return (self.mode.v_visible - self.fb_height * self.scale) // 2

    @property
    def window(self) -> int:
        """Endereço de palavra do início da janela do framebuffer."""
        return 1 << (self.addr_width - 1)

    @property
    def channel_mask(self) -> int:
        """Máscara de um canal de cor."""
        return (1 << self.channel_bits) - 1

    @property
    def color_mask(self) -> int:
        """Máscara de uma cor de três canais."""
        return (1 << (COLOR_CHANNELS * self.channel_bits)) - 1

    @property
    def palette_mask(self) -> int:
        """Máscara de bytes que uma escrita na paleta deve cobrir."""
        bytes_needed = (
            COLOR_CHANNELS * self.channel_bits + BITS_PER_BYTE - 1
        ) // BITS_PER_BYTE
        return (1 << bytes_needed) - 1


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
        scale=(fmt >> 8) & 0xFF,
        channel_bits=(fmt >> 16) & 0xFF,
        indexed=bool(fmt & INDEXED_FLAG),
        addr_width=len(dut.i_address),
        mode=read_mode(dut),
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
        Entradas da paleta de 3 x channel_bits bits.
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
        """Aplica uma escrita na paleta; exige as faixas baixas da cor.

        Parameters
        ----------
        index : int
            Índice da entrada.
        data : int
            Dado de 32 bits.
        mask : int
            Habilitação de bytes.
        """
        need = self.geo.palette_mask
        if self.geo.indexed and mask & need == need:
            self.palette[index] = data & self.geo.color_mask

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
            Vermelho, verde e azul.
        """
        geo = self.geo
        number = y * geo.fb_width + x
        word = self.words[number // geo.pixels_per_word]
        slot = number % geo.pixels_per_word
        raw = (word >> (geo.pixel_bits * slot)) & ((1 << geo.pixel_bits) - 1)
        rgb = self.palette[raw] if geo.indexed else raw & geo.color_mask
        bits = geo.channel_bits
        return (
            (rgb >> (2 * bits)) & geo.channel_mask,
            (rgb >> bits) & geo.channel_mask,
            rgb & geo.channel_mask,
        )

    def screen_color(self, x: int, y: int) -> Color:
        """Cor esperada do pixel (x, y) da tela.

        Parameters
        ----------
        x : int
            Coluna da tela.
        y : int
            Linha da tela.

        Returns
        -------
        Color
            Vermelho, verde e azul.
        """
        geo = self.geo
        fx, fy = x - geo.x_off, y - geo.y_off
        width, height = geo.fb_width * geo.scale, geo.fb_height * geo.scale
        if 0 <= fx < width and 0 <= fy < height:
            return self.pixel_color(fx // geo.scale, fy // geo.scale)
        return BLACK


@dataclass(frozen=True)
class Sample:
    """Estado dos pinos de vídeo em um ciclo de pixel.

    Attributes
    ----------
    color : Color
        Vermelho, verde e azul.
    hs : int
        Sincronismo horizontal.
    vs : int
        Sincronismo vertical.
    blank_n : int
        Apagamento do conversor, ativo em nível baixo.
    """

    color: Color
    hs: int
    vs: int
    blank_n: int


def sample(dut: VideoDut) -> Sample:
    """Lê os pinos de vídeo.

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
        blank_n=int(dut.o_vga_blank_n.value),
    )


async def vs_pulse_start(dut: VideoDut, mode: Mode) -> None:
    """Espera a borda de início do pulso de sincronismo vertical.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    mode : Mode
        Temporização do modo.
    """
    if mode.v_positive:
        await RisingEdge(dut.o_vga_vs)
    else:
        await FallingEdge(dut.o_vga_vs)


async def vs_pulse_end(dut: VideoDut, mode: Mode) -> None:
    """Espera a borda de fim do pulso de sincronismo vertical.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    mode : Mode
        Temporização do modo.
    """
    if mode.v_positive:
        await FallingEdge(dut.o_vga_vs)
    else:
        await RisingEdge(dut.o_vga_vs)


async def seek(dut: VideoDut, line: int, column: int) -> None:
    """Para na amostra (coluna, linha) do próximo quadro.

    A referência é a borda de início de o_vga_vs, que marca a coluna 0
    da linha em que o pulso vertical começa; as amostras são tomadas no
    meio do ciclo de pixel.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    line : int
        Linha da tela.
    column : int
        Coluna da tela.
    """
    mode = read_mode(dut)
    await vs_pulse_start(dut, mode)
    await FallingEdge(dut.i_pixel_clk)
    skip = ((line - mode.vs_begin) % mode.v_total) * mode.h_total + column
    if skip:
        await ClockCycles(dut.i_pixel_clk, skip, rising=False)


async def capture(dut: VideoDut, first: int, count: int) -> list[list[Sample]]:
    """Captura linhas consecutivas da tela, de h_total amostras cada.

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
    mode = read_mode(dut)
    await seek(dut, first, 0)
    rows: list[list[Sample]] = []
    for _ in range(count):
        row: list[Sample] = []
        for _ in range(mode.h_total):
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
        As amostras da linha.

    Raises
    ------
    AssertionError
        Se algum pixel ou sincronismo difere do esperado.
    """
    mode = model.geo.mode
    for column, got in enumerate(row):
        want = Sample(
            model.screen_color(column, line)
            if mode.visible(column, line)
            else BLACK,
            mode.hs_level(column),
            mode.vs_level(line),
            int(mode.visible(column, line)),
        )
        if got != want:
            message = f"linha {line} coluna {column}: {got} != {want}"
            raise AssertionError(message)

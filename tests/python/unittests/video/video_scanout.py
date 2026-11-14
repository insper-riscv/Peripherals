"""Caminho de pixel: endereço, escolha do pixel, paleta e latência."""

from dataclasses import dataclass

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.unittests.video.bus import drive
from tests.python.unittests.video.registers import COLOR_CHANNELS, storage_bits
from tests.python.unittests.video.signals import ScanoutDut
from tests.python.utils.check import check
from tests.python.utils.rng import seeded

SEED = 0x5CA
CLOCK_NS = 10
SETTLE_EDGES = 4
CYCLES = 3000
LATENCY = 2
TOGGLE_PROB = 0.1


class Memories:
    """Memórias de leitura registrada que a varredura consulta.

    Attributes
    ----------
    words : list[int]
        Palavras do framebuffer.
    palette : list[int]
        Cores da paleta.
    """

    def __init__(self, depth: int, color_bits: int, seed: int) -> None:
        """Preenche as memórias com valores aleatórios.

        Parameters
        ----------
        depth : int
            Palavras do framebuffer.
        color_bits : int
            Bits de uma cor da paleta.
        seed : int
            Semente dos valores.
        """
        rng = seeded(seed)
        self.words = [rng.getrandbits(32) for _ in range(depth)]
        self.palette = [rng.getrandbits(color_bits) for _ in range(256)]


@dataclass(frozen=True)
class Format:
    """Formato do pixel sob teste.

    Attributes
    ----------
    width : int
        Largura do framebuffer.
    height : int
        Altura do framebuffer.
    channel_bits : int
        Bits de cada canal.
    indexed : bool
        Formato indexado quando verdadeiro.
    """

    width: int
    height: int
    channel_bits: int
    indexed: bool

    @property
    def pixel_bits(self) -> int:
        """Bits que cada pixel ocupa no framebuffer."""
        return storage_bits(self.indexed, self.channel_bits)

    @property
    def color_bits(self) -> int:
        """Bits de uma cor."""
        return COLOR_CHANNELS * self.channel_bits


async def read_format(dut: ScanoutDut) -> Format:
    """Descobre o formato pelo comportamento da porta da paleta.

    O simulador não expõe generics de texto, então o teste põe um pixel
    de bits todos em 1 na palavra lida: só o formato indexado o leva ao
    endereço da paleta.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste, com o clock em andamento.

    Returns
    -------
    Format
        O formato do pixel.
    """
    dut.i_fb_data.value = 0xFFFFFFFF
    for _ in range(2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    indexed = int(dut.o_pal_addr.value) != 0
    return Format(
        int(dut.fb_width.value),
        int(dut.fb_height.value),
        int(dut.channel_bits.value),
        indexed,
    )


async def memory_model(dut: ScanoutDut, memories: Memories) -> None:
    """Modela as memórias síncronas: o dado chega uma borda depois.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    memories : Memories
        Conteúdo das memórias.
    """
    while True:
        await RisingEdge(dut.i_clk)
        dut.i_fb_data.value = memories.words[int(dut.o_fb_addr.value)]
        index = int(dut.o_pal_addr.value)
        dut.i_pal_data.value = memories.palette[index]


def expected_color(memories: Memories, fmt: Format, x: int, y: int) -> int:
    """Cor esperada de um pixel do framebuffer.

    Parameters
    ----------
    memories : Memories
        Conteúdo das memórias.
    fmt : Format
        Formato do pixel.
    x : int
        Coluna do pixel.
    y : int
        Linha do pixel.

    Returns
    -------
    int
        A cor de três canais.
    """
    bits = fmt.pixel_bits
    per_word = 32 // bits
    number = y * fmt.width + x
    word = memories.words[number // per_word]
    raw = (word >> (bits * (number % per_word))) & ((1 << bits) - 1)
    if fmt.indexed:
        return memories.palette[raw]
    return raw & ((1 << fmt.color_bits) - 1)


async def reset(dut: ScanoutDut) -> None:
    """Inicia o clock e dá tempo para as memórias assentarem.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    """
    drive(
        dut,
        i_enable=1,
        i_hs=1,
        i_vs=1,
        i_visible=0,
        i_image=0,
        i_fb_x=0,
        i_fb_y=0,
        i_fb_data=0,
        i_pal_data=0,
    )
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    for _ in range(SETTLE_EDGES):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


@dataclass(frozen=True)
class Stimulus:
    """Entrada de um ciclo e a cor que o framebuffer devolve para ela.

    Attributes
    ----------
    color : int
        Cor do pixel endereçado.
    image : int
        Marca de imagem.
    visible : int
        Marca de área visível.
    hs : int
        Sincronismo horizontal.
    vs : int
        Sincronismo vertical.
    """

    color: int
    image: int
    visible: int
    hs: int
    vs: int


async def run_random(dut: ScanoutDut, fmt: Format) -> None:
    """Estimula coordenadas aleatórias e compara dois ciclos depois.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    fmt : Format
        Formato do pixel.
    """
    rng = seeded(SEED + fmt.pixel_bits)
    memories = Memories(
        fmt.width * fmt.height * fmt.pixel_bits // 32, fmt.color_bits, SEED
    )
    cocotb.start_soon(memory_model(dut, memories))
    history: list[Stimulus] = []
    for _ in range(CYCLES):
        x, y = rng.randrange(fmt.width), rng.randrange(fmt.height)
        enable = int(rng.random() > TOGGLE_PROB)
        image, visible = rng.getrandbits(1), rng.getrandbits(1)
        hs, vs = rng.getrandbits(1), rng.getrandbits(1)
        dut.i_fb_x.value = x
        dut.i_fb_y.value = y
        dut.i_enable.value = enable
        dut.i_image.value = image
        dut.i_visible.value = visible
        dut.i_hs.value = hs
        dut.i_vs.value = vs
        color = expected_color(memories, fmt, x, y)
        history.append(Stimulus(color, image, visible, hs, vs))
        await FallingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if len(history) >= LATENCY:
            compare(dut, history[-LATENCY], enable)


def compare(dut: ScanoutDut, stimulus: Stimulus, enable: int) -> None:
    """Confere a saída contra a entrada de dois ciclos antes.

    A habilitação vale no ciclo em que a saída é lida.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    stimulus : Stimulus
        Entrada de dois ciclos antes.
    enable : int
        Habilitação vista no ciclo da leitura.
    """
    want = (
        stimulus.color,
        stimulus.image and enable,
        stimulus.visible,
        stimulus.hs,
        stimulus.vs,
    )
    got = (
        int(dut.o_color.value),
        int(dut.o_lit.value),
        int(dut.o_visible.value),
        int(dut.o_hs.value),
        int(dut.o_vs.value),
    )
    check(got == want, f"{got} != {want}")


@cocotb.test()
async def test_random_pixels_latency_two(dut: ScanoutDut) -> None:
    """Cor, marcas e sincronismos saem alinhados, dois ciclos depois."""
    await reset(dut)
    await run_random(dut, await read_format(dut))


@cocotb.test()
async def test_disable_clears_lit(dut: ScanoutDut) -> None:
    """A habilitação desligada apaga só a marca de imagem acesa."""
    await reset(dut)
    dut.i_image.value = 1
    dut.i_visible.value = 1
    dut.i_enable.value = 0
    dut.i_hs.value = 0
    for _ in range(LATENCY + 2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(int(dut.o_hs.value) == 0, "HS acompanha a entrada")
    check(int(dut.o_visible.value) == 1, "a área visível não depende")
    check(int(dut.o_lit.value) == 0, "desabilitada, nada é aceso")
    dut.i_enable.value = 1
    await Timer(1, unit="ns")
    check(int(dut.o_lit.value) == 1, "habilitada, a imagem acende")

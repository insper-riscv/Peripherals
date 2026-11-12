"""Caminho de pixel: endereço, escolha do pixel, paleta e latência."""

from dataclasses import dataclass

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.unittests.video.bus import drive
from tests.python.unittests.video.registers import DIRECT_PIXEL_BITS
from tests.python.unittests.video.signals import ScanoutDut
from tests.python.utils.bus import hold_reset
from tests.python.utils.check import check
from tests.python.utils.rng import seeded

SEED = 0x5CA
CYCLES = 3000
LATENCY = 3
CHANNEL = 0xF
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

    def __init__(self, depth: int, seed: int) -> None:
        """Preenche as memórias com valores aleatórios.

        Parameters
        ----------
        depth : int
            Palavras do framebuffer.
        seed : int
            Semente dos valores.
        """
        rng = seeded(seed)
        self.words = [rng.getrandbits(32) for _ in range(depth)]
        self.palette = [rng.getrandbits(12) for _ in range(256)]


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


def expected_color(
    memories: Memories, width: int, bits: int, x: int, y: int
) -> tuple[int, int, int]:
    """Cor esperada de um pixel do framebuffer.

    Parameters
    ----------
    memories : Memories
        Conteúdo das memórias.
    width : int
        Largura do framebuffer em pixels.
    bits : int
        Bits por pixel.
    x : int
        Coluna do pixel.
    y : int
        Linha do pixel.

    Returns
    -------
    tuple[int, int, int]
        Vermelho, verde e azul.
    """
    per_word = 32 // bits
    number = y * width + x
    word = memories.words[number // per_word]
    raw = (word >> (bits * (number % per_word))) & ((1 << bits) - 1)
    rgb = (raw & 0xFFF) if bits == DIRECT_PIXEL_BITS else memories.palette[raw]
    return (rgb >> 8) & CHANNEL, (rgb >> 4) & CHANNEL, rgb & CHANNEL


async def reset(dut: ScanoutDut) -> None:
    """Inicia o clock e aplica o reset.

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
        i_image=0,
        i_fb_x=0,
        i_fb_y=0,
        i_fb_data=0,
        i_pal_data=0,
    )
    await hold_reset(dut, 4)


async def run_random(
    dut: ScanoutDut, width: int, height: int, bits: int
) -> None:
    """Estimula coordenadas aleatórias e compara três ciclos depois.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    width : int
        Largura do framebuffer.
    height : int
        Altura do framebuffer.
    bits : int
        Bits por pixel.
    """
    rng = seeded(SEED + bits)
    memories = Memories(width * height * bits // 32, SEED)
    await reset(dut)
    cocotb.start_soon(memory_model(dut, memories))
    history: list[Stimulus] = []
    for _ in range(CYCLES):
        x, y = rng.randrange(width), rng.randrange(height)
        enable, image = int(rng.random() > TOGGLE_PROB), rng.getrandbits(1)
        hs, vs = rng.getrandbits(1), rng.getrandbits(1)
        dut.i_fb_x.value = x
        dut.i_fb_y.value = y
        dut.i_enable.value = enable
        dut.i_image.value = image
        dut.i_hs.value = hs
        dut.i_vs.value = vs
        color = expected_color(memories, width, bits, x, y)
        history.append(Stimulus(color, image, hs, vs))
        await FallingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if len(history) >= LATENCY:
            compare(dut, history[-LATENCY], enable)


@dataclass(frozen=True)
class Stimulus:
    """Entrada de um ciclo e a cor que o framebuffer devolve para ela.

    Attributes
    ----------
    color : tuple[int, int, int]
        Cor do pixel endereçado.
    image : int
        Marca de imagem.
    hs : int
        Sincronismo horizontal.
    vs : int
        Sincronismo vertical.
    """

    color: tuple[int, int, int]
    image: int
    hs: int
    vs: int


def compare(dut: ScanoutDut, stimulus: Stimulus, enable: int) -> None:
    """Confere a saída contra a entrada de três ciclos antes.

    A habilitação vale no ciclo em que a saída é registrada.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    stimulus : Stimulus
        Entrada de três ciclos antes.
    enable : int
        Habilitação vista na borda que registra a saída.
    """
    lit = stimulus.image and enable
    want = (
        stimulus.color if lit else (0, 0, 0),
        stimulus.hs,
        stimulus.vs,
    )
    got = (
        (
            int(dut.o_vga_r.value),
            int(dut.o_vga_g.value),
            int(dut.o_vga_b.value),
        ),
        int(dut.o_vga_hs.value),
        int(dut.o_vga_vs.value),
    )
    check(got == want, f"{got} != {want}")


@cocotb.test()
async def test_random_pixels_latency_three(dut: ScanoutDut) -> None:
    """Cor, HS e VS saem alinhados, três ciclos depois."""
    await run_random(
        dut,
        int(dut.fb_width.value),
        int(dut.fb_height.value),
        int(dut.pixel_bits.value),
    )


@cocotb.test()
async def test_reset_and_disable(dut: ScanoutDut) -> None:
    """O reset leva ao repouso e a habilitação apaga as cores."""
    await reset(dut)
    dut.i_image.value = 1
    dut.i_enable.value = 0
    dut.i_hs.value = 0
    for _ in range(LATENCY + 2):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(int(dut.o_vga_hs.value) == 0, "HS acompanha a entrada")
    for channel in (dut.o_vga_r, dut.o_vga_g, dut.o_vga_b):
        check(int(channel.value) == 0, "desabilitada, a cor é preta")
    dut.i_rst.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(int(dut.o_vga_hs.value) == 1, "o reset leva HS a repouso")
    check(int(dut.o_vga_vs.value) == 1, "o reset leva VS a repouso")

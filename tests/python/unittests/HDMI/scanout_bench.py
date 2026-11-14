"""Bancada do caminho de pixel: memórias falsas e comparação."""

import random
from typing import Protocol

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.unittests.HDMI.hdmi_bench import expand_565
from tests.python.utils.check import check

CLOCK_NS = 10
FB_WIDTH = 8
FB_HEIGHT = 3
CYCLES = 400
LATENCY = 2
WORD_BITS = 32
DIRECT_BITS = 16
OUTPUTS = ("o_color", "o_lit", "o_visible", "o_hs", "o_vs")


class ScanoutDut(Protocol):
    """Sinais do caminho de pixel, das saídas para as entradas."""

    o_vs: LogicObject
    o_hs: LogicObject
    o_visible: LogicObject
    o_lit: LogicObject
    o_color: LogicArrayObject
    o_fb_addr: LogicArrayObject
    o_pal_addr: LogicArrayObject
    i_clk: LogicObject
    i_rst: LogicObject
    i_enable: LogicObject
    i_fb_data: LogicArrayObject
    i_pal_data: LogicArrayObject
    i_fb_x: LogicArrayObject
    i_fb_y: LogicArrayObject
    i_image: LogicObject
    i_visible: LogicObject
    i_hs: LogicObject
    i_vs: LogicObject


async def ram_models(
    dut: ScanoutDut, words: list[int], palette: list[int]
) -> None:
    """Memórias de leitura registrada do framebuffer e da paleta.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    words : list[int]
        Palavras do framebuffer.
    palette : list[int]
        Cores de 24 bits da paleta.
    """
    while True:
        await RisingEdge(dut.i_clk)
        fb_addr = int(dut.o_fb_addr.value)
        pal_addr = int(dut.o_pal_addr.value)
        await Timer(1, unit="ns")
        dut.i_fb_data.value = words[fb_addr]
        dut.i_pal_data.value = palette[pal_addr]


def pack_words(pixels: list[list[int]], bits: int) -> list[int]:
    """Empacota os pixels em palavras, o primeiro nos bits baixos.

    Parameters
    ----------
    pixels : list[list[int]]
        Valor de cada pixel do framebuffer, por linha.
    bits : int
        Bits de cada pixel.

    Returns
    -------
    list[int]
        As palavras na ordem do endereço.
    """
    per_word = WORD_BITS // bits
    flat = [p for row in pixels for p in row]
    return [
        sum(flat[i + k] << (k * bits) for k in range(per_word))
        for i in range(0, len(flat), per_word)
    ]


def drive_cycle(
    dut: ScanoutDut, rng: random.Random
) -> tuple[int, int, int, tuple[int, int, int, int]]:
    """Aplica coordenadas e sinais de controle sorteados.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    rng : random.Random
        Gerador do sorteio.

    Returns
    -------
    tuple[int, int, int, tuple[int, int, int, int]]
        Coluna, linha, habilitação e (imagem, área visível, HS, VS).
    """
    x, y = rng.randrange(FB_WIDTH), rng.randrange(FB_HEIGHT)
    enable = rng.randrange(2)
    control = (
        rng.randrange(2),
        rng.randrange(2),
        rng.randrange(2),
        rng.randrange(2),
    )
    dut.i_fb_x.value = x
    dut.i_fb_y.value = y
    dut.i_image.value = control[0]
    dut.i_visible.value = control[1]
    dut.i_hs.value = control[2]
    dut.i_vs.value = control[3]
    dut.i_enable.value = enable
    return x, y, enable, control


async def setup(
    dut: ScanoutDut, pixels: list[list[int]], bits: int, rng: random.Random
) -> list[int]:
    """Inicia o clock, as memórias falsas e solta o reset.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    pixels : list[list[int]]
        Valor de cada pixel do framebuffer, por linha.
    bits : int
        Bits de cada pixel.
    rng : random.Random
        Gerador que sorteia a paleta.

    Returns
    -------
    list[int]
        A paleta de 24 bits.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    palette = [rng.randrange(1 << 24) for _ in range(256)]
    dut.i_rst.value = 1
    dut.i_enable.value = 1
    for name in ("i_hs", "i_vs", "i_visible", "i_image"):
        getattr(dut, name).value = 0
    for name in ("i_fb_x", "i_fb_y", "i_fb_data", "i_pal_data"):
        getattr(dut, name).value = 0
    await Timer(1, unit="ns")
    cocotb.start_soon(ram_models(dut, pack_words(pixels, bits), palette))
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    return palette


def check_output(
    dut: ScanoutDut, cycle: int, want: tuple[int, int, int, int, int]
) -> None:
    """Confere as saídas do caminho de pixel.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    cycle : int
        Ciclo da conferência, para a mensagem.
    want : tuple[int, int, int, int, int]
        Cor, marca de imagem acesa, área visível, HS e VS esperados.
    """
    got = tuple(int(getattr(dut, name).value) for name in OUTPUTS)
    check(got == want, f"ciclo {cycle}: obtido {got}, esperado {want}")


def color_of(pixel: int, palette: list[int], bits: int) -> int:
    """Cor de 24 bits esperada para o valor de um pixel.

    Parameters
    ----------
    pixel : int
        Valor do pixel no framebuffer.
    palette : list[int]
        Paleta de 24 bits.
    bits : int
        Bits de cada pixel.

    Returns
    -------
    int
        O índice da paleta ou o RGB565, convertido em cor.
    """
    return expand_565(pixel) if bits == DIRECT_BITS else palette[pixel]


def expected(
    entry: tuple[int, tuple[int, int, int, int]], enable: int
) -> tuple[int, int, int, int, int]:
    """Saídas esperadas para a entrada de dois ciclos antes.

    Parameters
    ----------
    entry : tuple[int, tuple[int, int, int, int]]
        Cor e (imagem, área visível, HS, VS) daquela entrada.
    enable : int
        Habilitação do ciclo atual.

    Returns
    -------
    tuple[int, int, int, int, int]
        Cor, marca de imagem acesa, área visível, HS e VS.
    """
    color, (image, visible, hs, vs) = entry
    return color, image & enable, visible, hs, vs


async def run(
    dut: ScanoutDut, pixels: list[list[int]], bits: int, seed: int
) -> None:
    """Percorre coordenadas aleatórias e confere cada saída.

    A saída de um ciclo corresponde à entrada de dois ciclos antes, e
    a marca de imagem acesa usa a habilitação do próprio ciclo.

    Parameters
    ----------
    dut : ScanoutDut
        Caminho de pixel sob teste.
    pixels : list[list[int]]
        Valor de cada pixel do framebuffer, por linha.
    bits : int
        Bits de cada pixel.
    seed : int
        Semente do sorteio das coordenadas e dos sinais de controle.
    """
    rng = random.Random(seed)  # noqa: S311
    palette = await setup(dut, pixels, bits, rng)
    history: list[tuple[int, tuple[int, int, int, int]]] = []
    for cycle in range(CYCLES):
        x, y, enable, control = drive_cycle(dut, rng)
        color = color_of(pixels[y][x], palette, bits)
        history.append((color, control))
        await FallingEdge(dut.i_clk)
        if cycle >= LATENCY:
            want = expected(history[cycle - LATENCY], enable)
            check_output(dut, cycle, want)
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")

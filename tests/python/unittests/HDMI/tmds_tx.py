"""Transmissor TMDS completo: pixels paralelos até os quatro pares.

O teste liga os dois clocks do PLL (o de pixel e o cinco vezes mais
rápido), aplica um quadro curto com sincronismos e pixels de cor
conhecida e reconstrói os símbolos que saem pelos pinos, amostrando os
dois bits de cada ciclo rápido. O alinhamento vem do canal de clock, e
os símbolos dos canais de dados têm de conter, em ordem, a sequência
do codificador de referência, com os sincronismos no canal azul.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.utils.check import check
from tests.python.utils.dut import TmdsTxDut
from tests.python.utils.tmds_reference import (
    CLOCK_TOKEN,
    TOKEN_BITS,
    EncoderModel,
    find_run,
    symbols,
)

PIXEL_NS = 20
FAST_NS = 4
LANES = 4
CLOCK_LANE = 3
HOLD_RESET = 4
LEAD_BLANK = 6
TRAIL_BLANK = 8
ACTIVE = [0x00, 0xFF, 0x55, 0xAA, 0x0F, 0xF0, 0x80, 0x01, 0xC3, 0x3C]
SYNC_PAIRS = [(0, 0), (1, 0), (1, 1), (0, 1)]
GUARD_TOKENS = 3


def frame() -> list[tuple[int, int, int, int]]:
    """Monte os pixels do teste.

    Returns
    -------
    list[tuple[int, int, int, int]]
        Para cada ciclo de pixel, DE, HS, VS e o pixel RGB de 24 bits.
    """
    blank = [(0, h, v, 0) for h, v in SYNC_PAIRS] * 2
    lead = [(0, 0, 0, 0)] * LEAD_BLANK
    pixels = [
        (1, 0, 0, (b << 16) | ((255 - b) << 8) | (b ^ 0x5A)) for b in ACTIVE
    ]
    return lead + blank + pixels + [(0, 0, 0, 0)] * TRAIL_BLANK


async def drive(
    dut: TmdsTxDut, cycles: list[tuple[int, int, int, int]]
) -> None:
    """Aplique um pixel por borda do clock de pixel.

    Parameters
    ----------
    dut : TmdsTxDut
        Transmissor exercitado pelo teste.
    cycles : list[tuple[int, int, int, int]]
        Entradas de cada ciclo, na ordem DE, HS, VS e RGB.
    """
    for de, hsync, vsync, rgb in cycles:
        dut.i_de.value = de
        dut.i_hsync.value = hsync
        dut.i_vsync.value = vsync
        dut.i_rgb.value = rgb
        await RisingEdge(dut.i_clk_pixel)
        await Timer(1, unit="ns")


async def capture(dut: TmdsTxDut, fast_cycles: int) -> list[list[int]]:
    """Amostre os bits dos pinos, dois por ciclo rápido.

    Parameters
    ----------
    dut : TmdsTxDut
        Transmissor exercitado pelo teste.
    fast_cycles : int
        Número de ciclos do clock rápido a amostrar.

    Returns
    -------
    list[list[int]]
        Para cada canal (azul, verde, vermelho e clock), os bits na
        ordem de transmissão.
    """
    bits: list[list[int]] = [[] for _ in range(LANES)]
    for _ in range(fast_cycles):
        for edge in (RisingEdge, FallingEdge):
            await edge(dut.i_clk_x5)
            await Timer(1, unit="ns")
            data = dut.o_data.value
            levels = [int(data[lane]) for lane in range(LANES - 1)]
            levels.append(int(dut.o_clk.value))
            for lane, level in enumerate(levels):
                bits[lane].append(level)
    return bits


def clock_phase(stream: list[int]) -> int:
    """Ache a posição em que o símbolo do clock começa.

    Parameters
    ----------
    stream : list[int]
        Bits do canal de clock.

    Returns
    -------
    int
        Posição do primeiro símbolo completo do clock.

    Raises
    ------
    AssertionError
        Se o padrão do clock não aparece.
    """
    pattern = [(CLOCK_TOKEN >> i) & 1 for i in range(TOKEN_BITS)]
    for start in range(len(stream) - TOKEN_BITS):
        stop = start + TOKEN_BITS
        if stream[start:stop] == pattern:
            return start
    message = "o canal de clock não tem o padrão de cinco zeros e cinco uns"
    raise AssertionError(message)


def expected_tokens(
    cycles: list[tuple[int, int, int, int]],
) -> list[list[int]]:
    """Monte os símbolos que o modelo de referência envia.

    Parameters
    ----------
    cycles : list[tuple[int, int, int, int]]
        Entradas de cada ciclo, na ordem DE, HS, VS e RGB.

    Returns
    -------
    list[list[int]]
        Símbolos dos canais azul, verde e vermelho.
    """
    models = [EncoderModel() for _ in range(LANES - 1)]
    out: list[list[int]] = [[] for _ in range(LANES - 1)]
    for de, hsync, vsync, rgb in cycles:
        for lane, model in enumerate(models):
            byte = (rgb >> (8 * lane)) & 0xFF
            if de:
                out[lane].append(model.data(byte))
            elif lane == 0:
                out[lane].append(model.control(vsync, hsync))
            else:
                out[lane].append(model.control(0, 0))
    return out


async def start_clocks(dut: TmdsTxDut) -> None:
    """Ligue os clocks do PLL e reinicie o transmissor.

    Parameters
    ----------
    dut : TmdsTxDut
        Transmissor exercitado pelo teste.
    """
    dut.i_rst.value = 1
    dut.i_de.value = 0
    dut.i_hsync.value = 0
    dut.i_vsync.value = 0
    dut.i_rgb.value = 0
    cocotb.start_soon(Clock(dut.i_clk_pixel, PIXEL_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.i_clk_x5, FAST_NS, unit="ns").start())
    for _ in range(HOLD_RESET):
        await RisingEdge(dut.i_clk_pixel)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


@cocotb.test()
async def test_frame_reaches_the_pins(dut: TmdsTxDut) -> None:
    """Os símbolos do quadro saem pelos três canais."""
    await start_clocks(dut)
    cycles = frame()
    total = len(cycles) + GUARD_TOKENS
    watcher = cocotb.start_soon(capture(dut, total * TOKEN_BITS // 2))
    await drive(dut, cycles)
    bits = await watcher
    phase = clock_phase(bits[CLOCK_LANE])
    clock_words = symbols(bits[CLOCK_LANE], phase)
    check(
        all(word == CLOCK_TOKEN for word in clock_words),
        "o canal de clock repete o símbolo",
    )
    want = expected_tokens(cycles)
    first = find_run(symbols(bits[0], phase), want[0])
    if first is None:
        message = "a sequência de símbolos esperada não saiu pelo canal"
        raise AssertionError(message)
    for lane in range(LANES - 1):
        last = first + len(want[lane])
        got = symbols(bits[lane], phase)[first:last]
        check(got == want[lane], f"canal {lane} difere do modelo")

"""Serializador TMDS: símbolos de 10 bits em dois bits por ciclo rápido.

O teste liga os dois clocks do PLL, apresenta uma sequência de símbolos
conhecidos, um por período de pixel, e amostra a saída em cada ciclo do
clock rápido. Os bits têm de sair a partir do bit 0, o bit 2k no
primeiro valor do ciclo k e o bit 2k+1 no segundo, e cada símbolo tem de
sair inteiro, na ordem em que entrou.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.check import check
from tests.python.utils.dut import TmdsSerializerDut
from tests.python.utils.tmds_reference import TOKEN_BITS, find_run, symbols

PIXEL_NS = 20
FAST_NS = 4
TOKENS = [0x3FF, 0x000, 0x2AA, 0x155, 0x001, 0x200, 0x354, 0x0AB, 0x1D5]
FAST_PER_PIXEL = TOKEN_BITS // 2
SETTLE_PIXELS = 4
TAIL_PIXELS = 3


async def capture(dut: TmdsSerializerDut, fast_cycles: int) -> list[int]:
    """Amostre a saída depois de cada borda de subida do clock rápido.

    Parameters
    ----------
    dut : TmdsSerializerDut
        Serializador exercitado pelo teste.
    fast_cycles : int
        Número de ciclos a amostrar.

    Returns
    -------
    list[int]
        Os bits na ordem de transmissão.
    """
    bits: list[int] = []
    for _ in range(fast_cycles):
        await RisingEdge(dut.i_clk_x5)
        await Timer(1, unit="ns")
        bits += [int(dut.o_h.value), int(dut.o_l.value)]
    return bits


@cocotb.test()
async def test_symbols_leave_whole_and_in_order(
    dut: TmdsSerializerDut,
) -> None:
    """Cada símbolo sai inteiro, com o bit 0 primeiro, e na ordem."""
    dut.i_token.value = 0
    cocotb.start_soon(Clock(dut.i_clk_pixel, PIXEL_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.i_clk_x5, FAST_NS, unit="ns").start())
    total = len(TOKENS) + SETTLE_PIXELS + TAIL_PIXELS
    watcher = cocotb.start_soon(capture(dut, total * FAST_PER_PIXEL))
    for _ in range(SETTLE_PIXELS):
        await RisingEdge(dut.i_clk_pixel)
    for token in TOKENS:
        dut.i_token.value = token
        await RisingEdge(dut.i_clk_pixel)
        await Timer(1, unit="ns")
    bits = await watcher
    found = [
        offset
        for offset in range(TOKEN_BITS)
        if find_run(symbols(bits, offset), TOKENS) is not None
    ]
    check(len(found) == 1, f"alinhamentos que reproduzem a sequência: {found}")

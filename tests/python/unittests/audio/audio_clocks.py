"""Áudio I2S no modo mestre: taxas dos clocks gerados."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.audio.common import (
    BCLK_DIV,
    CLK_EN,
    CONTROL,
    SLOT_BITS,
    XCK_STEP,
    setup,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioDut

SYSTEM_HZ = 50_000_000
WINDOW = 100_000


async def count_edges(dut: AudioDut, cycles: int) -> tuple[int, int, int]:
    """Conte as bordas de subida de XCK, BCLK e LRCK numa janela.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.
    cycles : int
        Ciclos do clock do sistema da janela.

    Returns
    -------
    tuple[int, int, int]
        Bordas de XCK, BCLK e LRCK.
    """
    counts = [0, 0, 0]

    async def watch(index: int, signal: object) -> None:
        while True:
            await RisingEdge(signal)  # type: ignore[arg-type]
            counts[index] += 1

    tasks = [
        cocotb.start_soon(watch(0, dut.o_xck)),
        cocotb.start_soon(watch(1, dut.o_bclk)),
        cocotb.start_soon(watch(2, dut.o_daclrck)),
    ]
    await bus.cycles(dut, cycles)
    for task in tasks:
        task.cancel()
    return counts[0], counts[1], counts[2]


@cocotb.test()
async def default_rates(dut: AudioDut) -> None:
    """Gere 12,288 MHz, 3,072 MHz e 48 kHz a partir de 50 MHz."""
    await setup(dut)
    await bus.write(dut, CONTROL, CLK_EN)
    xck, bclk, lrck = await count_edges(dut, WINDOW)
    want_xck = WINDOW * 12_288_000 // SYSTEM_HZ
    check(abs(xck - want_xck) <= 1, f"XCK {xck} contra {want_xck}")
    check(abs(bclk - xck // 4) <= 1, f"BCLK {bclk}")
    check(abs(lrck - bclk // 64) <= 1, f"LRCK {lrck}")
    check(int(dut.o_adclrck.value) == int(dut.o_daclrck.value), "iguais")
    check(int(dut.o_bclk_oe.value) == 1, "BCLK dirigido")


@cocotb.test()
async def reprogrammed_to_44100(dut: AudioDut) -> None:
    """Reprograme os divisores para 11,2896 MHz e 44,1 kHz."""
    await setup(dut)
    await bus.write(dut, XCK_STEP, 22_579_200)
    await bus.write(dut, BCLK_DIV, 4)
    await bus.write(dut, SLOT_BITS, 32)
    await bus.write(dut, CONTROL, CLK_EN)
    xck, _, lrck = await count_edges(dut, WINDOW)
    want_xck = WINDOW * 11_289_600 // SYSTEM_HZ
    check(abs(xck - want_xck) <= 1, f"XCK {xck} contra {want_xck}")
    want_lrck = WINDOW * 44_100 // SYSTEM_HZ
    check(abs(lrck - want_lrck) <= 1, f"LRCK {lrck} contra {want_lrck}")
    await bus.write(dut, CONTROL, 0)
    await bus.cycles(dut, 4)
    check(int(dut.o_xck.value) == 0, "parado desabilitado")

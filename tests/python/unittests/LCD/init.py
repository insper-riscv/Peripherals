"""lcd_init: espera de energização e os sete comandos da sequência."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdInitDut

CLOCK_HZ = 1_000_000
POWER_CYCLES = 30
EXEC_CYCLES = 4
LONG_CYCLES = 9
WAKE_FIRST_CYCLES = 5000
WAKE_CYCLES = 200
BYTES = [0x30, 0x30, 0x30, 0x38, 0x0C, 0x01, 0x06]
DELAYS = [
    WAKE_FIRST_CYCLES,
    WAKE_CYCLES,
    WAKE_CYCLES,
    EXEC_CYCLES,
    EXEC_CYCLES,
    LONG_CYCLES,
    EXEC_CYCLES,
]
BUSY_CYCLES = 3
LIMIT = 20_000


async def start(dut: LcdInitDut) -> None:
    """Aplica o reset com a camada física livre.

    Parameters
    ----------
    dut : LcdInitDut
        Inicialização sob teste.
    """
    dut.i_phy_ready.value = 1
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def _drive_sequence(
    dut: LcdInitDut,
) -> tuple[list[tuple[int, int]], int | None]:
    """Atende a sequência até o fim e devolve o que foi enviado.

    Parameters
    ----------
    dut : LcdInitDut
        Sequência de inicialização sob teste.

    Returns
    -------
    tuple[list[tuple[int, int]], int | None]
        Pares dado e atraso enviados, e o ciclo do primeiro envio.
    """
    sent: list[tuple[int, int]] = []
    first_start = None
    await Timer(1, unit="ns")
    for cycle in range(LIMIT):
        if int(dut.o_busy.value) == 0:
            break
        if int(dut.o_start.value):
            first_start = cycle if first_start is None else first_start
            sent.append((int(dut.o_data.value), int(dut.o_delay.value)))
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            dut.i_phy_ready.value = 0
            await bus.cycles(dut, BUSY_CYCLES)
            dut.i_phy_ready.value = 1
            await Timer(1, unit="ns")
            continue
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    return sent, first_start


@cocotb.test()
async def runs_the_sequence(dut: LcdInitDut) -> None:
    """Espere a energização, envie os sete comandos e termine."""
    await start(dut)
    check(int(dut.o_busy.value) == 1, "ocupado depois do reset")
    sent, first_start = await _drive_sequence(dut)
    check(int(dut.o_busy.value) == 0, "a sequência terminou")
    check([row[0] for row in sent] == BYTES, f"bytes {sent}")
    check([row[1] for row in sent] == DELAYS, f"atrasos {sent}")
    check(
        first_start is not None and first_start >= POWER_CYCLES - 1,
        "energização",
    )
    await bus.cycles(dut, 5)
    check(int(dut.o_start.value) == 0, "nada mais é enviado")

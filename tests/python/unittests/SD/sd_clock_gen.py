"""Gerador de SD_CLK: período, parada em repouso e pulsos de borda."""

from itertools import pairwise

import cocotb
from cocotb.triggers import Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import SdClockGenDut

DIVIDERS = (0, 1, 2, 7)
EDGES = 5
DIVIDER_STOP = 3
FIRST_LIMIT = 100
IDLE_CYCLES = 40


async def setup(dut: SdClockGenDut, divider: int) -> None:
    """Reinicie o gerador com um divisor e sem pedido de clock.

    Parameters
    ----------
    dut : SdClockGenDut
        Gerador exercitado pelo teste.
    divider : int
        Divisor de meio período.
    """
    dut.i_divider.value = divider
    dut.i_run.value = 0
    await bus.hold_reset(dut, hold=2)


async def sample(dut: SdClockGenDut) -> tuple[int, int, int, int]:
    """Avance um ciclo e leia nível, pulsos e o nível seguinte.

    Parameters
    ----------
    dut : SdClockGenDut
        Gerador exercitado pelo teste.

    Returns
    -------
    tuple[int, int, int, int]
        Nível de SD_CLK, pulso de subida, pulso de descida e o nível de
        SD_CLK depois da borda do clock do módulo.
    """
    level = int(dut.o_sclk.value)
    rise = int(dut.o_rise.value)
    fall = int(dut.o_fall.value)
    await bus.cycles(dut, 1)
    return level, rise, fall, int(dut.o_sclk.value)


async def check_cycle(dut: SdClockGenDut) -> bool:
    """Avance um ciclo e confira os pulsos contra a borda de SD_CLK.

    Parameters
    ----------
    dut : SdClockGenDut
        Gerador exercitado pelo teste.

    Returns
    -------
    bool
        Verdadeiro se o ciclo termina com a borda de subida.
    """
    level, rise, fall, after = await sample(dut)
    check(not (rise and fall), "pulsos exclusivos")
    check(bool(rise) == (level == 0 and after == 1), "pulso de subida")
    check(bool(fall) == (level == 1 and after == 0), "pulso de descida")
    return bool(rise)


@cocotb.test()
async def test_period_and_edge_pulses(dut: SdClockGenDut) -> None:
    """O período é 2 * (divisor + 1) e os pulsos antecedem a borda."""
    for divider in DIVIDERS:
        await setup(dut, divider)
        dut.i_run.value = 1
        await Timer(1, unit="ns")
        rises: list[int] = []
        for cycle in range(EDGES * 2 * (divider + 1) + 4):
            rise = await check_cycle(dut)
            if rise:
                rises.append(cycle)
        gaps = {b - a for a, b in pairwise(rises)}
        check(len(rises) >= EDGES, f"divisor {divider}: poucas bordas")
        check(gaps == {2 * (divider + 1)}, f"divisor {divider}: {gaps}")
        dut.i_run.value = 0


@cocotb.test()
async def test_clock_stops_low_without_request(dut: SdClockGenDut) -> None:
    """Sem pedido o clock termina o nível alto e fica baixo."""
    await setup(dut, DIVIDER_STOP)
    dut.i_run.value = 1
    await bus.cycles(dut, 20)
    dut.i_run.value = 0
    for _ in range(2 * (DIVIDER_STOP + 1) + 2):
        await bus.cycles(dut, 1)
    for _ in range(IDLE_CYCLES):
        level, rise, fall, _ = await sample(dut)
        check(level == 0 and rise == 0 and fall == 0, "clock parado")
    dut.i_run.value = 1
    await Timer(1, unit="ns")
    first = 0
    while int(dut.o_sclk.value) == 0 and first < FIRST_LIMIT:
        await bus.cycles(dut, 1)
        first += 1
    check(first == DIVIDER_STOP + 1, f"a primeira subida levou {first} ciclos")

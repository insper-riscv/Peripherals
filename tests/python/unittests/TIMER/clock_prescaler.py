"""CLOCK_PRESCALER: a one-cycle tick every prescaler count."""

import itertools

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import PrescalerDut

PERIOD_NS = 10
OBSERVED_TICKS = 5
RESET_CYCLES = 3


async def _start(dut: PrescalerDut, prescaler: int) -> None:
    """Start the clock, hold the reset and release it.

    Parameters
    ----------
    dut : PrescalerDut
        The design under test.
    prescaler : int
        Value of the prescaler register.
    """
    dut.i_prescaler_in.value = prescaler
    await bus.hold_reset(dut, RESET_CYCLES)


async def _tick_cycles(dut: PrescalerDut, cycles: int) -> list[int]:
    """Sample the tick after each of a number of clock edges.

    Parameters
    ----------
    dut : PrescalerDut
        The design under test.
    cycles : int
        Number of edges to sample.

    Returns
    -------
    list[int]
        The tick value after each edge.
    """
    samples: list[int] = []
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        samples.append(int(dut.o_tick.value))
    return samples


@cocotb.test()
async def test_no_tick_while_in_reset(dut: PrescalerDut) -> None:
    """The tick stays low while the reset is held."""
    dut.i_prescaler_in.value = 0
    dut.i_rst.value = 1
    cocotb.start_soon(Clock(dut.i_clk, PERIOD_NS, unit="ns").start())
    samples = await _tick_cycles(dut, RESET_CYCLES + 2)
    check(sum(samples[1:]) == 0, f"tick during reset: {samples}")


@cocotb.test()
async def test_tick_is_a_single_cycle_pulse(dut: PrescalerDut) -> None:
    """Every tick lasts exactly one clock cycle."""
    await _start(dut, 4)
    samples = await _tick_cycles(dut, 40)
    ticks = sum(samples)
    check(ticks >= OBSERVED_TICKS, f"too few ticks: {samples}")
    check(
        all(not (a and b) for a, b in itertools.pairwise(samples)),
        f"tick longer than one cycle: {samples}",
    )


@cocotb.test()
async def test_period_follows_the_prescaler(dut: PrescalerDut) -> None:
    """The distance between ticks is the prescaler plus one cycle."""
    for prescaler in (1, 3, 7):
        await _start(dut, prescaler)
        samples = await _tick_cycles(dut, 12 * (prescaler + 1))
        positions = [i for i, tick in enumerate(samples) if tick]
        check(len(positions) >= OBSERVED_TICKS, f"ticks: {positions}")
        gaps = {b - a for a, b in itertools.pairwise(positions)}
        check(
            gaps == {prescaler + 1},
            f"prescaler {prescaler}: gaps {gaps}",
        )


@cocotb.test()
async def test_zero_prescaler_ticks_every_cycle(dut: PrescalerDut) -> None:
    """A zero prescaler keeps the tick high."""
    await _start(dut, 0)
    samples = await _tick_cycles(dut, 20)
    check(all(samples[2:]), f"ticks: {samples}")

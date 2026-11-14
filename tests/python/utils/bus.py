"""The bus protocol of the peripherals, from the testbench side.

A write is one cycle with write=1: the register changes at the clock
edge. A read is one cycle with read=1: data_out is sampled before the
edge, which is also when the peripheral clears a read-to-clear status.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.dut import (
    BusDut,
    ClockedDut,
    DecoderDut,
    ResettableDut,
)


def _set_read(dut: BusDut, value: int) -> None:
    """Drive the read strobe when the peripheral has one.

    The CLINT has no read strobe, because a read has no side effect.

    Parameters
    ----------
    dut : BusDut
        The design under test.
    value : int
        Value of the read strobe.
    """
    if hasattr(dut, "i_read"):
        dut.i_read.value = value


async def hold_reset(
    dut: ResettableDut, hold: int = 3, period_ns: int = 10
) -> None:
    """Start the clock, hold the reset for a few edges and release it.

    Parameters
    ----------
    dut : ResettableDut
        The design under test.
    hold : int
        Number of clock edges to hold the reset.
    period_ns : int
        Clock period in nanoseconds.
    """
    cocotb.start_soon(Clock(dut.i_clk, period_ns, unit="ns").start())
    dut.i_rst.value = 1
    for _ in range(hold):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def reset(dut: BusDut, hold: int = 3, period_ns: int = 10) -> None:
    """Start the clock and hold clear for a few edges.

    Some registers clear on the edge, so clear is held for several.

    Parameters
    ----------
    dut : BusDut
        The design under test.
    hold : int
        Number of clock edges to hold the reset.
    period_ns : int
        Clock period in nanoseconds.
    """
    set_inputs(dut, i_write=0, i_address=0, i_data_in=0)
    _set_read(dut, 0)
    await hold_reset(dut, hold, period_ns)
    await cycles(dut, 1)


def set_inputs(dut: ClockedDut, **values: int) -> None:
    """Drive several inputs of the design at once.

    Parameters
    ----------
    dut : ClockedDut
        The design under test.
    **values : int
        Value of each input, by port name.
    """
    for name, value in values.items():
        getattr(dut, name).value = value


async def pulse(dut: ClockedDut, *names: str) -> None:
    """Raise inputs for exactly one clock edge.

    Parameters
    ----------
    dut : ClockedDut
        The design under test.
    *names : str
        Names of the input ports.
    """
    for name in names:
        getattr(dut, name).value = 1
    await cycles(dut, 1)
    for name in names:
        getattr(dut, name).value = 0


async def drive(
    dut: DecoderDut, address: int, write_strobe: int, read_strobe: int
) -> None:
    """Drive the bus inputs of a decoder and let them settle.

    Parameters
    ----------
    dut : DecoderDut
        The design under test.
    address : int
        Register address.
    write_strobe : int
        Value of the write strobe.
    read_strobe : int
        Value of the read strobe.
    """
    dut.i_address.value = address
    dut.i_write.value = write_strobe
    dut.i_read.value = read_strobe
    await Timer(1, unit="ns")


async def write(dut: BusDut, address: int, value: int) -> None:
    """Write one register in one cycle.

    Parameters
    ----------
    dut : BusDut
        The design under test.
    address : int
        Register address.
    value : int
        Value to write.
    """
    dut.i_address.value = address
    dut.i_data_in.value = value
    dut.i_write.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_write.value = 0


async def read(dut: BusDut, address: int) -> int:
    """Read one register in one cycle.

    Parameters
    ----------
    dut : BusDut
        The design under test.
    address : int
        Register address.

    Returns
    -------
    int
        The value sampled before the clock edge.
    """
    dut.i_address.value = address
    _set_read(dut, 1)
    await Timer(1, unit="ns")
    value = int(dut.o_data_out.value)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    _set_read(dut, 0)
    return value


async def cycles(dut: ClockedDut, n: int) -> None:
    """Wait for a number of clock edges.

    Parameters
    ----------
    dut : ClockedDut
        The design under test.
    n : int
        Number of clock edges to wait.
    """
    for _ in range(n):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")

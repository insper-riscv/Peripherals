"""The bus protocol of the peripherals, from the testbench side.

A write is one cycle with write=1: the register changes at the clock
edge. A read is one cycle with read=1: data_out is sampled before the
edge, which is also when the peripheral clears a read-to-clear status.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.dut import BusDut


async def reset(dut: BusDut, cycles: int = 3) -> None:
    """Start the clock and hold clear for a few edges.

    Some registers clear on the edge, so clear is held for several.

    Parameters
    ----------
    dut : BusDut
        The design under test.
    cycles : int
        Number of clock edges to hold the reset.
    """
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_write.value = 0
    dut.i_read.value = 0
    dut.i_address.value = 0
    dut.i_data_in.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)
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
    dut.i_read.value = 1
    await Timer(1, unit="ns")
    value = int(dut.o_data_out.value)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_read.value = 0
    return value


async def cycles(dut: BusDut, n: int) -> None:
    """Wait for a number of clock edges.

    Parameters
    ----------
    dut : BusDut
        The design under test.
    n : int
        Number of clock edges to wait.
    """
    for _ in range(n):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")

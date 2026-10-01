"""The bus protocol of the peripherals, from the testbench side.

A write is one cycle with write=1: the register changes at the clock edge. A read
is one cycle with read=1: data_out is sampled before the edge, which is also when
the peripheral clears a read-to-clear status.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset(dut, cycles=3):
    """Start the clock and hold clear for a few edges (some registers clear on the edge)."""
    cocotb.start_soon(Clock(dut.clock, 10, unit="ns").start())
    dut.clear.value = 1
    dut.write.value = 0
    dut.read.value = 0
    dut.address.value = 0
    dut.data_in.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.clear.value = 0
    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")


async def write(dut, address, value):
    dut.address.value = address
    dut.data_in.value = value
    dut.write.value = 1
    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.write.value = 0


async def read(dut, address):
    dut.address.value = address
    dut.read.value = 1
    await Timer(1, unit="ns")
    value = int(dut.data_out.value)
    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.read.value = 0
    return value


async def cycles(dut, n):
    for _ in range(n):
        await RisingEdge(dut.clock)
    await Timer(1, unit="ns")

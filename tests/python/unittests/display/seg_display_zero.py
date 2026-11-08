"""The display register without digits (seg_display_zero_tb).

The module has no register and no segment: a write is lost and the read
answers zero.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut

CYCLES = 4


@cocotb.test()
async def test_zero_digit_display_stores_nothing(dut: Dut):
    """A write is lost, the read is zero and the ports have no bit."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_we.value = 0
    dut.i_wdata.value = 0
    for _ in range(CYCLES):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    dut.i_wdata.value = 0xFFFFFFFF
    dut.i_we.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_we.value = 0
    await Timer(1, unit="ns")
    check_equal(int(dut.o_rdata.value), 0, "the read answers zero")
    check_equal(int(dut.o_hex_len.value), 0, "no segment")
    check_equal(int(dut.o_value_len.value), 0, "no value bit")

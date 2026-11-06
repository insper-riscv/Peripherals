"""GPIO without pins (gpio_zero_tb, data_width zero).

The module has no register and no interrupt: it elaborates, answers
nothing and never raises a request.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.check import check
from tests.python.unittests.dut import Dut

CYCLES = 6


@cocotb.test()
async def test_zero_width_gpio_is_silent(dut: Dut) -> None:
    """Writes and reads change nothing and the request stays low."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_write.value = 0
    dut.i_read.value = 0
    dut.i_address.value = 0
    for _ in range(CYCLES):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    for address in range(16):
        dut.i_address.value = address
        dut.i_write.value = 1
        await RisingEdge(dut.i_clk)
        dut.i_write.value = 0
        dut.i_read.value = 1
        await RisingEdge(dut.i_clk)
        dut.i_read.value = 0
        await Timer(1, unit="ns")
        check(int(dut.o_irq.value) == 0, f"request at address {address}")
    check(int(dut.o_data_len.value) == 0, "the data read has no bit")
    check(int(dut.o_pins_len.value) == 0, "there is no pin")

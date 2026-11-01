"""Timing check for UART's production 50 MHz / 115200-baud defaults."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout
from cocotb.utils import get_sim_time


TX_DATA = 0
CLOCK_PERIOD_NS = 20
BAUD_RATE = 115_200


async def reset_50_mhz(dut):
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_PERIOD_NS, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_write.value = 0
    dut.i_read.value = 0
    dut.i_address.value = 0
    dut.i_data_in.value = 0
    dut.i_uart_rx.value = 1
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


@cocotb.test()
async def test_default_generics_generate_115200_baud_at_50_mhz(dut):
    await reset_50_mhz(dut)

    start_edge = cocotb.start_soon(with_timeout(FallingEdge(dut.o_uart_tx), 20, "us"))
    dut.i_address.value = TX_DATA
    dut.i_data_in.value = 0x00
    dut.i_write.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_write.value = 0

    await start_edge
    start_ns = float(get_sim_time(unit="ns"))
    await with_timeout(RisingEdge(dut.o_uart_tx), 100, "us")
    stop_ns = float(get_sim_time(unit="ns"))

    # For 0x00, the line remains low for the start bit plus eight zero data
    # bits, then rises at the beginning of the stop bit: exactly nine bits.
    expected_ns = 9 * 1_000_000_000 / BAUD_RATE
    measured_ns = stop_ns - start_ns
    assert abs(measured_ns - expected_ns) <= 2 * CLOCK_PERIOD_NS, (
        f"measured {measured_ns} ns for nine bits, expected {expected_ns} ns"
    )

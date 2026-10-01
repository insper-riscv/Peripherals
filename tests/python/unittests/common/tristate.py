"""TRISTATE_BUFFER_1BIT: drives the data when enabled, releases the line ('Z') when not."""

import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def test_tristate_drives_or_releases(dut):
    for data in (0, 1):
        dut.data_in.value = data
        dut.enable.value = 1
        await Timer(1, unit="ns")
        assert str(dut.data_out.value) == str(data), f"enabled, data={data}"
        dut.enable.value = 0
        await Timer(1, unit="ns")
        assert str(dut.data_out.value) == "Z", f"disabled, data={data}"

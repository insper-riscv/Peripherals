"""tristate_buffer_1bit: drives the data when enabled, releases the line ('Z') when not."""

import cocotb
from cocotb.triggers import Timer


@cocotb.test()
async def test_tristate_drives_or_releases(dut):
    for data in (0, 1):
        dut.i_d.value = data
        dut.i_enable.value = 1
        await Timer(1, unit="ns")
        assert str(dut.o_d.value) == str(data), f"enabled, data={data}"
        dut.i_enable.value = 0
        await Timer(1, unit="ns")
        assert str(dut.o_d.value) == "Z", f"disabled, data={data}"

"""Periférico HDMI sem sequenciador: o barramento I2C fica livre."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.HDMI import hdmi_bench as bench
from tests.python.unittests.HDMI.hdmi_bench import TxDut
from tests.python.utils.check import check

QUIET_CYCLES = 3000


@cocotb.test()
async def test_i2c_pins_stay_released(dut: TxDut) -> None:
    """Sem o sequenciador os pinos ficam livres, mesmo com reinício."""
    await bench.start(dut)
    status = await bench.read(dut, bench.HDMI_STATUS)
    check(status & bench.ST_INIT == 0, "sequenciador ausente")
    await bench.write(dut, bench.SEQ_CTRL, 1)
    for _ in range(QUIET_CYCLES):
        await RisingEdge(dut.i_clk)
        check(int(dut.o_i2c_sda_oe.value) == 0, "SDA liberada")
        check(int(dut.o_i2c_scl_oe.value) == 0, "SCL liberada")
    status = await bench.read(dut, bench.HDMI_STATUS)
    check(status & (bench.ST_BUSY | bench.ST_DONE) == 0, "estado parado")
    check(await bench.read(dut, bench.SEQ_COUNT) == 0, "contadores zerados")

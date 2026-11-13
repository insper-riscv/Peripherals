"""HDMI nos modos CEA-861: medida da temporização da saída."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.HDMI import hdmi_bench as bench
from tests.python.unittests.HDMI.hdmi_bench import TxDut
from tests.python.unittests.HDMI.monitor import EdgeLog, check_edges, log_edges
from tests.python.utils.check import check


@cocotb.test()
async def test_cea_mode_timing(dut: TxDut) -> None:
    """Linha, quadro, pulsos, polaridades e pórticos do modo CEA-861."""
    timing = bench.timing_of(dut)
    vic = int(dut.mode_id.value)
    check(vic in bench.PIXEL_PERIOD_PS, f"modo CEA-861 {vic} desconhecido")
    period_ps = bench.PIXEL_PERIOD_PS[vic]
    await bench.start(dut, pixel_ps=period_ps, release=False)
    geo_khz = await bench.read(dut, bench.PIXEL_KHZ)
    check(geo_khz > 0, "clock de pixel em kHz")
    mode = await bench.read(dut, bench.HDMI_MODE)
    check(mode & 0xFF == vic, "número do modo no registrador")
    log = EdgeLog()
    cocotb.start_soon(log_edges(dut, log))
    dut.i_rst.value = 0
    for _ in range(int(2.4 * timing.frame_clocks)):
        await RisingEdge(dut.i_pixel_clk)
    check_edges(log, timing, period_ps)

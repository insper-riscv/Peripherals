"""The scan clock of a Virtual JTAG instance, from the testbench."""

from cocotb.triggers import Timer

from tests.python.utils.dut import JtagDut

HALF_TCK_NS = 40


async def tck(dut: JtagDut, state: str = "", ir: int | None = None) -> None:
    """Give one TCK pulse in a scan state.

    Parameters
    ----------
    dut : JtagDut
        The design under test.
    state : str
        One of cdr, sdr, udr, or empty for none.
    ir : int | None
        An instruction to load through the update-IR state.
    """
    if ir is not None:
        dut.i_ir_in.value = ir
    dut.i_state_cdr.value = int(state == "cdr")
    dut.i_state_sdr.value = int(state == "sdr")
    dut.i_state_udr.value = int(state == "udr")
    dut.i_state_uir.value = int(ir is not None)
    dut.i_tck.value = 0
    await Timer(HALF_TCK_NS, unit="ns")
    dut.i_tck.value = 1
    await Timer(HALF_TCK_NS, unit="ns")
    dut.i_tck.value = 0
    dut.i_state_cdr.value = 0
    dut.i_state_sdr.value = 0
    dut.i_state_udr.value = 0
    dut.i_state_uir.value = 0

"""The scan clock of a Virtual JTAG instance, from the testbench."""

from cocotb.triggers import Timer

from tests.python.utils.dut import JtagDut, JtagScanDut

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


async def scan(dut: JtagScanDut, word: int, bits: int) -> int:
    """Shift a data register once, from capture to update.

    Parameters
    ----------
    dut : JtagScanDut
        The design under test.
    word : int
        The bits shifted in, the least significant first.
    bits : int
        Length of the register in bits.

    Returns
    -------
    int
        The bits shifted out, the first in the least significant.
    """
    await tck(dut, "cdr")
    out = 0
    for i in range(bits):
        dut.i_tdi.value = (word >> i) & 1
        await Timer(1, unit="ns")
        out |= int(dut.o_tdo.value) << i
        await tck(dut, "sdr")
    await tck(dut, "udr")
    return out

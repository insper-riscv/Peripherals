"""PS2_MOUSE_OPERATION_DECODER: the register map of the mouse."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.PS2.mouse.registers import (
    BUTTONS,
    CONTROL,
    DX,
    DY,
    STATUS,
)
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MouseOperationDecoderDut

ADDRESSES = 8
RD_SEL = {STATUS: 0, DX: 1, DY: 2, BUTTONS: 3, CONTROL: 4}
RESERVED_SEL = 0b111


async def drive(
    dut: MouseOperationDecoderDut, address: int, write: int, read: int
) -> None:
    """Drive the bus inputs of the decoder and let them settle.

    Parameters
    ----------
    dut : MouseOperationDecoderDut
        The design under test.
    address : int
        Register address.
    write : int
        Value of the write strobe.
    read : int
        Value of the read strobe.
    """
    dut.i_address.value = address
    dut.i_write.value = write
    dut.i_read.value = read
    await Timer(1, unit="ns")


@cocotb.test()
async def test_read_selector(dut: MouseOperationDecoderDut) -> None:
    """Every address selects its register; the rest select zero."""
    for address in range(ADDRESSES):
        await drive(dut, address, 0, 0)
        want = RD_SEL.get(address, RESERVED_SEL)
        check_equal(int(dut.o_rd_sel.value), want)


@cocotb.test()
async def test_read_pulses(dut: MouseOperationDecoderDut) -> None:
    """A read pulses the clear of its register and of no other."""
    for address in range(ADDRESSES):
        await drive(dut, address, 0, 1)
        check(int(dut.o_status_read.value) == (address == STATUS))
        check(int(dut.o_dx_read.value) == (address == DX))
        check(int(dut.o_dy_read.value) == (address == DY))
        check(int(dut.o_control_write.value) == 0)


@cocotb.test()
async def test_write_pulse(dut: MouseOperationDecoderDut) -> None:
    """Only a write to CONTROL pulses the control write."""
    for address in range(ADDRESSES):
        await drive(dut, address, 1, 0)
        check(int(dut.o_control_write.value) == (address == CONTROL))
        check(int(dut.o_status_read.value) == 0)
        check(int(dut.o_dx_read.value) == 0)
        check(int(dut.o_dy_read.value) == 0)


@cocotb.test()
async def test_idle(dut: MouseOperationDecoderDut) -> None:
    """With no strobe no pulse comes out."""
    for address in range(ADDRESSES):
        await drive(dut, address, 0, 0)
        check(int(dut.o_status_read.value) == 0)
        check(int(dut.o_dx_read.value) == 0)
        check(int(dut.o_dy_read.value) == 0)
        check(int(dut.o_control_write.value) == 0)

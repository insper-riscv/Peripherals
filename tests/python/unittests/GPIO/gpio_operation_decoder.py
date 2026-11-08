"""GPIO_OPERATION_DECODER: the register map of the GPIO."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioDecoderDut

# wr_en bits: 0 DIR, 1 LOAD_OUT, 2 BIT_OUT, 3 IRQ_MASK, 4 RISE_MASK,
# 5 FALL_MASK, 6 IRQ_CLR (read), 7 LEVEL_MASK
DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL = 0, 1, 2, 3, 4
IRQ_MASK, RISE_MASK, FALL_MASK, IRQ_STAT, PINS, LEVEL_MASK = 5, 6, 7, 8, 9, 10
IRQ_CLEAR_BIT = 6
ADDRESSES = 16
# address -> write-enable bit it raises on a write
WRITE_BIT = {
    DIR: 0,
    OUT_LOAD: 1,
    OUT_SET: 2,
    OUT_CLR: 2,
    OUT_TGL: 2,
    IRQ_MASK: 3,
    RISE_MASK: 4,
    FALL_MASK: 5,
    LEVEL_MASK: 7,
}
WR_OP = {OUT_LOAD: 0b00, OUT_SET: 0b01, OUT_CLR: 0b10, OUT_TGL: 0b11}
RD_SEL = {
    DIR: 0b000,
    OUT_LOAD: 0b001,
    OUT_SET: 0b001,
    OUT_CLR: 0b001,
    OUT_TGL: 0b001,
    PINS: 0b010,
    IRQ_STAT: 0b011,
    IRQ_MASK: 0b100,
    RISE_MASK: 0b101,
    FALL_MASK: 0b110,
    LEVEL_MASK: 0b111,
}
RD_SEL_UNMAPPED = 0b111


async def _apply(
    dut: GpioDecoderDut, address: int, write: int, read: int
) -> tuple[int, int, int]:
    """Drive one bus operation and sample the decoder outputs.

    Parameters
    ----------
    dut : GpioDecoderDut
        The design under test.
    address : int
        Register address.
    write : int
        Value of the write strobe.
    read : int
        Value of the read strobe.

    Returns
    -------
    tuple[int, int, int]
        The wr_en, wr_op and rd_sel outputs.
    """
    await bus.drive(dut, address, write, read)
    return (
        int(dut.o_wr_en.value),
        int(dut.o_wr_op.value),
        int(dut.o_rd_sel.value),
    )


@cocotb.test()
async def test_writes_raise_one_enable(dut: GpioDecoderDut) -> None:
    """A write raises its register enable and sets the operation."""
    for address in range(ADDRESSES):
        wr_en, wr_op, _ = await _apply(dut, address, 1, 0)
        want = 1 << WRITE_BIT[address] if address in WRITE_BIT else 0
        check(
            wr_en == want,
            f"write {address}: wr_en={wr_en:08b}, expected {want:08b}",
        )
        check(
            wr_op == WR_OP.get(address, 0),
            f"write {address}: wr_op={wr_op:02b}",
        )


@cocotb.test()
async def test_no_write_no_enable(dut: GpioDecoderDut) -> None:
    """Without a write or a read, no enable is raised."""
    for address in range(ADDRESSES):
        wr_en, _, _ = await _apply(dut, address, 0, 0)
        check(wr_en == 0, f"idle {address}: wr_en={wr_en:08b}")


@cocotb.test()
async def test_only_reading_the_status_clears_it(
    dut: GpioDecoderDut,
) -> None:
    """Only a read of the IRQ status raises its clear enable."""
    for address in range(ADDRESSES):
        wr_en, _, _ = await _apply(dut, address, 0, 1)
        want = 1 << IRQ_CLEAR_BIT if address == IRQ_STAT else 0
        check(
            wr_en == want,
            f"read {address}: wr_en={wr_en:08b}, expected {want:08b}",
        )


@cocotb.test()
async def test_read_select(dut: GpioDecoderDut) -> None:
    """Each address selects its own read source."""
    for address in range(ADDRESSES):
        _, _, rd_sel = await _apply(dut, address, 0, 1)
        want = RD_SEL.get(address, RD_SEL_UNMAPPED)
        check(rd_sel == want, f"address {address}: rd_sel={rd_sel:03b}")


@cocotb.test()
async def test_only_the_level_register_selects_its_read_source(
    dut: GpioDecoderDut,
) -> None:
    """o_rd_level is high at the level-mode address and nowhere else."""
    for address in range(ADDRESSES):
        await _apply(dut, address, 0, 1)
        want = 1 if address == LEVEL_MASK else 0
        check(
            int(dut.o_rd_level.value) == want,
            f"address {address}: o_rd_level={int(dut.o_rd_level.value)}",
        )

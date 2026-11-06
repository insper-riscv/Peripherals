"""GPIO_CELL (through gpio_cell_tb): one pin, its registers, IRQ."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioCellDut

SYNC_CYCLES = 4
# write-enable bits, in the order of the decoder bit map
DIR, LOAD, BIT_OUT, IRQ_MASK, RISE, FALL, IRQ_CLR, LEVEL = (
    1 << n for n in range(8)
)
# read bits of o_data_out
R_DIR, R_OUT, R_PIN, R_MASK, R_RISE, R_FALL, R_STAT, R_LEVEL = range(8)
OP_LOAD, OP_SET, OP_CLEAR, OP_TOGGLE = 0b00, 0b01, 0b10, 0b11


async def _setup(dut: GpioCellDut) -> None:
    """Start the clock, hold the pin low and reset the cell.

    Parameters
    ----------
    dut : GpioCellDut
        The design under test.
    """
    dut.i_pin_drive.value = 0
    dut.i_pin_drive_en.value = 1
    dut.i_data_in.value = 0
    dut.i_wr_signals.value = 0
    dut.i_wr_op.value = OP_LOAD
    await bus.hold_reset(dut)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def _write(
    dut: GpioCellDut, enables: int, data: int, op: int = OP_LOAD
) -> None:
    """Pulse write enables for one cycle.

    Parameters
    ----------
    dut : GpioCellDut
        The design under test.
    enables : int
        Write enables to raise.
    data : int
        The data bit from the processor.
    op : int
        The output operation.
    """
    dut.i_wr_signals.value = enables
    dut.i_data_in.value = data
    dut.i_wr_op.value = op
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_wr_signals.value = 0
    dut.i_data_in.value = 0


def _bit(dut: GpioCellDut, index: int) -> int:
    """Return one bit of the read-back vector.

    Parameters
    ----------
    dut : GpioCellDut
        The design under test.
    index : int
        Bit position.

    Returns
    -------
    int
        The bit.
    """
    text = str(dut.o_data_out.value)
    return int(text[len(text) - 1 - index])


@cocotb.test()
async def test_reset_state(dut: GpioCellDut) -> None:
    """Every register reads zero and the pin follows the outside."""
    await _setup(dut)
    check(int(dut.o_data_out.value) == 0, "registers after reset")
    check(str(dut.o_pin.value) == "0", "pin held low by the outside")
    dut.i_pin_drive_en.value = 0
    await Timer(1, unit="ns")
    check(str(dut.o_pin.value) == "Z", "the cell does not drive the pin")


@cocotb.test()
async def test_direction_gates_the_output(dut: GpioCellDut) -> None:
    """The output register reaches the pin only as an output."""
    await _setup(dut)
    dut.i_pin_drive_en.value = 0
    await _write(dut, LOAD, 1)
    check(_bit(dut, R_OUT) == 1, "output register loaded")
    check(str(dut.o_pin.value) == "Z", "input direction keeps Z")
    await _write(dut, DIR, 1)
    check(_bit(dut, R_DIR) == 1, "direction register")
    check(str(dut.o_pin.value) == "1", "output direction drives 1")
    await _write(dut, LOAD, 0)
    check(str(dut.o_pin.value) == "0", "output direction drives 0")
    await _write(dut, DIR, 0)
    check(str(dut.o_pin.value) == "Z", "back to input releases the pin")


@cocotb.test()
async def test_bit_operations_act_only_on_a_selected_bit(
    dut: GpioCellDut,
) -> None:
    """Set, clear and toggle need the data bit at one; load does not."""
    await _setup(dut)
    await _write(dut, BIT_OUT, 0, OP_SET)
    check(_bit(dut, R_OUT) == 0, "set without the data bit")
    await _write(dut, BIT_OUT, 1, OP_SET)
    check(_bit(dut, R_OUT) == 1, "set")
    await _write(dut, BIT_OUT, 0, OP_CLEAR)
    check(_bit(dut, R_OUT) == 1, "clear without the data bit")
    await _write(dut, BIT_OUT, 1, OP_CLEAR)
    check(_bit(dut, R_OUT) == 0, "clear")
    await _write(dut, BIT_OUT, 1, OP_TOGGLE)
    check(_bit(dut, R_OUT) == 1, "toggle to one")
    await _write(dut, BIT_OUT, 1, OP_TOGGLE)
    check(_bit(dut, R_OUT) == 0, "toggle to zero")
    await _write(dut, BIT_OUT, 0, OP_TOGGLE)
    check(_bit(dut, R_OUT) == 0, "toggle without the data bit")


@cocotb.test()
async def test_pin_is_read_after_the_synchronizer(dut: GpioCellDut) -> None:
    """An external level is read back a few cycles later."""
    await _setup(dut)
    dut.i_pin_drive.value = 1
    dut.i_pin_drive_en.value = 1
    check(_bit(dut, R_PIN) == 0, "not yet visible")
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_PIN) == 1, "high level read")
    dut.i_pin_drive.value = 0
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_PIN) == 0, "low level read")


@cocotb.test()
async def test_mask_registers_hold_what_was_written(dut: GpioCellDut) -> None:
    """The three interrupt masks are independent one-bit registers."""
    await _setup(dut)
    for enable, bit in ((IRQ_MASK, R_MASK), (RISE, R_RISE), (FALL, R_FALL)):
        await _write(dut, enable, 1)
        value = int(dut.o_data_out.value)
        check(value == 1 << bit, f"mask {bit}: {value:07b}")
        await _write(dut, enable, 0)
        check(int(dut.o_data_out.value) == 0, f"mask {bit} cleared")


@cocotb.test()
async def test_rising_edge_sets_the_status(dut: GpioCellDut) -> None:
    """A rising edge with both masks on sets a sticky status."""
    await _setup(dut)
    await _write(dut, IRQ_MASK, 1)
    await _write(dut, RISE, 1)
    dut.i_pin_drive.value = 1
    dut.i_pin_drive_en.value = 1
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 1, "status after a rising edge")
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 1, "status is sticky")
    await _write(dut, IRQ_CLR, 0)
    check(_bit(dut, R_STAT) == 0, "status cleared by the clear strobe")


@cocotb.test()
async def test_falling_edge_sets_the_status(dut: GpioCellDut) -> None:
    """A falling edge needs the fall mask, not the rise mask."""
    await _setup(dut)
    dut.i_pin_drive.value = 1
    dut.i_pin_drive_en.value = 1
    await bus.cycles(dut, SYNC_CYCLES)
    await _write(dut, IRQ_MASK, 1)
    await _write(dut, RISE, 1)
    dut.i_pin_drive.value = 0
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 0, "rise mask ignores a falling edge")
    await _write(dut, FALL, 1)
    dut.i_pin_drive.value = 1
    await bus.cycles(dut, SYNC_CYCLES)
    await _write(dut, IRQ_CLR, 0)
    dut.i_pin_drive.value = 0
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 1, "falling edge with the fall mask")


@cocotb.test()
async def test_status_needs_the_global_mask(dut: GpioCellDut) -> None:
    """Edge masks alone do not raise the status."""
    await _setup(dut)
    await _write(dut, RISE | FALL, 1)
    dut.i_pin_drive.value = 1
    dut.i_pin_drive_en.value = 1
    await bus.cycles(dut, SYNC_CYCLES)
    dut.i_pin_drive.value = 0
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 0, "no status with the global mask off")


@cocotb.test()
async def test_level_mode_follows_the_pin_level(dut: GpioCellDut) -> None:
    """In level mode the rise mask means high level, the fall mask low."""
    await _setup(dut)
    await _write(dut, IRQ_MASK, 1)
    await _write(dut, LEVEL, 1)
    check(_bit(dut, R_LEVEL) == 1, "level mode reads back")
    await _write(dut, RISE, 1)
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 0, "pin low, high-level not met")
    dut.i_pin_drive.value = 1
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 1, "high level raises the status")
    await _write(dut, IRQ_CLR, 0)
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 1, "the level still holds: it rises again")
    dut.i_pin_drive.value = 0
    await bus.cycles(dut, SYNC_CYCLES)
    await _write(dut, IRQ_CLR, 0)
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 0, "level gone, the clear holds")


@cocotb.test()
async def test_level_mode_low_level_and_global_mask(dut: GpioCellDut) -> None:
    """The fall mask asks for a low level, and the global mask still gates."""
    await _setup(dut)
    await _write(dut, LEVEL, 1)
    await _write(dut, FALL, 1)
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 0, "global mask off")
    await _write(dut, IRQ_MASK, 1)
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 1, "pin low with the global mask on")
    dut.i_pin_drive.value = 1
    await bus.cycles(dut, SYNC_CYCLES)
    await _write(dut, IRQ_CLR, 0)
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 0, "pin high, no low level")
    await _write(dut, LEVEL, 0)
    await _write(dut, RISE, 1)
    dut.i_pin_drive.value = 0
    await bus.cycles(dut, SYNC_CYCLES)
    check(_bit(dut, R_STAT) == 1, "edge mode: the falling edge still counts")

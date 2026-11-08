"""GPIO (8 bits, through gpio_tb): direction, output, pins, IRQ."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioDut

DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL = 0, 1, 2, 3, 4
IRQ_MASK, RISE_MASK, FALL_MASK, IRQ_STAT, PINS, LEVEL_MASK = 5, 6, 7, 8, 9, 10
UNMAPPED = (11, 12, 13, 14, 15)
ALL_PINS = 0xFF
SYNC_CYCLES = 3
EDGE_CYCLES = 4
AFTER_SET = 0xAF
AFTER_CLEAR = 0x2E
AFTER_TOGGLE = 0xD1
PINS_FIRST = 0x3C
PINS_SECOND = 0xC3
RISING_PIN = 0b100
FALLING_PIN = 0b010
UNMASKED_PIN = 0b010
LEVEL_PINS = 0b0000_0110
HIGH_LEVEL_PIN = 0b0000_0100


async def setup(dut: GpioDut) -> None:
    """Release the pins and reset the design.

    Parameters
    ----------
    dut : GpioDut
        The design under test.
    """
    dut.i_pin_drive.value = 0
    dut.i_pin_drive_en.value = 0
    await bus.reset(dut)


@cocotb.test()
async def test_reset_state(dut: GpioDut) -> None:
    """Every register is zero after the reset."""
    await setup(dut)
    registers = (
        DIR,
        OUT_LOAD,
        IRQ_MASK,
        RISE_MASK,
        FALL_MASK,
        IRQ_STAT,
        LEVEL_MASK,
    )
    for address in registers:
        value = await bus.read(dut, address)
        check(value == 0, f"register {address} after reset")
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_registers_read_back_what_was_written(dut: GpioDut) -> None:
    """Each register answers at its own address."""
    await setup(dut)
    values = {
        DIR: 0xF0,
        OUT_LOAD: 0xA5,
        IRQ_MASK: 0x0F,
        RISE_MASK: 0x33,
        FALL_MASK: 0x55,
    }
    for address, value in values.items():
        await bus.write(dut, address, value)
    for address, value in values.items():
        read_back = await bus.read(dut, address)
        check(read_back == value, f"register {address}")


@cocotb.test()
async def test_pins_follow_the_output_where_the_direction_says_output(
    dut: GpioDut,
) -> None:
    """Output pins are driven and input pins are released."""
    await setup(dut)
    await bus.write(dut, OUT_LOAD, 0b10100101)
    await bus.write(dut, DIR, 0b00001111)
    pins = str(dut.o_pins.value)
    check(pins == "ZZZZ0101", f"low nibble driven, high released: {pins}")
    await bus.write(dut, DIR, ALL_PINS)
    check(str(dut.o_pins.value) == "10100101")
    await bus.write(dut, DIR, 0x00)
    check(str(dut.o_pins.value) == "Z" * 8)


@cocotb.test()
async def test_set_clear_toggle_touch_only_the_bits_written_as_one(
    dut: GpioDut,
) -> None:
    """Set, clear and toggle act only on the bits written as one."""
    await setup(dut)
    await bus.write(dut, OUT_LOAD, 0xA5)
    await bus.write(dut, OUT_SET, 0x0F)
    check(await bus.read(dut, OUT_LOAD) == AFTER_SET)
    await bus.write(dut, OUT_CLR, 0x81)
    check(await bus.read(dut, OUT_LOAD) == AFTER_CLEAR)
    await bus.write(dut, OUT_TGL, ALL_PINS)
    check(await bus.read(dut, OUT_LOAD) == AFTER_TOGGLE)
    await bus.write(dut, OUT_TGL, 0x00)
    check(await bus.read(dut, OUT_LOAD) == AFTER_TOGGLE)


@cocotb.test()
async def test_pins_read_is_the_synchronized_input(dut: GpioDut) -> None:
    """The pins register returns the synchronized input."""
    await setup(dut)
    dut.i_pin_drive.value = PINS_FIRST
    dut.i_pin_drive_en.value = ALL_PINS
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, PINS) == PINS_FIRST)
    dut.i_pin_drive.value = PINS_SECOND
    await bus.cycles(dut, SYNC_CYCLES)
    check(await bus.read(dut, PINS) == PINS_SECOND)


async def _edge(
    dut: GpioDut, before: int, after: int, enable: dict[int, int]
) -> None:
    """Configure the interrupt registers and move the pins once.

    Parameters
    ----------
    dut : GpioDut
        The design under test.
    before : int
        Pin levels before the edge.
    after : int
        Pin levels after the edge.
    enable : dict[int, int]
        Registers to write, by address, before the pins move.
    """
    dut.i_pin_drive_en.value = ALL_PINS
    dut.i_pin_drive.value = before
    await bus.cycles(dut, EDGE_CYCLES)
    for address, value in enable.items():
        await bus.write(dut, address, value)
    dut.i_pin_drive.value = after
    await bus.cycles(dut, EDGE_CYCLES)


@cocotb.test()
async def test_rising_edge_interrupt_is_cleared_by_reading_the_status(
    dut: GpioDut,
) -> None:
    """A rising edge is pending until the status is read."""
    await setup(dut)
    await _edge(dut, 0b000, 0b100, {IRQ_MASK: ALL_PINS, RISE_MASK: ALL_PINS})
    check(int(dut.o_irq.value) == 1)
    pending = await bus.read(dut, IRQ_STAT)
    check(pending == RISING_PIN, "the read returns the pending bit")
    check(int(dut.o_irq.value) == 0, "and clears it")
    check(await bus.read(dut, IRQ_STAT) == 0)


@cocotb.test()
async def test_falling_edge_interrupt(dut: GpioDut) -> None:
    """A falling edge raises the interrupt when it is enabled."""
    await setup(dut)
    await _edge(dut, 0b010, 0b000, {IRQ_MASK: ALL_PINS, FALL_MASK: ALL_PINS})
    check(int(dut.o_irq.value) == 1)
    check(await bus.read(dut, IRQ_STAT) == FALLING_PIN)


@cocotb.test()
async def test_an_edge_that_is_not_enabled_raises_nothing(
    dut: GpioDut,
) -> None:
    """A rising edge with only the falling edge enabled is ignored."""
    await setup(dut)
    await _edge(dut, 0b000, 0b100, {IRQ_MASK: ALL_PINS, FALL_MASK: ALL_PINS})
    check(int(dut.o_irq.value) == 0)
    check(await bus.read(dut, IRQ_STAT) == 0)


@cocotb.test()
async def test_masked_pin_raises_nothing(dut: GpioDut) -> None:
    """Only the unmasked pin reports an edge."""
    await setup(dut)
    await _edge(dut, 0b000, 0b110, {IRQ_MASK: 0b010, RISE_MASK: ALL_PINS})
    pending = await bus.read(dut, IRQ_STAT)
    check(pending == UNMASKED_PIN, "only the unmasked pin")


@cocotb.test()
async def test_level_mode_is_per_pin_and_o_irq_is_a_level(
    dut: GpioDut,
) -> None:
    """A pin in level mode keeps the interrupt up while it holds."""
    await setup(dut)
    for address in UNMAPPED:
        check(await bus.read(dut, address) == 0, f"address {address}")
    dut.i_pin_drive_en.value = ALL_PINS
    dut.i_pin_drive.value = 0b0000_0000
    await bus.write(dut, IRQ_MASK, ALL_PINS)
    await bus.write(dut, RISE_MASK, 0b0000_0100)
    await bus.write(dut, FALL_MASK, 0b0000_0010)
    await bus.write(dut, LEVEL_MASK, LEVEL_PINS)
    check(await bus.read(dut, LEVEL_MASK) == LEVEL_PINS)
    await bus.cycles(dut, EDGE_CYCLES)
    check(int(dut.o_irq.value) == 1, "pin 1 is low and wants the low level")
    dut.i_pin_drive.value = 0b0000_0010
    await bus.cycles(dut, EDGE_CYCLES)
    await bus.read(dut, IRQ_STAT)
    await bus.cycles(dut, EDGE_CYCLES)
    check(int(dut.o_irq.value) == 0, "no pin meets its level")
    dut.i_pin_drive.value = 0b0000_0110
    await bus.cycles(dut, EDGE_CYCLES)
    pending = await bus.read(dut, IRQ_STAT)
    check(pending == HIGH_LEVEL_PIN, f"only pin 2 (high level): {pending:#x}")
    await bus.cycles(dut, EDGE_CYCLES)
    check(int(dut.o_irq.value) == 1, "the high level still holds")
    await bus.write(dut, RISE_MASK, 0)
    await bus.read(dut, IRQ_STAT)
    await bus.cycles(dut, EDGE_CYCLES)
    check(int(dut.o_irq.value) == 0, "mask off, the line drops")

"""GPIO (8 bits, through gpio_tb): direction, output, pins, interrupts."""

import cocotb

from tests.python.utils import bus

DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL = 0, 1, 2, 3, 4
IRQ_MASK, RISE_MASK, FALL_MASK, IRQ_STAT, PINS = 5, 6, 7, 8, 9


async def setup(dut):
    dut.pin_drive.value = 0
    dut.pin_drive_en.value = 0
    await bus.reset(dut)


@cocotb.test()
async def test_reset_state(dut):
    await setup(dut)
    for address in (DIR, OUT_LOAD, IRQ_MASK, RISE_MASK, FALL_MASK, IRQ_STAT):
        assert await bus.read(dut, address) == 0, f"register {address} after reset"
    assert int(dut.irq.value) == 0


@cocotb.test()
async def test_registers_read_back_what_was_written(dut):
    """Each register answers at its own address (direction, output, three masks)."""
    await setup(dut)
    values = {DIR: 0xF0, OUT_LOAD: 0xA5, IRQ_MASK: 0x0F, RISE_MASK: 0x33, FALL_MASK: 0x55}
    for address, value in values.items():
        await bus.write(dut, address, value)
    for address, value in values.items():
        assert await bus.read(dut, address) == value, f"register {address}"


@cocotb.test()
async def test_pins_follow_the_output_where_the_direction_says_output(dut):
    await setup(dut)
    await bus.write(dut, OUT_LOAD, 0b10100101)
    await bus.write(dut, DIR, 0b00001111)
    pins = str(dut.pins.value)
    assert pins == "ZZZZ0101", f"low nibble driven, high nibble released: {pins}"
    await bus.write(dut, DIR, 0xFF)
    assert str(dut.pins.value) == "10100101"
    await bus.write(dut, DIR, 0x00)
    assert str(dut.pins.value) == "Z" * 8


@cocotb.test()
async def test_set_clear_toggle_touch_only_the_bits_written_as_one(dut):
    await setup(dut)
    await bus.write(dut, OUT_LOAD, 0xA5)
    await bus.write(dut, OUT_SET, 0x0F)
    assert await bus.read(dut, OUT_LOAD) == 0xAF
    await bus.write(dut, OUT_CLR, 0x81)
    assert await bus.read(dut, OUT_LOAD) == 0x2E
    await bus.write(dut, OUT_TGL, 0xFF)
    assert await bus.read(dut, OUT_LOAD) == 0xD1
    await bus.write(dut, OUT_TGL, 0x00)
    assert await bus.read(dut, OUT_LOAD) == 0xD1


@cocotb.test()
async def test_pins_read_is_the_synchronized_input(dut):
    await setup(dut)
    dut.pin_drive.value = 0x3C
    dut.pin_drive_en.value = 0xFF
    await bus.cycles(dut, 3)
    assert await bus.read(dut, PINS) == 0x3C
    dut.pin_drive.value = 0xC3
    await bus.cycles(dut, 3)
    assert await bus.read(dut, PINS) == 0xC3


async def _edge(dut, before, after, enable):
    dut.pin_drive_en.value = 0xFF
    dut.pin_drive.value = before
    await bus.cycles(dut, 4)
    for address, value in enable.items():
        await bus.write(dut, address, value)
    dut.pin_drive.value = after
    await bus.cycles(dut, 4)


@cocotb.test()
async def test_rising_edge_interrupt_is_read_and_cleared_by_reading_the_status(dut):
    await setup(dut)
    await _edge(dut, 0b000, 0b100, {IRQ_MASK: 0xFF, RISE_MASK: 0xFF})
    assert int(dut.irq.value) == 1
    assert await bus.read(dut, IRQ_STAT) == 0b100, "the read returns the pending bit"
    assert int(dut.irq.value) == 0, "and clears it"
    assert await bus.read(dut, IRQ_STAT) == 0


@cocotb.test()
async def test_falling_edge_interrupt(dut):
    await setup(dut)
    await _edge(dut, 0b010, 0b000, {IRQ_MASK: 0xFF, FALL_MASK: 0xFF})
    assert int(dut.irq.value) == 1
    assert await bus.read(dut, IRQ_STAT) == 0b010


@cocotb.test()
async def test_an_edge_that_is_not_enabled_raises_nothing(dut):
    await setup(dut)
    await _edge(dut, 0b000, 0b100, {IRQ_MASK: 0xFF, FALL_MASK: 0xFF})  # rising, only falling enabled
    assert int(dut.irq.value) == 0
    assert await bus.read(dut, IRQ_STAT) == 0


@cocotb.test()
async def test_masked_pin_raises_nothing(dut):
    await setup(dut)
    await _edge(dut, 0b000, 0b110, {IRQ_MASK: 0b010, RISE_MASK: 0xFF})
    assert await bus.read(dut, IRQ_STAT) == 0b010, "only the unmasked pin"

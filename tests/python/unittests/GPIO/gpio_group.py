"""GPIO_GROUP (32 pins, default generics): the registers of one group.

The group does not touch the pads: it gives each pin the value to
drive and the tristate enable, and takes the value of each pin in.
"""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioGroupDut

DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL = 0, 1, 2, 3, 4
IRQ_MASK, RISE_MASK, IRQ_STAT, PINS = 5, 6, 8, 9
SYNC_CYCLES = 4
WORD = 0xFFFF_FFFF
PATTERN = 0xA5A5_A5A5
HIGH_HALF = 0xFFFF_0000
LOW_BYTE_AFTER = 0xF0


async def setup(dut: GpioGroupDut) -> None:
    """Hold the pins low and reset the group."""
    dut.i_pins.value = 0
    await bus.reset(dut)


@cocotb.test()
async def test_registers_drive_the_pins(dut: GpioGroupDut) -> None:
    """DIR is the tristate enable and OUT_LOAD is the driven value."""
    await setup(dut)
    check(int(dut.o_pins_en.value) == 0, "released after reset")
    await bus.write(dut, OUT_LOAD, PATTERN)
    await bus.write(dut, DIR, 0xFFFF_0000)
    check(int(dut.o_pins_en.value) == HIGH_HALF)
    check(int(dut.o_pins_drv.value) == PATTERN)
    await bus.write(dut, OUT_CLR, WORD)
    check(await bus.read(dut, OUT_LOAD) == 0)
    await bus.write(dut, OUT_SET, 0x0F)
    await bus.write(dut, OUT_TGL, 0xFF)
    check(await bus.read(dut, OUT_LOAD) == LOW_BYTE_AFTER)
    check(await bus.read(dut, DIR) == HIGH_HALF)


@cocotb.test()
async def test_pins_read_and_interrupt(dut: GpioGroupDut) -> None:
    """PINS is the synchronized input; a rise is pending until read."""
    await setup(dut)
    await bus.write(dut, IRQ_MASK, WORD)
    await bus.write(dut, RISE_MASK, WORD)
    dut.i_pins.value = 1 << 31
    await bus.cycles(dut, SYNC_CYCLES)
    check(int(dut.o_irq.value) == 1)
    check(await bus.read(dut, PINS) == 1 << 31)
    check(await bus.read(dut, IRQ_STAT) == 1 << 31)
    check(int(dut.o_irq.value) == 0)

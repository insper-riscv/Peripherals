"""GPIO with active-low pins (gpio_tb with active_low true).

The program sees and writes every pin active high: the pin level is the
opposite of what the registers show, in the read of the pins, in the
output and in the interrupt edges.
"""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioDut

DIR, OUT_LOAD = 0, 1
IRQ_MASK, RISE_MASK, IRQ_STAT, PINS = 5, 6, 8, 9
ALL_PINS = 0xFF
SYNC_CYCLES = 3
EDGE_CYCLES = 4
PHYSICAL = 0x3C
LOGICAL = 0xC3
RISING_PIN = 0b100
OUT_PATTERN = 0b10100101


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
async def test_pins_read_is_the_inverted_input(dut: GpioDut) -> None:
    """A pin held low reads as one."""
    await setup(dut)
    dut.i_pin_drive.value = PHYSICAL
    dut.i_pin_drive_en.value = ALL_PINS
    await bus.cycles(dut, SYNC_CYCLES)
    value = await bus.read(dut, PINS)
    check(value == LOGICAL, f"pins register {value:#x}")


@cocotb.test()
async def test_output_drives_the_inverted_level(dut: GpioDut) -> None:
    """A one written to the output puts the pin low."""
    await setup(dut)
    await bus.write(dut, OUT_LOAD, 0b10100101)
    await bus.write(dut, DIR, ALL_PINS)
    pins = str(dut.o_pins.value)
    check(pins == "01011010", f"pins {pins}")
    check(await bus.read(dut, OUT_LOAD) == OUT_PATTERN, "the register keeps")
    await bus.write(dut, DIR, 0x00)
    check(str(dut.o_pins.value) == "Z" * 8, "released as input")


@cocotb.test()
async def test_falling_pin_is_a_rising_edge_for_the_program(
    dut: GpioDut,
) -> None:
    """The pin that goes low raises the rising edge interrupt."""
    await setup(dut)
    dut.i_pin_drive_en.value = ALL_PINS
    dut.i_pin_drive.value = 0b111
    await bus.cycles(dut, EDGE_CYCLES)
    await bus.write(dut, IRQ_MASK, ALL_PINS)
    await bus.write(dut, RISE_MASK, ALL_PINS)
    dut.i_pin_drive.value = 0b011
    await bus.cycles(dut, EDGE_CYCLES)
    check(int(dut.o_irq.value) == 1)
    pending = await bus.read(dut, IRQ_STAT)
    check(pending == RISING_PIN, f"pending {pending:#x}")

"""GPIO_CELL with a fixed direction (gpio_cell_tb with dir_mode 1 or 2).

The test runs for both modes: the mode is read from the DIR bit after
a write of one and a write of zero.
"""

import cocotb

from tests.python.unittests.GPIO.gpio_cell import (
    _bit,  # pyright: ignore[reportPrivateUsage]
    _setup,  # pyright: ignore[reportPrivateUsage]
    _write,  # pyright: ignore[reportPrivateUsage]
)
from tests.python.utils.check import check
from tests.python.utils.dut import GpioCellDut

DIR, LOAD = 1, 2
R_DIR = 0


@cocotb.test()
async def test_fixed_direction_ignores_the_write(dut: GpioCellDut) -> None:
    """DIR reads the fixed value after a write of one and of zero."""
    await _setup(dut)
    dut.i_pin_drive_en.value = 0
    fixed = _bit(dut, R_DIR)
    await _write(dut, DIR, 1)
    check(_bit(dut, R_DIR) == fixed, "a write of one does not change DIR")
    await _write(dut, DIR, 0)
    check(_bit(dut, R_DIR) == fixed, "a write of zero does not change DIR")
    await _write(dut, LOAD, 1)
    pin = str(dut.o_pin.value)
    check(
        pin == ("1" if fixed else "Z"),
        f"pin {pin} with fixed direction {fixed}",
    )

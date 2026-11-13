"""Reset value of the divider for other clock frequencies."""

import cocotb

from tests.python.unittests.I2C.registers import DIVIDER
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import I2cDut

MIN_DIVIDER = 2
STEPS_PER_BIT = 5


@cocotb.test()
async def test_reset_divider_follows_generics(dut: I2cDut) -> None:
    """The divider starts at f_clk / (5 * f_scl) - 1, never below 2."""
    clk_freq = int(getattr(dut, "clk_freq").value)  # noqa: B009
    scl_freq = int(getattr(dut, "scl_freq").value)  # noqa: B009
    await bus.reset(dut)
    want = max(clk_freq // (STEPS_PER_BIT * scl_freq) - 1, MIN_DIVIDER)
    check(await bus.read(dut, DIVIDER) == want)

"""MAX 10 ADC peripheral with a core that answers after the ready.

The response comes one cycle after the ready, and the sequencer must
still take every sample.
"""

import cocotb

from tests.python.unittests.ADC.driver import read_channel, scan, start
from tests.python.unittests.ADC.registers import (
    DONE,
    SAMPLE_MASK,
    TEMPERATURE,
    VALID,
)
from tests.python.utils.check import check
from tests.python.utils.dut import Max10AdcDut

VALUES = {0: 0x0A1, 2: 0x7FF, 8: 0xFFF, TEMPERATURE: 0x321}
MASK = (1 << 0) | (1 << 2) | (1 << 8) | (1 << TEMPERATURE)


@cocotb.test()
async def test_late_response_scan(dut: Max10AdcDut) -> None:
    """Take the samples of a response that follows the ready."""
    log = await start(dut, VALUES)
    status = await scan(dut, MASK)
    check(bool(status & DONE))
    check(log.channels() == [0, 2, 8, TEMPERATURE], f"{log.channels()}")
    for channel, value in VALUES.items():
        word = await read_channel(dut, channel)
        check(word & SAMPLE_MASK == value and bool(word & VALID), f"{channel}")

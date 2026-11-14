"""MAX 10 ADC peripheral against a model of the ADC core.

Registers, scan order, per-channel flags, period, interrupt and rejected
starts.
"""

from itertools import pairwise

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.ADC.driver import (
    CommandLog,
    read_channel,
    scan,
    start,
    wait_done,
)
from tests.python.unittests.ADC.registers import (
    BUSY,
    CHANNEL_BASE,
    CHANNELS,
    CONTINUOUS,
    CTRL,
    DONE,
    ENABLE,
    IRQ_ENABLE,
    LATE,
    MASK,
    OVERRUN,
    PERIOD,
    SAMPLE_MASK,
    START,
    STATUS,
    TEMPERATURE,
    VALID,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import Max10AdcDut

RESET_PERIOD = 100_000
WIDE_PERIOD = 0x1234_5678
MASK_BITS = (1 << CHANNELS) - 1
SCAN_MASK = (1 << 0) | (1 << 3) | (1 << TEMPERATURE)
VALUES = {0: 0x123, 3: 0xFFF, TEMPERATURE: 0x800, 5: 0x456}
SHORT_PERIOD = 400
NEW_SAMPLE = 0x222
MIN_SCANS = 2
TIGHT_PERIOD = 4
SCANS = 3
POLLS_PER_SCAN = 200


@cocotb.test()
async def test_reset_state(dut: Max10AdcDut) -> None:
    """The registers have their reset values and the core is quiet."""
    await start(dut)
    check(await bus.read(dut, CTRL) == 0)
    check(await bus.read(dut, MASK) == 0)
    check(await bus.read(dut, PERIOD) == RESET_PERIOD)
    check(await bus.read(dut, STATUS) == 0)
    for channel in range(CHANNELS):
        check(await read_channel(dut, channel) == 0)
    check(int(dut.o_irq.value) == 0)
    check(int(dut.o_cmd_valid.value) == 0)


@cocotb.test()
async def test_registers_read_back(dut: Max10AdcDut) -> None:
    """Control, mask and period read back; the start bit reads zero."""
    await start(dut)
    await bus.write(dut, CTRL, IRQ_ENABLE | CONTINUOUS)
    check(await bus.read(dut, CTRL) == IRQ_ENABLE | CONTINUOUS)
    await bus.write(dut, CTRL, ENABLE | START)
    check(await bus.read(dut, CTRL) == ENABLE)
    await bus.write(dut, MASK, 0xFFFF_FFFF)
    check(await bus.read(dut, MASK) == MASK_BITS, "mask has 18 bits")
    await bus.write(dut, PERIOD, WIDE_PERIOD)
    check(await bus.read(dut, PERIOD) == WIDE_PERIOD)


@cocotb.test()
async def test_read_data_is_zero_without_read_strobe(
    dut: Max10AdcDut,
) -> None:
    """The data output is zero when the processor is not reading."""
    await start(dut)
    await bus.write(dut, MASK, SCAN_MASK)
    dut.i_address.value = MASK
    dut.i_read.value = 0
    await Timer(1, unit="ns")
    check(int(dut.o_data_out.value) == 0)


@cocotb.test()
async def test_scan_order_and_packets(dut: Max10AdcDut) -> None:
    """A scan converts the masked channels in order, one packet."""
    log = await start(dut, VALUES)
    status = await scan(dut, SCAN_MASK)
    check(not status & BUSY and bool(status & DONE))
    check(log.channels() == [0, 3, TEMPERATURE], f"{log.channels()}")
    check([c.sop for c in log.commands] == [True, False, False])
    check([c.eop for c in log.commands] == [False, False, True])


@cocotb.test()
async def test_results_and_flags(dut: Max10AdcDut) -> None:
    """Each scanned channel holds its sample and a valid flag."""
    await start(dut, VALUES)
    await scan(dut, SCAN_MASK)
    for channel in (0, 3, TEMPERATURE):
        word = await read_channel(dut, channel)
        check(word & SAMPLE_MASK == VALUES[channel], f"channel {channel}")
        check(bool(word & VALID), f"channel {channel} valid")
        check(not word & OVERRUN)
        again = await read_channel(dut, channel)
        check(again & SAMPLE_MASK == VALUES[channel], "value stays")
        check(not again & (VALID | OVERRUN), "the read clears the flags")
    other = await read_channel(dut, 5)
    check(other == 0, "an unscanned channel stays empty")


@cocotb.test()
async def test_overrun_when_unread(dut: Max10AdcDut) -> None:
    """A second scan over an unread result sets the overrun flag."""
    await start(dut, {1: 0x111})
    await scan(dut, 1 << 1)
    dut.i_analog.value = NEW_SAMPLE << 12
    await bus.write(dut, STATUS, DONE)
    await scan(dut, 1 << 1)
    word = await read_channel(dut, 1)
    check(word & SAMPLE_MASK == NEW_SAMPLE, "the new sample replaced the old")
    check(bool(word & VALID and word & OVERRUN))
    check(
        await read_channel(dut, 1) == NEW_SAMPLE, "flags cleared by the read"
    )


@cocotb.test()
async def test_read_between_scans_avoids_overrun(dut: Max10AdcDut) -> None:
    """Reading the result before the next scan leaves no overrun."""
    await start(dut, {1: 0x111})
    await scan(dut, 1 << 1)
    await read_channel(dut, 1)
    await bus.write(dut, STATUS, DONE)
    await scan(dut, 1 << 1)
    word = await read_channel(dut, 1)
    check(bool(word & VALID) and not word & OVERRUN)


@cocotb.test()
async def test_interrupt_at_end_of_scan(dut: Max10AdcDut) -> None:
    """The interrupt rises at the end of the scan when enabled."""
    await start(dut, VALUES)
    await bus.write(dut, MASK, SCAN_MASK)
    await bus.write(dut, CTRL, ENABLE | IRQ_ENABLE)
    await bus.write(dut, CTRL, ENABLE | IRQ_ENABLE | START)
    check(int(dut.o_irq.value) == 0, "not before the scan ends")
    await wait_done(dut)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, STATUS, DONE)
    check(int(dut.o_irq.value) == 0, "writing one clears it")
    check(await bus.read(dut, STATUS) == 0)


@cocotb.test()
async def test_interrupt_mask(dut: Max10AdcDut) -> None:
    """With the interrupt disabled the done flag does not raise it."""
    await start(dut, VALUES)
    await scan(dut, SCAN_MASK)
    check(int(dut.o_irq.value) == 0)
    await bus.write(dut, CTRL, ENABLE | IRQ_ENABLE)
    check(int(dut.o_irq.value) == 1, "enabling it with done set raises it")


@cocotb.test()
async def test_empty_mask_ends_at_once(dut: Max10AdcDut) -> None:
    """A scan with no channel ends without a command."""
    log = await start(dut, VALUES)
    status = await scan(dut, 0)
    check(bool(status & DONE) and not status & BUSY)
    check(not log.commands)


@cocotb.test()
async def test_disabled_ignores_start(dut: Max10AdcDut) -> None:
    """Without the enable bit a start request does nothing."""
    log = await start(dut, VALUES)
    await bus.write(dut, MASK, SCAN_MASK)
    await bus.write(dut, CTRL, START)
    for _ in range(POLLS_PER_SCAN):
        await bus.read(dut, STATUS)
    check(await bus.read(dut, STATUS) == 0)
    check(not log.commands)


@cocotb.test()
async def test_start_while_busy_is_late(dut: Max10AdcDut) -> None:
    """A start during a scan is ignored and sets the late flag."""
    log = await start(dut, VALUES)
    await bus.write(dut, MASK, SCAN_MASK)
    await bus.write(dut, CTRL, ENABLE)
    await bus.write(dut, CTRL, ENABLE | START)
    check(bool(await bus.read(dut, STATUS) & BUSY))
    await bus.write(dut, CTRL, ENABLE | START)
    status = await wait_done(dut)
    check(bool(status & LATE and status & DONE))
    check(len(log.commands) == len((0, 3, TEMPERATURE)), "no second scan")
    await bus.write(dut, STATUS, LATE)
    check(await bus.read(dut, STATUS) == DONE, "late cleared, done kept")


@cocotb.test()
async def test_continuous_period(dut: Max10AdcDut) -> None:
    """In continuous mode a scan starts every PERIOD cycles."""
    log = await start(dut, VALUES)
    await bus.write(dut, MASK, SCAN_MASK)
    await bus.write(dut, PERIOD, SHORT_PERIOD)
    await bus.write(dut, CTRL, ENABLE | CONTINUOUS)
    await _wait_scans(dut, log, SCANS)
    firsts = [c.cycle for c in log.commands if c.sop]
    gaps = [b - a for a, b in pairwise(firsts)]
    check(all(gap == SHORT_PERIOD for gap in gaps), f"gaps {gaps}")
    await bus.write(dut, CTRL, ENABLE)
    count = len(log.commands)
    await bus.write(dut, STATUS, DONE | LATE)
    await bus.write(dut, CTRL, 0)
    await bus.write(dut, CTRL, ENABLE)
    for _ in range(SHORT_PERIOD * 2):
        await bus.read(dut, STATUS)
    check(len(log.commands) - count <= len((0, 3, TEMPERATURE)))
    check(not await bus.read(dut, STATUS) & LATE)


async def _wait_scans(dut: Max10AdcDut, log: CommandLog, scans: int) -> None:
    """Wait until the log shows a number of finished scans.

    Parameters
    ----------
    dut : Max10AdcDut
        The design under test.
    log : CommandLog
        Commands the core accepted.
    scans : int
        Number of scans to wait for.

    Raises
    ------
    TimeoutError
        If the scans do not happen in time.
    """
    for _ in range(scans * SHORT_PERIOD * 2):
        await bus.read(dut, STATUS)
        if len([c for c in log.commands if c.eop]) >= scans:
            return
    raise TimeoutError("the continuous scans did not happen")


@cocotb.test()
async def test_continuous_late_when_period_is_short(
    dut: Max10AdcDut,
) -> None:
    """A period shorter than a scan makes scans back to back, late."""
    log = await start(dut, VALUES)
    await bus.write(dut, MASK, SCAN_MASK)
    await bus.write(dut, PERIOD, TIGHT_PERIOD)
    await bus.write(dut, CTRL, ENABLE | CONTINUOUS)
    for _ in range(POLLS_PER_SCAN):
        await bus.read(dut, STATUS)
    check(len([c for c in log.commands if c.eop]) >= MIN_SCANS, "scans repeat")
    check(bool(await bus.read(dut, STATUS) & LATE))
    firsts = [c.cycle for c in log.commands if c.sop]
    check(len({b - a for a, b in pairwise(firsts)}) == 1)


@cocotb.test()
async def test_channel_window(dut: Max10AdcDut) -> None:
    """Addresses outside the channel window read zero."""
    await start(dut, VALUES)
    await scan(dut, SCAN_MASK)
    after = CHANNEL_BASE + CHANNELS
    await bus.write(dut, CHANNEL_BASE, 0x1FFF)
    check(await bus.read(dut, after) == 0)
    check(await bus.read(dut, 4) == 0)
    check(await bus.read(dut, 31) == 0)
    word = await read_channel(dut, 0)
    check(word & SAMPLE_MASK == VALUES[0], "a write does not change it")

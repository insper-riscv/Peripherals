"""MAC transmitter: preamble, SFD, padding, FCS and interval."""

import cocotb

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH import driver
from tests.python.unittests.ETH import registers as reg
from tests.python.unittests.ETH.model import (
    GAP_NIBBLES,
    MIN_PAYLOAD,
    TxMonitor,
    fcs,
)
from tests.python.utils import bus
from tests.python.utils.rng import seeded

LONG_LENGTH = 301
SHORT_LENGTH = 20
MAX_LENGTH = 2048


def make_frame(length: int, seed: int) -> bytes:
    """Build a frame with a pseudo-random content.

    Parameters
    ----------
    length : int
        Frame length in bytes.
    seed : int
        Seed of the content.

    Returns
    -------
    bytes
        The frame.
    """
    return seeded(seed).randbytes(length)


@cocotb.test()
async def test_long_frame(dut: Dut) -> None:
    """A frame of 301 bytes goes out with the right FCS."""
    await driver.start(dut)
    await driver.configure(dut)
    monitor = TxMonitor(dut)
    frame = make_frame(LONG_LENGTH, 1)
    await driver.send_frame(dut, frame)
    await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
    check_equal(len(monitor.frames), 1)
    check_equal(monitor.decode(0), frame + fcs(frame))
    check_equal(await bus.read(dut, reg.CNT_TX), 1)
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_TX_DONE, 2)


@cocotb.test()
async def test_padding(dut: Dut) -> None:
    """A short frame is filled with zeros up to 60 bytes."""
    await driver.start(dut)
    await driver.configure(dut)
    monitor = TxMonitor(dut)
    frame = make_frame(SHORT_LENGTH, 2)
    await driver.send_frame(dut, frame)
    await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
    padded = frame + bytes(MIN_PAYLOAD - SHORT_LENGTH)
    check_equal(monitor.decode(0), padded + fcs(padded))


@cocotb.test()
async def test_back_to_back_gap(dut: Dut) -> None:
    """Two frames in a row leave at least 96 bit times between them."""
    await driver.start(dut)
    await driver.configure(dut)
    monitor = TxMonitor(dut)
    for seed in (3, 4):
        frame = make_frame(64 + seed, seed)
        await driver.send_frame(dut, frame)
        await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
        check_equal(
            monitor.decode(len(monitor.frames) - 1), frame + fcs(frame)
        )
    gap = monitor.starts[1] - monitor.ends[0]
    check_true(gap >= GAP_NIBBLES, f"gap of {gap} nibbles")
    check_equal(await bus.read(dut, reg.CNT_TX), 2)


@cocotb.test()
async def test_slow_clock(dut: Dut) -> None:
    """The same frame goes out at the 10 Mbit/s clock of 2.5 MHz."""
    await driver.start(dut, tx_ns=driver.MII_10_NS)
    await driver.configure(dut)
    monitor = TxMonitor(dut)
    frame = make_frame(70, 5)
    await driver.send_frame(dut, frame)
    await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
    check_equal(monitor.decode(0), frame + fcs(frame))


@cocotb.test()
async def test_bad_start(dut: Dut) -> None:
    """A start with length zero, or while busy, raises the error."""
    await driver.start(dut)
    await driver.configure(dut)
    monitor = TxMonitor(dut)
    await bus.write(dut, reg.TX_CMD, reg.TX_START)
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_ERROR, 4)
    await driver.settle(dut, 5)
    check_equal(len(monitor.frames), 0)
    frame = make_frame(100, 6)
    await driver.send_frame(dut, frame)
    await bus.write(dut, reg.IRQ_STATUS, reg.IRQ_ERROR)
    await bus.write(dut, reg.TX_CMD, reg.TX_START)
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_ERROR, 4)
    await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
    check_equal(len(monitor.frames), 1)


@cocotb.test()
async def test_largest_frame(dut: Dut) -> None:
    """A frame that fills the 2 KiB buffer goes out whole."""
    await driver.start(dut)
    await driver.configure(dut)
    monitor = TxMonitor(dut)
    frame = make_frame(MAX_LENGTH, 7)
    await driver.send_frame(dut, frame)
    await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
    check_equal(monitor.decode(0), frame + fcs(frame))

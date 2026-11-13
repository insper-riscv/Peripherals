"""MAC receiver: SFD, FCS check, filter, counters and the buffer."""

import cocotb

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH import driver
from tests.python.unittests.ETH import registers as reg
from tests.python.unittests.ETH.model import drive_rx, wire_nibbles
from tests.python.utils import bus
from tests.python.utils.rng import seeded

BROADCAST = bytes((0xFF,) * 6)
GROUP = bytes((0x01, 0x00, 0x5E, 0x00, 0x00, 0x01))
OTHER = bytes((0x02, 0x99, 0x88, 0x77, 0x66, 0x55))
SOURCE = bytes((0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE))
SETTLE_US = 3


def make_frame(dest: bytes, length: int, seed: int) -> bytes:
    """Build a frame for a destination address.

    Parameters
    ----------
    dest : bytes
        Destination address.
    length : int
        Frame length in bytes, from the destination on.
    seed : int
        Seed of the content.

    Returns
    -------
    bytes
        The frame without FCS.
    """
    body = seeded(seed).randbytes(length - len(dest) - len(SOURCE))
    return dest + SOURCE + body


async def counters(dut: Dut) -> tuple[int, int, int, int, int]:
    """Read the receive counters.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    tuple[int, int, int, int, int]
        Frames, CRC errors, PHY errors, dropped and filtered.
    """
    return (
        await bus.read(dut, reg.CNT_RX),
        await bus.read(dut, reg.CNT_CRC),
        await bus.read(dut, reg.CNT_PHY),
        await bus.read(dut, reg.CNT_DROP),
        await bus.read(dut, reg.CNT_FILTER),
    )


@cocotb.test()
async def test_unicast_sizes(dut: Dut) -> None:
    """Frames for this MAC arrive intact for several sizes."""
    await driver.start(dut)
    await driver.configure(dut)
    for index, length in enumerate((60, 61, 62, 63, 64, 100, 777, 1514)):
        frame = make_frame(driver.MAC_ADDRESS, length, index)
        await drive_rx(dut, wire_nibbles(frame))
        await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
        check_equal(await bus.read(dut, reg.RX_LEN), length)
        check_equal(await driver.read_frame(dut), frame)
    check_equal(await counters(dut), (8, 0, 0, 0, 0))


@cocotb.test()
async def test_irq(dut: Dut) -> None:
    """The interrupt rises with a received frame when it is enabled."""
    await driver.start(dut)
    await driver.configure(dut)
    await bus.write(dut, reg.IRQ_ENABLE, reg.IRQ_RX_FRAME)
    check_equal(int(dut.o_irq.value), 0)
    await drive_rx(dut, wire_nibbles(make_frame(driver.MAC_ADDRESS, 80, 9)))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, reg.IRQ_STATUS, reg.IRQ_RX_FRAME)
    check_equal(int(dut.o_irq.value), 0)


@cocotb.test()
async def test_filter(dut: Dut) -> None:
    """Other, broadcast and group destinations follow the bits."""
    await driver.start(dut)
    await driver.configure(dut)
    other = make_frame(OTHER, 70, 10)
    await drive_rx(dut, wire_nibbles(other))
    await driver.settle(dut, SETTLE_US)
    check_equal((await counters(dut))[4], 1)
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_RX_READY, 0)
    cast = make_frame(BROADCAST, 70, 11)
    await drive_rx(dut, wire_nibbles(cast))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    check_equal(await driver.read_frame(dut), cast)
    group = make_frame(GROUP, 70, 12)
    await drive_rx(dut, wire_nibbles(group))
    await driver.settle(dut, SETTLE_US)
    check_equal((await counters(dut))[4], 2)
    await driver.configure(dut, reg.CTRL_ENABLE | reg.CTRL_MULTICAST)
    await drive_rx(dut, wire_nibbles(group))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    check_equal(await driver.read_frame(dut), group)


@cocotb.test()
async def test_promiscuous(dut: Dut) -> None:
    """The promiscuous bit delivers frames for any destination."""
    await driver.start(dut)
    await driver.configure(dut, reg.CTRL_ENABLE | reg.CTRL_PROMISCUOUS)
    other = make_frame(OTHER, 90, 13)
    await drive_rx(dut, wire_nibbles(other))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    check_equal(await driver.read_frame(dut), other)


@cocotb.test()
async def test_broadcast_off(dut: Dut) -> None:
    """With the broadcast bit clear, broadcast frames are refused."""
    await driver.start(dut)
    await bus.write(dut, reg.CTRL, reg.CTRL_ENABLE)
    await bus.write(dut, reg.MAC_LO, 0x33221102)
    await bus.write(dut, reg.MAC_HI, 0x5544)
    await drive_rx(dut, wire_nibbles(make_frame(BROADCAST, 70, 14)))
    await driver.settle(dut, SETTLE_US)
    check_equal((await counters(dut))[4], 1)


@cocotb.test()
async def test_crc_error(dut: Dut) -> None:
    """A wrong FCS counts as a CRC error and is not delivered."""
    await driver.start(dut)
    await driver.configure(dut)
    frame = make_frame(driver.MAC_ADDRESS, 90, 15)
    await drive_rx(dut, wire_nibbles(frame, bad_fcs=True))
    await driver.settle(dut, SETTLE_US)
    check_equal(await counters(dut), (0, 1, 0, 0, 0))
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_RX_READY, 0)
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_ERROR, 4)


@cocotb.test()
async def test_accept_errors(dut: Dut) -> None:
    """With accept-errors, a frame with a bad FCS is delivered."""
    await driver.start(dut)
    await driver.configure(dut, reg.CTRL_ENABLE | reg.CTRL_ACCEPT_ERRORS)
    frame = make_frame(driver.MAC_ADDRESS, 90, 16)
    await drive_rx(dut, wire_nibbles(frame, bad_fcs=True))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    check_equal(await driver.read_frame(dut), frame)
    check_equal((await counters(dut))[1], 1)


@cocotb.test()
async def test_phy_error_and_runt(dut: Dut) -> None:
    """RX_ER, an odd nibble count and a runt are PHY errors."""
    await driver.start(dut)
    await driver.configure(dut)
    frame = make_frame(driver.MAC_ADDRESS, 90, 17)
    await drive_rx(dut, wire_nibbles(frame), error_at=40)
    await drive_rx(dut, wire_nibbles(frame)[:-1])
    runt = make_frame(driver.MAC_ADDRESS, 40, 18)
    await drive_rx(dut, wire_nibbles(runt))
    await driver.settle(dut, SETTLE_US)
    check_equal((await counters(dut))[2], 3)
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_RX_READY, 0)


@cocotb.test()
async def test_buffer_busy(dut: Dut) -> None:
    """A frame that arrives with the buffer full is dropped."""
    await driver.start(dut)
    await driver.configure(dut)
    first = make_frame(driver.MAC_ADDRESS, 80, 19)
    await drive_rx(dut, wire_nibbles(first))
    await drive_rx(dut, wire_nibbles(make_frame(driver.MAC_ADDRESS, 80, 20)))
    await driver.settle(dut, SETTLE_US)
    check_equal((await counters(dut))[3], 1)
    check_equal(await driver.read_frame(dut), first)
    third = make_frame(driver.MAC_ADDRESS, 81, 21)
    await drive_rx(dut, wire_nibbles(third))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    check_equal(await driver.read_frame(dut), third)


@cocotb.test()
async def test_slow_clock(dut: Dut) -> None:
    """Reception works at the 10 Mbit/s clock, and with MAC off."""
    await driver.start(dut, rx_ns=driver.MII_10_NS)
    await driver.configure(dut, 0)
    frame = make_frame(driver.MAC_ADDRESS, 70, 22)
    await drive_rx(dut, wire_nibbles(frame))
    await driver.settle(dut, SETTLE_US)
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_RX_READY, 0)
    await driver.configure(dut)
    await drive_rx(dut, wire_nibbles(frame))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    check_equal(await driver.read_frame(dut), frame)


@cocotb.test()
async def test_back_to_back_frames(dut: Dut) -> None:
    """Frames separated by the minimum gap are all received in order."""
    await driver.start(dut)
    await driver.configure(dut)
    for index in range(4):
        frame = make_frame(driver.MAC_ADDRESS, 64 + index, 30 + index)
        await drive_rx(dut, wire_nibbles(frame))
        await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
        check_equal(await driver.read_frame(dut), frame)

"""MAC with RGMII at 10, 100 and 1000 Mbit/s."""

import struct

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH import driver, rgmii_driver
from tests.python.unittests.ETH import registers as reg
from tests.python.unittests.ETH.frames_rx import make_frame
from tests.python.unittests.ETH.model import MIN_PAYLOAD, fcs
from tests.python.unittests.ETH.phy_mdio import MdioPhy
from tests.python.unittests.ETH.rgmii_phy import (
    GAP_BYTES,
    GAP_NIBBLES,
    RgmiiPhy,
    wire_bytes,
)
from tests.python.utils import bus
from tests.python.utils.rng import seeded

PHY_ADDRESS = 16
SPEEDS = (1000, 100, 10)
LENGTHS = {1000: (60, 61, 300, 1514), 100: (60, 77, 300), 10: (60, 90)}
POLL_WAIT_NS = 250_000
READ_ATTEMPTS = 5
HOST_MAC = bytes((0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE))
HOST_IP = bytes((192, 168, 1, 10))
BOARD_IP = bytes((192, 168, 1, 50))
ICMP_ECHO_REQUEST = 8
ICMP_ECHO_REPLY = 0
ETHERTYPE_IPV4 = bytes((0x08, 0x00))
IPV4_HEADER = 20
ICMP_HEADER = 8
CHECKSUM_FOLD = 0xFFFF
TTL = 64
PROTOCOL_ICMP = 1
ADDRESS_BYTES = 6
TYPE_END = 14
ICMP_START = TYPE_END + IPV4_HEADER
SRC_START = ADDRESS_BYTES
TYPE_START = 2 * ADDRESS_BYTES


def padded(frame: bytes) -> bytes:
    """Pad a frame with zeros up to the minimum size, as the MAC does.

    Parameters
    ----------
    frame : bytes
        Frame without FCS.

    Returns
    -------
    bytes
        The frame of at least 60 bytes.
    """
    return frame + bytes(max(0, MIN_PAYLOAD - len(frame)))


def internet_checksum(data: bytes) -> int:
    """Compute the checksum of RFC 1071.

    Parameters
    ----------
    data : bytes
        Bytes to sum; an odd count gets a zero appended.

    Returns
    -------
    int
        The one's complement of the sum of the 16-bit words.
    """
    if len(data) % 2:
        data += b"\x00"
    total = sum(struct.unpack(f">{len(data) // 2}H", data))
    while total >> 16:
        total = (total & CHECKSUM_FOLD) + (total >> 16)
    return ~total & CHECKSUM_FOLD


async def transmit_all(dut: Dut, phy: RgmiiPhy, speed: int) -> None:
    """Send frames of several lengths and compare them on the pins.

    Parameters
    ----------
    dut : Dut
        The design under test.
    phy : RgmiiPhy
        The PHY model.
    speed : int
        Link speed in Mbit/s.
    """
    for index, length in enumerate(LENGTHS[speed]):
        frame = seeded(length + speed).randbytes(length)
        await driver.send_frame(dut, frame)
        await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
        check_equal(len(phy.tx.frames), index + 1)
        want = padded(frame)
        check_equal(phy.decode(index), want + fcs(want))
    minimum = GAP_BYTES if speed == 1000 else GAP_NIBBLES  # noqa: PLR2004
    check_true(
        all(gap >= minimum for gap in phy.tx.gaps), f"gaps {phy.tx.gaps}"
    )
    check_equal(await bus.read(dut, reg.CNT_TX), len(LENGTHS[speed]))


async def receive_all(dut: Dut, phy: RgmiiPhy, speed: int) -> None:
    """Send frames from the PHY and read them back.

    Parameters
    ----------
    dut : Dut
        The design under test.
    phy : RgmiiPhy
        The PHY model.
    speed : int
        Link speed in Mbit/s.
    """
    for index, length in enumerate(LENGTHS[speed]):
        frame = make_frame(driver.MAC_ADDRESS, length, index + speed)
        phy.send(wire_bytes(frame))
        await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
        check_equal(await bus.read(dut, reg.RX_LEN), length)
        check_equal(await driver.read_frame(dut), frame)
        await bus.cycles(dut, 4)
    check_equal(await bus.read(dut, reg.CNT_RX), len(LENGTHS[speed]))


@cocotb.test()
async def test_reset_values(dut: Dut) -> None:
    """After reset SPEED is automatic and reports 1000 Mbit/s."""
    await rgmii_driver.start(dut)
    word = await bus.read(dut, reg.SPEED)
    check_equal(word & reg.SPEED_MODE_MASK, reg.SPEED_MODE_AUTO)
    check_equal(await rgmii_driver.active_speed_code(dut), 2)
    for mode in (reg.SPEED_MODE_10, reg.SPEED_MODE_100, reg.SPEED_MODE_1000):
        await bus.write(dut, reg.SPEED, mode)
        check_equal(await bus.read(dut, reg.SPEED) & reg.SPEED_MODE_MASK, mode)
        check_equal(await rgmii_driver.active_speed_code(dut), mode - 1)


async def speed_case(dut: Dut, speed: int, *, mac_delays_txc: bool) -> None:
    """Transmit and receive at one forced speed.

    Parameters
    ----------
    dut : Dut
        The design under test.
    speed : int
        Link speed in Mbit/s.
    mac_delays_txc : bool
        The MAC shifts the TXC clock by 90 degrees.
    """
    phy = await rgmii_driver.start(dut, speed, mac_delays_txc=mac_delays_txc)
    await driver.configure(dut)
    await rgmii_driver.force_speed(dut, speed)
    await transmit_all(dut, phy, speed)
    await receive_all(dut, phy, speed)


@cocotb.test()
async def test_speed_1000(dut: Dut) -> None:
    """Frames in both directions at 1000 Mbit/s."""
    await speed_case(dut, 1000, mac_delays_txc=True)


@cocotb.test()
async def test_speed_100(dut: Dut) -> None:
    """Frames in both directions at 100 Mbit/s."""
    await speed_case(dut, 100, mac_delays_txc=True)


@cocotb.test()
async def test_speed_10(dut: Dut) -> None:
    """Frames in both directions at 10 Mbit/s."""
    await speed_case(dut, 10, mac_delays_txc=True)


async def errors_case(dut: Dut, speed: int) -> None:
    """Receive a frame with a bad FCS and a frame with RX_ER.

    Parameters
    ----------
    dut : Dut
        The design under test.
    speed : int
        Link speed in Mbit/s.
    """
    phy = await rgmii_driver.start(dut, speed)
    await driver.configure(dut)
    await rgmii_driver.force_speed(dut, speed)
    frame = make_frame(driver.MAC_ADDRESS, 90, speed)
    phy.fall_noise = speed != 1000  # noqa: PLR2004
    phy.send(wire_bytes(frame, bad_fcs=True))
    phy.send(wire_bytes(frame), error_at=40)
    await phy.drain()
    await Timer(2000, unit="ns")
    check_equal(await bus.read(dut, reg.CNT_CRC), 1)
    check_equal(await bus.read(dut, reg.CNT_PHY), 1)
    check_equal(await bus.read(dut, reg.CNT_RX), 0)


@cocotb.test()
async def test_errors_1000(dut: Dut) -> None:
    """A bad FCS and RX_ER are counted at 1000 Mbit/s."""
    await errors_case(dut, 1000)


@cocotb.test()
async def test_errors_100(dut: Dut) -> None:
    """A bad FCS and RX_ER are counted at 100 Mbit/s."""
    await errors_case(dut, 100)


def phy_status(speed_code: int, *, link: bool, resolved: bool = True) -> int:
    """Build the value of the PHY status register.

    Parameters
    ----------
    speed_code : int
        0 for 10, 1 for 100 and 2 for 1000 Mbit/s.
    link : bool
        The link is up.
    resolved : bool
        Speed and duplex are resolved.

    Returns
    -------
    int
        The register value, with full duplex set.
    """
    value = (speed_code << reg.PHY_STATUS_SPEED_SHIFT) | reg.PHY_STATUS_DUPLEX
    if link:
        value |= reg.PHY_STATUS_LINK
    if resolved:
        value |= reg.PHY_STATUS_RESOLVED
    return value


@cocotb.test()
async def test_automatic_speed(dut: Dut) -> None:
    """The speed follows the PHY status register read by MDIO."""
    await rgmii_driver.start(dut)
    regs = {reg.PHY_STATUS_REG: phy_status(1, link=True), 2: 0x0141}
    mdio = MdioPhy(dut, PHY_ADDRESS, regs)
    await Timer(POLL_WAIT_NS, unit="ns")
    check_equal(await rgmii_driver.active_speed_code(dut), 1)
    word = await bus.read(dut, reg.SPEED)
    check_equal(
        word & (reg.SPEED_LINK | reg.SPEED_FULL_DUPLEX | reg.SPEED_RESOLVED),
        reg.SPEED_LINK | reg.SPEED_FULL_DUPLEX | reg.SPEED_RESOLVED,
    )
    check_true(
        all(
            frame == (2, PHY_ADDRESS, reg.PHY_STATUS_REG)
            for frame in mdio.frames
        ),
        f"frames {mdio.frames}",
    )
    regs[reg.PHY_STATUS_REG] = phy_status(0, link=True)
    await Timer(POLL_WAIT_NS, unit="ns")
    check_equal(await rgmii_driver.active_speed_code(dut), 0)
    regs[reg.PHY_STATUS_REG] = phy_status(2, link=False)
    await Timer(POLL_WAIT_NS, unit="ns")
    check_equal(await rgmii_driver.active_speed_code(dut), 0)
    check_equal(await bus.read(dut, reg.SPEED) & reg.SPEED_LINK, 0)
    regs[reg.PHY_STATUS_REG] = phy_status(2, link=True)
    await Timer(POLL_WAIT_NS, unit="ns")
    check_equal(await rgmii_driver.active_speed_code(dut), 2)
    await bus.write(dut, reg.SPEED, reg.SPEED_MODE_100)
    check_equal(await rgmii_driver.active_speed_code(dut), 1)


@cocotb.test()
async def test_mdio_next_to_the_poll(dut: Dut) -> None:
    """A read of the program is correct among the reads of the speed."""
    await rgmii_driver.start(dut)
    regs = {reg.PHY_STATUS_REG: phy_status(2, link=True), 2: 0x0141, 3: 0x0C2D}
    MdioPhy(dut, PHY_ADDRESS, regs)
    await Timer(POLL_WAIT_NS, unit="ns")
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_MDIO_DONE, 0)
    for register in (2, 3, 2, 3):
        check_equal(await read_phy(dut, register), regs[register])
        check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_MDIO_NOACK, 0)
        await Timer(30_000, unit="ns")
    check_equal(await rgmii_driver.active_speed_code(dut), 2)


async def read_phy(dut: Dut, register: int) -> int:
    """Read a PHY register through MDIO with retries.

    A command written while the speed poll holds the master is ignored,
    like one written while the master is busy, so the program checks the
    done interrupt and repeats the command.

    Parameters
    ----------
    dut : Dut
        The design under test.
    register : int
        Register of the PHY.

    Returns
    -------
    int
        The value read.

    Raises
    ------
    TimeoutError
        If the read never completes.
    """
    for _ in range(READ_ATTEMPTS):
        await driver.wait_status(dut, reg.STATUS_MDIO_BUSY, 0)
        await bus.write(dut, reg.IRQ_STATUS, reg.IRQ_MDIO_DONE)
        await bus.write(dut, reg.MDIO_CMD, (PHY_ADDRESS << 5) | register)
        await bus.cycles(dut, 4)
        await driver.wait_status(dut, reg.STATUS_MDIO_BUSY, 0)
        if await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_MDIO_DONE:
            return await bus.read(dut, reg.MDIO_DATA)
    message = f"MDIO read of register {register} never completed"
    raise TimeoutError(message)


def echo_request() -> bytes:
    """Build an ICMP echo request for the board.

    Returns
    -------
    bytes
        The Ethernet frame, without FCS.
    """
    icmp = struct.pack(">BBHHH", ICMP_ECHO_REQUEST, 0, 0, 0x1234, 1)
    icmp += bytes(range(32))
    icmp = icmp[:2] + struct.pack(">H", internet_checksum(icmp)) + icmp[4:]
    total = IPV4_HEADER + len(icmp)
    ip = struct.pack(
        ">BBHHHBBH4s4s",
        0x45,
        0,
        total,
        0x4242,
        0,
        TTL,
        PROTOCOL_ICMP,
        0,
        HOST_IP,
        BOARD_IP,
    )
    ip = ip[:10] + struct.pack(">H", internet_checksum(ip)) + ip[12:]
    head = driver.MAC_ADDRESS + HOST_MAC + ETHERTYPE_IPV4
    return head + ip + icmp


def echo_reply(request: bytes) -> bytes:
    """Answer an echo request the way a stack does.

    Parameters
    ----------
    request : bytes
        The request frame, without FCS.

    Returns
    -------
    bytes
        The reply frame, without FCS.
    """
    dst, src, kind = (
        request[:ADDRESS_BYTES],
        request[SRC_START:TYPE_START],
        request[TYPE_START:TYPE_END],
    )
    head = src + dst + kind
    ip = bytearray(request[TYPE_END:ICMP_START])
    ip[12:16], ip[16:20] = request[30:34], request[26:30]
    ip[10:12] = b"\x00\x00"
    ip[10:12] = struct.pack(">H", internet_checksum(bytes(ip)))
    icmp = bytearray(request[ICMP_START:])
    icmp[0] = ICMP_ECHO_REPLY
    icmp[2:4] = b"\x00\x00"
    icmp[2:4] = struct.pack(">H", internet_checksum(bytes(icmp)))
    return head + bytes(ip) + bytes(icmp)


@cocotb.test()
async def test_ping(dut: Dut) -> None:
    """A program answers an echo request at 1000 Mbit/s."""
    phy = await rgmii_driver.start(dut, 1000)
    await driver.configure(dut)
    await rgmii_driver.force_speed(dut, 1000)
    request = echo_request()
    phy.send(wire_bytes(request))
    await driver.wait_status(dut, reg.STATUS_RX_READY, reg.STATUS_RX_READY)
    received = await driver.read_frame(dut)
    check_equal(received, request)
    reply = echo_reply(received)
    await driver.send_frame(dut, reply)
    await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
    check_equal(len(phy.tx.frames), 1)
    wire = phy.decode(0)
    check_equal(wire, padded(reply) + fcs(padded(reply)))
    check_equal(internet_checksum(wire[TYPE_END:ICMP_START]), 0)
    check_equal(internet_checksum(wire[ICMP_START:-4]), 0)
    check_equal(wire[TYPE_END + IPV4_HEADER], ICMP_ECHO_REPLY)
    check_equal(wire[:ADDRESS_BYTES], HOST_MAC)

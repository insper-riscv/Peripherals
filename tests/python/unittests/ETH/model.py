"""Frames and PHY models of the Ethernet MAC tests."""

import zlib

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.dut import Dut

PREAMBLE_NIBBLES = 15
SFD_HIGH = 0xD
PREAMBLE_NIBBLE = 0x5
MIN_PAYLOAD = 60
FCS_LEN = 4
GAP_NIBBLES = 24
MDIO_PREAMBLE = 32
BAD_FCS_MASK = 0x01
RX_PINS = ("i_mii_rx_clk", "i_mii_rxd", "i_mii_rx_dv", "i_mii_rx_er")
TX_PINS = ("i_mii_tx_clk", "o_mii_tx_en", "o_mii_txd")


def fcs(frame: bytes) -> bytes:
    """Compute the FCS of a frame with the CRC-32 of the host library.

    Parameters
    ----------
    frame : bytes
        Frame from the destination address to the last payload byte.

    Returns
    -------
    bytes
        The four FCS bytes in transmission order.
    """
    return zlib.crc32(frame).to_bytes(FCS_LEN, "little")


def to_nibbles(data: bytes) -> list[int]:
    """Split bytes into nibbles, the low nibble of each byte first.

    Parameters
    ----------
    data : bytes
        Bytes to split.

    Returns
    -------
    list[int]
        The nibbles in MII order.
    """
    result: list[int] = []
    for byte in data:
        result.extend((byte & 0xF, byte >> 4))
    return result


def from_nibbles(nibbles: list[int]) -> bytes:
    """Join nibbles into bytes, the low nibble of each byte first.

    Parameters
    ----------
    nibbles : list[int]
        The nibbles in MII order, an even count.

    Returns
    -------
    bytes
        The joined bytes.
    """
    return bytes(
        nibbles[i] | (nibbles[i + 1] << 4)
        for i in range(0, len(nibbles) - 1, 2)
    )


def wire_nibbles(frame: bytes, *, bad_fcs: bool = False) -> list[int]:
    """Build the nibbles a PHY delivers for a frame.

    Parameters
    ----------
    frame : bytes
        Frame without FCS.
    bad_fcs : bool
        Corrupt one bit of the FCS.

    Returns
    -------
    list[int]
        Preamble, SFD, frame and FCS as MII nibbles.
    """
    check = bytearray(fcs(frame))
    if bad_fcs:
        check[-1] ^= BAD_FCS_MASK
    head = [PREAMBLE_NIBBLE] * PREAMBLE_NIBBLES + [SFD_HIGH]
    return head + to_nibbles(frame + bytes(check))


async def drive_rx(
    dut: Dut,
    nibbles: list[int],
    error_at: int | None = None,
    gap: int = GAP_NIBBLES,
    pins: tuple[str, str, str, str] = RX_PINS,
) -> None:
    """Drive nibbles into the receiver the way a PHY does.

    Parameters
    ----------
    dut : Dut
        The design under test.
    nibbles : list[int]
        Nibbles to present, one per RX_CLK.
    error_at : int | None
        Index of the nibble that carries RX_ER, if any.
    gap : int
        Idle RX_CLK cycles after the frame.
    pins : tuple[str, str, str, str]
        Names of the clock, data, valid and error ports.
    """
    clock, data, valid, error = (getattr(dut, name) for name in pins)
    for index, nibble in enumerate(nibbles):
        await RisingEdge(clock)
        data.value = nibble
        valid.value = 1
        error.value = int(index == error_at)
    for _ in range(gap):
        await RisingEdge(clock)
        valid.value = 0
        error.value = 0
        data.value = 0


class TxMonitor:
    """Capture the frames the transmitter puts on the MII.

    Attributes
    ----------
    frames : list[list[int]]
        Nibbles of each frame, taken while TX_EN is high.
    starts : list[int]
        TX_CLK cycle where each frame began.
    ends : list[int]
        TX_CLK cycle after the last nibble of each frame.
    """

    def __init__(self, dut: Dut, pins: tuple[str, str, str] = TX_PINS) -> None:
        """Start the capture on the TX_CLK of the design.

        Parameters
        ----------
        dut : Dut
            The design under test.
        pins : tuple[str, str, str]
            Names of the clock, enable and data ports.
        """
        self._clock, self._enable, self._data = (
            getattr(dut, name) for name in pins
        )
        self.frames: list[list[int]] = []
        self.starts: list[int] = []
        self.ends: list[int] = []
        cocotb.start_soon(self._run())

    async def _run(self) -> None:
        """Sample TXD and TX_EN at every rising edge of TX_CLK."""
        current: list[int] = []
        cycle = 0
        while True:
            await RisingEdge(self._clock)
            cycle += 1
            if int(self._enable.value):
                if not current:
                    self.starts.append(cycle)
                current.append(int(self._data.value))
            elif current:
                self.frames.append(current)
                self.ends.append(cycle)
                current = []

    def decode(self, index: int) -> bytes:
        """Return the bytes of a captured frame after preamble and SFD.

        Parameters
        ----------
        index : int
            Position of the frame in the capture.

        Returns
        -------
        bytes
            The frame with its FCS.

        Raises
        ------
        AssertionError
            If the preamble or the SFD is wrong.
        """
        nibbles = self.frames[index]
        head = nibbles[: PREAMBLE_NIBBLES + 1]
        want = [PREAMBLE_NIBBLE] * PREAMBLE_NIBBLES + [SFD_HIGH]
        if head != want:
            message = f"bad preamble or SFD: {head}"
            raise AssertionError(message)
        start = PREAMBLE_NIBBLES + 1
        return from_nibbles(nibbles[start:])

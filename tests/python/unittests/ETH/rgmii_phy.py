"""RGMII side of a PHY."""

from collections import deque
from dataclasses import dataclass, field

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer, Trigger
from cocotb.utils import get_sim_time

from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.model import (
    GAP_NIBBLES,
    fcs,
    from_nibbles,
    to_nibbles,
)

PREAMBLE_BYTES = 7
PREAMBLE_BYTE = 0x55
SFD_BYTE = 0xD5
GAP_BYTES = 12
NIBBLE_MASK = 0xF
NIBBLE_BITS = 4
CLOCK_DELAY_NS = 2
SPEED_PERIOD_NS = {1000: 8, 100: 40, 10: 400}
RX_PINS = ("i_rgmii_rxc", "i_rgmii_rxd", "i_rgmii_rx_ctl")
TX_PINS = ("o_rgmii_txc", "o_rgmii_txd", "o_rgmii_tx_ctl")


@dataclass(frozen=True)
class RxCycle:
    """One RXC cycle of the RGMII receive bus.

    Attributes
    ----------
    rise : int
        Data nibble on the rising edge of RXC.
    fall : int
        Data nibble on the falling edge of RXC.
    valid : int
        RX_DV of the cycle.
    error : int
        RX_ER of the cycle.
    """

    rise: int
    fall: int
    valid: int
    error: int


IDLE_CYCLE = RxCycle(0, 0, 0, 0)


def wire_bytes(frame: bytes, *, bad_fcs: bool = False) -> bytes:
    """Build the bytes a GMII PHY delivers for a frame.

    Parameters
    ----------
    frame : bytes
        Frame without FCS.
    bad_fcs : bool
        Corrupt one bit of the FCS.

    Returns
    -------
    bytes
        Preamble, SFD, frame and FCS.
    """
    check = bytearray(fcs(frame))
    if bad_fcs:
        check[-1] ^= 1
    head = bytes((PREAMBLE_BYTE,) * PREAMBLE_BYTES + (SFD_BYTE,))
    return head + frame + bytes(check)


@dataclass
class TxCapture:
    """What the transmit pins showed.

    Attributes
    ----------
    frames : list[bytes]
        Frames with the FCS, from the preamble.
    gaps : list[int]
        TXC cycles that TX_CTL stayed low after each frame.
    rise_times : list[int]
        Time in nanoseconds of each rising edge of TXC.
    fall_times : list[int]
        Time in nanoseconds of each falling edge of TXC.
    """

    frames: list[bytes] = field(default_factory=list[bytes])
    gaps: list[int] = field(default_factory=list[int])
    rise_times: list[int] = field(default_factory=list[int])
    fall_times: list[int] = field(default_factory=list[int])


class RgmiiPhy:
    """The RGMII pins of a PHY at one speed.

    The receive side generates RXC at the link speed and drives RXD
    and RX_CTL a fixed delay before each edge, as a PHY that delays the
    clock does. The transmit side samples TXD and TX_CTL on both
    edges of TXC and decodes frames.

    Attributes
    ----------
    speed : int
        Link speed in Mbit/s.
    period_ns : int
        Period of RXC and TXC in nanoseconds.
    tx : TxCapture
        What the transmit pins showed.
    fall_noise : bool
        Drive the other edge of a 10 or 100 Mbit/s cycle with noise.
    """

    def __init__(
        self, dut: Dut, speed: int, tx_sample_delay_ns: int = CLOCK_DELAY_NS
    ) -> None:
        """Start the receive clock and the transmit capture.

        Parameters
        ----------
        dut : Dut
            The design under test.
        speed : int
            Link speed in Mbit/s: 10, 100 or 1000.
        tx_sample_delay_ns : int
            Delay after each TXC edge at which TXD is sampled, which is
            the clock delay of a PHY that inserts it.
        """
        self.speed = speed
        self.period_ns = SPEED_PERIOD_NS[speed]
        self.tx = TxCapture()
        self.fall_noise = False
        self._dut = dut
        self._queue: deque[RxCycle] = deque()
        self._delay = tx_sample_delay_ns
        cocotb.start_soon(self._receive_clock())
        cocotb.start_soon(self._capture())

    @property
    def wide(self) -> bool:
        """Tell whether a byte travels per cycle (1000 Mbit/s)."""
        return self.speed == 1000  # noqa: PLR2004 - the gigabit speed

    @property
    def idle(self) -> bool:
        """Tell whether the receive queue is empty."""
        return not self._queue

    def _cycles_of(self, data: bytes, error_at: int | None) -> list[RxCycle]:
        """Turn bytes into the RXC cycles that carry them.

        Parameters
        ----------
        data : bytes
            Bytes of the wire, from the preamble to the FCS.
        error_at : int | None
            Index of the cycle that carries RX_ER, if any.

        Returns
        -------
        list[RxCycle]
            One cycle per byte at 1000 Mbit/s, one per nibble below.
        """
        if self.wide:
            units = [
                (byte & NIBBLE_MASK, byte >> NIBBLE_BITS) for byte in data
            ]
        else:
            units = [
                (nibble, nibble ^ NIBBLE_MASK if self.fall_noise else nibble)
                for nibble in to_nibbles(data)
            ]
        return [
            RxCycle(rise, fall, 1, int(index == error_at))
            for index, (rise, fall) in enumerate(units)
        ]

    def send(
        self,
        data: bytes,
        error_at: int | None = None,
        gap: int | None = None,
    ) -> None:
        """Queue bytes for the receiver, followed by an idle gap.

        Parameters
        ----------
        data : bytes
            Bytes of the wire, from the preamble to the FCS.
        error_at : int | None
            Index of the cycle that carries RX_ER, if any.
        gap : int | None
            Idle RXC cycles after the data, by default the gap.
        """
        self._queue.extend(self._cycles_of(data, error_at))
        idle = gap if gap is not None else self._gap_cycles()
        self._queue.extend([IDLE_CYCLE] * idle)

    def _gap_cycles(self) -> int:
        """Return the interframe gap in RXC cycles."""
        return GAP_BYTES if self.wide else GAP_NIBBLES

    async def drain(self) -> None:
        """Wait until the queued data has left the pins."""
        while self._queue:
            await Timer(self.period_ns, unit="ns")
        await Timer(self.period_ns, unit="ns")

    async def _receive_clock(self) -> None:
        """Generate RXC and drive RXD and RX_CTL ahead of each edge."""
        clock, data, control = (getattr(self._dut, n) for n in RX_PINS)
        half = self.period_ns // 2
        data.value = 0
        control.value = 0
        clock.value = 0
        while True:
            cycle = self._queue.popleft() if self._queue else IDLE_CYCLE
            data.value = cycle.rise
            control.value = cycle.valid
            await Timer(CLOCK_DELAY_NS, unit="ns")
            clock.value = 1
            await Timer(half - CLOCK_DELAY_NS, unit="ns")
            data.value = cycle.fall
            control.value = cycle.valid ^ cycle.error
            await Timer(CLOCK_DELAY_NS, unit="ns")
            clock.value = 0
            await Timer(half - CLOCK_DELAY_NS, unit="ns")

    async def _sample(self, edge: Trigger) -> tuple[int, int]:
        """Wait for an edge of TXC and sample the data pins.

        Parameters
        ----------
        edge : Trigger
            The cocotb trigger of the edge.

        Returns
        -------
        tuple[int, int]
            TXD and TX_CTL.
        """
        await edge
        if self._delay:
            await Timer(self._delay, unit="ns")
        data = getattr(self._dut, TX_PINS[1])
        control = getattr(self._dut, TX_PINS[2])
        return int(data.value), int(control.value)

    async def _capture(self) -> None:
        """Decode the frames of the transmit pins."""
        clock = getattr(self._dut, TX_PINS[0])
        units: list[int] = []
        gap = 0
        while True:
            rise_data, rise_ctl = await self._sample(RisingEdge(clock))
            self.tx.rise_times.append(int(get_sim_time("ns")))
            fall_data, fall_ctl = await self._sample(FallingEdge(clock))
            self.tx.fall_times.append(int(get_sim_time("ns")))
            if rise_ctl:
                if gap and self.tx.frames:
                    self.tx.gaps.append(gap)
                gap = 0
                units.append(self._unit(rise_data, fall_data, fall_ctl))
            elif units:
                self._finish(units)
                units = []
                gap = 1
            elif gap:
                gap += 1

    def _unit(self, rise: int, fall: int, fall_ctl: int) -> int:
        """Return the unit a TXC cycle carries.

        Parameters
        ----------
        rise : int
            Data sampled on the rising edge.
        fall : int
            Data sampled on the falling edge.
        fall_ctl : int
            TX_CTL sampled on the falling edge, TX_EN xor TX_ER.

        Returns
        -------
        int
            The byte at 1000 Mbit/s, else the nibble.

        Raises
        ------
        AssertionError
            If TX_ER is set, or a slower speed repeats no nibble.
        """
        if fall_ctl != 1:
            message = "TX_ER is not zero while TX_EN is high"
            raise AssertionError(message)
        if self.wide:
            return rise | (fall << NIBBLE_BITS)
        if fall != rise:
            message = f"nibble not repeated: {rise:#x} then {fall:#x}"
            raise AssertionError(message)
        return rise

    def decode(self, index: int) -> bytes:
        """Return a captured frame after the preamble and the SFD.

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
        data = self.tx.frames[index]
        head = data[: PREAMBLE_BYTES + 1]
        want = bytes((PREAMBLE_BYTE,) * PREAMBLE_BYTES + (SFD_BYTE,))
        if head != want:
            message = f"bad preamble or SFD: {head.hex()}"
            raise AssertionError(message)
        start = PREAMBLE_BYTES + 1
        return data[start:]

    def _finish(self, units: list[int]) -> None:
        """Store a frame whose TX_CTL went low.

        Parameters
        ----------
        units : list[int]
            Bytes at 1000 Mbit/s, else nibbles.
        """
        data = bytes(units) if self.wide else from_nibbles(units)
        self.tx.frames.append(data)

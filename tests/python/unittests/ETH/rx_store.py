"""Frame store alone: FIFO words in, buffer and events out."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import MAC_ADDRESS, pulse
from tests.python.unittests.ETH.frames_rx import (
    BROADCAST,
    GROUP,
    OTHER,
    make_frame,
)

CLOCK_NS = 10
LAST = 0x100
EVENTS = (
    "o_ev_frame",
    "o_ev_crc",
    "o_ev_phy",
    "o_ev_dropped",
    "o_ev_filtered",
)
BUFFER_BYTES = 16 * 4
FLAG_CRC = 0x01
FLAG_RUNT = 0x08
FLAG_OVERFLOW = 0x10
MAC_VALUE = int.from_bytes(MAC_ADDRESS, "little")


class Store:
    """Test bench around the store: FIFO feed, buffer and event capture.

    Attributes
    ----------
    memory : dict[int, int]
        Words written to the buffer by address.
    events : dict[str, int]
        Count of each event pulse.
    """

    def __init__(self, dut: Dut) -> None:
        """Start the clock, reset the store and watch its outputs.

        Parameters
        ----------
        dut : Dut
            The design under test.
        """
        self.memory: dict[int, int] = {}
        self.events = dict.fromkeys(EVENTS, 0)
        self._dut = dut
        self._queue: list[int] = []
        cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
        dut.i_rst.value = 1
        dut.i_empty.value = 1
        dut.i_word.value = 0
        dut.i_mac_addr.value = MAC_VALUE
        dut.i_enable.value = 1
        dut.i_promiscuous.value = 0
        dut.i_broadcast.value = 1
        dut.i_multicast.value = 0
        dut.i_accept_errors.value = 0
        dut.i_release.value = 0
        cocotb.start_soon(self._fifo())
        cocotb.start_soon(self._watch())

    async def _fifo(self) -> None:
        """Present the queue head and pop it when the store reads."""
        dut = self._dut
        while True:
            dut.i_empty.value = int(not self._queue)
            dut.i_word.value = self._queue[0] if self._queue else 0
            await RisingEdge(dut.i_clk)
            if self._queue and int(dut.o_rd_en.value):
                self._queue.pop(0)

    async def _watch(self) -> None:
        """Record the buffer writes and the event pulses."""
        dut = self._dut
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.o_ram_we.value):
                self.memory[int(dut.o_ram_addr.value)] = int(
                    dut.o_ram_data.value
                )
            for name in EVENTS:
                self.events[name] += int(getattr(dut, name).value)

    async def release_reset(self) -> None:
        """Hold the reset for a few cycles and release it."""
        for _ in range(3):
            await RisingEdge(self._dut.i_clk)
        self._dut.i_rst.value = 0

    async def send(self, frame: bytes, flags: int = 0) -> None:
        """Queue the bytes of a frame and the final word, and wait.

        Parameters
        ----------
        frame : bytes
            Frame without FCS.
        flags : int
            Flags of the final word.
        """
        self._queue.extend(frame)
        self._queue.append(LAST | flags)
        for _ in range(len(frame) + 20):
            await RisingEdge(self._dut.i_clk)
        await Timer(1, unit="ns")

    def stored(self, length: int) -> bytes:
        """Return the first bytes of the buffer.

        Parameters
        ----------
        length : int
            Number of bytes to return.

        Returns
        -------
        bytes
            The bytes of the buffer words, the first byte first.
        """
        words = [self.memory.get(i, 0) for i in range((length + 3) // 4)]
        data = b"".join(word.to_bytes(4, "little") for word in words)
        return data[:length]


@cocotb.test()
async def test_accepts_own_frame(dut: Dut) -> None:
    """A frame for this MAC fills the buffer and becomes ready."""
    store = Store(dut)
    await store.release_reset()
    frame = make_frame(MAC_ADDRESS, 30, 1)
    await store.send(frame)
    check_equal(int(dut.o_frame_ready.value), 1)
    check_equal(int(dut.o_frame_len.value), len(frame))
    check_equal(store.stored(len(frame)), frame)
    check_equal(store.events["o_ev_frame"], 1)
    await pulse(dut.i_clk, dut.i_release)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_frame_ready.value), 0)


@cocotb.test()
async def test_filter(dut: Dut) -> None:
    """Other, group and broadcast destinations follow the filter."""
    store = Store(dut)
    await store.release_reset()
    await store.send(make_frame(OTHER, 30, 2))
    check_equal(store.events["o_ev_filtered"], 1)
    await store.send(make_frame(GROUP, 30, 3))
    check_equal(store.events["o_ev_filtered"], 2)
    check_equal(int(dut.o_frame_ready.value), 0)
    dut.i_multicast.value = 1
    await store.send(make_frame(GROUP, 30, 4))
    check_equal(int(dut.o_frame_ready.value), 1)
    await pulse(dut.i_clk, dut.i_release)
    dut.i_multicast.value = 0
    dut.i_broadcast.value = 0
    await store.send(make_frame(BROADCAST, 30, 5))
    check_equal(store.events["o_ev_filtered"], 3)
    dut.i_promiscuous.value = 1
    await store.send(make_frame(OTHER, 30, 6))
    check_equal(int(dut.o_frame_ready.value), 1)


@cocotb.test()
async def test_errors(dut: Dut) -> None:
    """Flags count as errors; accept-errors delivers the frame."""
    store = Store(dut)
    await store.release_reset()
    frame = make_frame(MAC_ADDRESS, 30, 7)
    await store.send(frame, FLAG_CRC)
    check_equal(store.events["o_ev_crc"], 1)
    await store.send(frame, FLAG_RUNT)
    check_equal(store.events["o_ev_phy"], 1)
    check_equal(int(dut.o_frame_ready.value), 0)
    dut.i_accept_errors.value = 1
    await store.send(frame, FLAG_CRC)
    check_equal(int(dut.o_frame_ready.value), 1)
    check_equal(store.stored(len(frame)), frame)


@cocotb.test()
async def test_drops(dut: Dut) -> None:
    """A frame with the buffer busy, too long or lost is dropped."""
    store = Store(dut)
    await store.release_reset()
    frame = make_frame(MAC_ADDRESS, 30, 8)
    await store.send(frame)
    await store.send(make_frame(MAC_ADDRESS, 30, 9))
    check_equal(store.events["o_ev_dropped"], 1)
    check_equal(store.stored(len(frame)), frame)
    await pulse(dut.i_clk, dut.i_release)
    await store.send(make_frame(MAC_ADDRESS, BUFFER_BYTES + 8, 3))
    check_equal(store.events["o_ev_dropped"], 2)
    check_equal(int(dut.o_frame_ready.value), 0)
    await store.send(frame, FLAG_OVERFLOW)
    check_equal(store.events["o_ev_dropped"], 3)

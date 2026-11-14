"""Transmitter at 1000 Mbit/s and with clock enables."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import pack_words, reset_edges
from tests.python.unittests.ETH.model import (
    GAP_NIBBLES,
    MIN_PAYLOAD,
    fcs,
    from_nibbles,
)
from tests.python.unittests.ETH.rgmii_phy import (
    GAP_BYTES,
    PREAMBLE_BYTE,
    PREAMBLE_BYTES,
    SFD_BYTE,
)
from tests.python.utils.rng import seeded

CLOCK_NS = 8
TIMEOUT_CYCLES = 200000


class Bench:
    """Clock, enables, buffer model and capture of the transmitter.

    Attributes
    ----------
    units : list[int]
        Value of o_txd at each enable where o_tx_en is high.
    idle : list[int]
        Enables with o_tx_en low until o_done.
    """

    def __init__(self, dut: Dut, *, wide: bool, every: int) -> None:
        """Start the clock and the models.

        Parameters
        ----------
        dut : Dut
            The design under test.
        wide : bool
            One byte per enable when true, one nibble when false.
        every : int
            Clock cycles between enables; 1 keeps the enable high.
        """
        self.dut = dut
        self.wide = wide
        self.every = every
        self.words: list[int] = []
        self.units: list[int] = []
        self.idle: list[int] = []
        cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
        cocotb.start_soon(self._enables())
        cocotb.start_soon(self._buffer())
        cocotb.start_soon(self._capture())
        dut.i_wide.value = int(wide)
        dut.i_start.value = 0
        dut.i_length.value = 0

    async def _enables(self) -> None:
        """Pulse i_ce once in every few clock cycles."""
        dut = self.dut
        while True:
            dut.i_ce.value = 1
            await RisingEdge(dut.i_clk)
            if self.every > 1:
                dut.i_ce.value = 0
                for _ in range(self.every - 1):
                    await RisingEdge(dut.i_clk)

    async def _buffer(self) -> None:
        """Answer each address one clock later, as a RAM does."""
        dut = self.dut
        while True:
            await RisingEdge(dut.i_clk)
            address = int(dut.o_ram_addr.value)
            dut.i_ram_data.value = (
                self.words[address] if address < len(self.words) else 0
            )

    async def _capture(self) -> None:
        """Record the output at each enable."""
        dut = self.dut
        after = False
        run = 0
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.o_done.value) and after:
                self.idle.append(run)
                after = False
                run = 0
            if not int(dut.i_ce.value):
                continue
            if int(dut.o_tx_en.value):
                self.units.append(int(dut.o_txd.value))
                after = True
            elif after:
                run += 1

    async def transmit(
        self, frame: bytes, offset: int = 0
    ) -> tuple[list[int], int]:
        """Send one frame and return its units and the gap in enables.

        Parameters
        ----------
        frame : bytes
            Frame without FCS.
        offset : int
            Clock cycles between the reset and the i_start pulse.

        Returns
        -------
        tuple[list[int], int]
            The units sent from the preamble, and the enables
            between the last unit and the end pulse.
        """
        dut = self.dut
        self.words[:] = pack_words(frame)
        self.units.clear()
        self.idle.clear()
        await reset_edges(dut, 3)
        for _ in range(offset):
            await RisingEdge(dut.i_clk)
        dut.i_length.value = len(frame)
        dut.i_start.value = 1
        await RisingEdge(dut.i_clk)
        dut.i_start.value = 0
        for _ in range(TIMEOUT_CYCLES):
            await RisingEdge(dut.i_clk)
            if self.idle:
                break
        await Timer(1, unit="ns")
        check_true(self.idle, "the frame never ended")
        return list(self.units), self.idle[0]


def decode(units: list[int], *, wide: bool) -> bytes:
    """Return the bytes of a frame after the preamble and the SFD.

    Parameters
    ----------
    units : list[int]
        Bytes or nibbles of the frame, from the first preamble unit.
    wide : bool
        The units are bytes when true, nibbles when false.

    Returns
    -------
    bytes
        The frame with its FCS.
    """
    data = bytes(units) if wide else from_nibbles(units)
    start = PREAMBLE_BYTES + 1
    head = data[:start]
    want = bytes((PREAMBLE_BYTE,) * PREAMBLE_BYTES + (SFD_BYTE,))
    check_equal(head, want)
    return data[start:]


@cocotb.test()
async def test_gigabit_frame(dut: Dut) -> None:
    """A byte per cycle: preamble, content, FCS and gap."""
    bench = Bench(dut, wide=True, every=1)
    for length in (61, 64, 100, 1514):
        frame = seeded(length).randbytes(length)
        units, gap = await bench.transmit(frame)
        check_equal(decode(units, wide=True), frame + fcs(frame))
        check_equal(len(units), PREAMBLE_BYTES + 1 + length + 4)
        check_true(GAP_BYTES - 3 <= gap <= GAP_BYTES, f"gap {gap}")


@cocotb.test()
async def test_gigabit_padding(dut: Dut) -> None:
    """A frame of one byte is filled with zeros up to 60 bytes."""
    bench = Bench(dut, wide=True, every=1)
    frame = bytes((0xA5,))
    units, _ = await bench.transmit(frame)
    padded = frame + bytes(MIN_PAYLOAD - 1)
    check_equal(decode(units, wide=True), padded + fcs(padded))


async def clock_enable_case(dut: Dut, every: int) -> None:
    """Send frames with one enable in every few cycles.

    Parameters
    ----------
    dut : Dut
        The design under test.
    every : int
        Clock cycles between enables.
    """
    bench = Bench(dut, wide=False, every=every)
    for offset in (7, 8):
        frame = seeded(every + offset).randbytes(80)
        units, gap = await bench.transmit(frame, offset=offset)
        check_equal(decode(units, wide=False), frame + fcs(frame))
        check_true(GAP_NIBBLES - 3 <= gap <= GAP_NIBBLES, f"gap {gap}")


@cocotb.test()
async def test_enable_every_five(dut: Dut) -> None:
    """With an enable every five cycles the frame is intact."""
    await clock_enable_case(dut, 5)


@cocotb.test()
async def test_enable_every_fifty(dut: Dut) -> None:
    """With an enable every fifty cycles the frame is intact."""
    await clock_enable_case(dut, 50)

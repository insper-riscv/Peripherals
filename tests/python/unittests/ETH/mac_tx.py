"""Transmitter alone: a buffer model feeds the sequencer."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import (
    pack_words,
    reset_edges,
    start_and_wait_done,
)
from tests.python.unittests.ETH.model import (
    GAP_NIBBLES,
    MIN_PAYLOAD,
    TxMonitor,
    fcs,
)
from tests.python.utils.rng import seeded

CLOCK_NS = 40
ENTITY_TX_PINS = ("i_clk", "o_tx_en", "o_txd")


async def buffer_model(dut: Dut, words: list[int]) -> None:
    """Answer each address with the word one clock later, as a RAM does.

    Parameters
    ----------
    dut : Dut
        The design under test.
    words : list[int]
        Content of the buffer.
    """
    while True:
        await RisingEdge(dut.i_clk)
        address = int(dut.o_ram_addr.value)
        value = words[address] if address < len(words) else 0
        dut.i_ram_data.value = value


async def ticks(dut: Dut, count: list[int]) -> None:
    """Count the clock edges since the capture began.

    Parameters
    ----------
    dut : Dut
        The design under test.
    count : list[int]
        One-element list that holds the edge count.
    """
    while True:
        await RisingEdge(dut.i_clk)
        count[0] += 1


async def transmit(dut: Dut, frame: bytes) -> tuple[TxMonitor, int]:
    """Run one transmission to the end of the gap.

    Parameters
    ----------
    dut : Dut
        The design under test.
    frame : bytes
        Frame without FCS.

    Returns
    -------
    tuple[TxMonitor, int]
        The capture, and the edge count at which done was seen.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    cocotb.start_soon(buffer_model(dut, pack_words(frame)))
    monitor = TxMonitor(dut, ENTITY_TX_PINS)
    count = [0]
    cocotb.start_soon(ticks(dut, count))
    dut.i_start.value = 0
    dut.i_length.value = 0
    await reset_edges(dut, 3)
    dut.i_length.value = len(frame)
    await start_and_wait_done(dut)
    return monitor, count[0]


@cocotb.test()
async def test_frame(dut: Dut) -> None:
    """The frame leaves with preamble, SFD, content and FCS."""
    frame = seeded(1).randbytes(61)
    monitor, _ = await transmit(dut, frame)
    check_equal(monitor.decode(0), frame + fcs(frame))


@cocotb.test()
async def test_padding(dut: Dut) -> None:
    """A frame of one byte is filled with zeros up to 60 bytes."""
    frame = bytes((0xA5,))
    monitor, _ = await transmit(dut, frame)
    padded = frame + bytes(MIN_PAYLOAD - 1)
    check_equal(monitor.decode(0), padded + fcs(padded))


@cocotb.test()
async def test_gap(dut: Dut) -> None:
    """The gap of 24 nibbles starts counting at the first idle edge."""
    frame = seeded(2).randbytes(100)
    monitor, done_edge = await transmit(dut, frame)
    gap = done_edge - monitor.ends[0]
    check_true(GAP_NIBBLES - 3 <= gap <= GAP_NIBBLES, f"gap {gap}")

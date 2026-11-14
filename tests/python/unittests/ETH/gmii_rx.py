"""Receiver at 1000 Mbit/s: a byte per cycle in, bytes and flags out."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import reset_edges
from tests.python.unittests.ETH.mac_rx import (
    FLAG_CRC,
    FLAG_PHY,
    FLAG_RUNT,
    GAP,
    LAST,
    collect,
    split,
)
from tests.python.unittests.ETH.rgmii_phy import wire_bytes
from tests.python.utils.rng import seeded

CLOCK_NS = 8
IDLE_PINS = ("i_rxd", "i_rx_dv", "i_rx_er", "i_full", "i_full_next")


async def begin(dut: Dut) -> list[int]:
    """Start the clock and the collector and reset the receiver.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    list[int]
        The list that receives the words written to the FIFO.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    words: list[int] = []
    cocotb.start_soon(collect(dut, words))
    dut.i_wide.value = 1
    for name in IDLE_PINS:
        getattr(dut, name).value = 0
    return words


async def receive(
    dut: Dut, words: list[int], data: bytes, error_at: int | None = None
) -> None:
    """Reset, present one frame a byte per cycle and collect the words.

    Parameters
    ----------
    dut : Dut
        The design under test.
    words : list[int]
        Receives the words written to the FIFO.
    data : bytes
        Bytes of the wire, from the preamble to the FCS.
    error_at : int | None
        Index of the byte with RX_ER.
    """
    await reset_edges(dut, 3)
    words.clear()
    for index, byte in enumerate(data):
        await RisingEdge(dut.i_clk)
        dut.i_rxd.value = byte
        dut.i_rx_dv.value = 1
        dut.i_rx_er.value = int(index == error_at)
    for _ in range(GAP):
        await RisingEdge(dut.i_clk)
        dut.i_rx_dv.value = 0
        dut.i_rx_er.value = 0
        dut.i_rxd.value = 0


@cocotb.test()
async def test_good_frame(dut: Dut) -> None:
    """Frames of several sizes arrive without the FCS."""
    words = await begin(dut)
    for length in (60, 61, 64, 100, 1514):
        frame = seeded(length).randbytes(length)
        await receive(dut, words, wire_bytes(frame))
        check_equal(words[-1] & LAST, LAST)
        check_equal(split(words), (frame, 0))


@cocotb.test()
async def test_bad_fcs(dut: Dut) -> None:
    """A corrupt FCS sets the CRC flag and nothing else."""
    words = await begin(dut)
    frame = seeded(2).randbytes(70)
    await receive(dut, words, wire_bytes(frame, bad_fcs=True))
    check_equal(split(words), (frame, FLAG_CRC))


@cocotb.test()
async def test_phy_error_and_runt(dut: Dut) -> None:
    """RX_ER sets the PHY flag, and a short frame sets the runt flag."""
    words = await begin(dut)
    frame = seeded(3).randbytes(70)
    await receive(dut, words, wire_bytes(frame), error_at=20)
    check_equal(split(words)[1], FLAG_PHY)
    short = seeded(5).randbytes(30)
    await receive(dut, words, wire_bytes(short))
    check_equal(split(words), (short, FLAG_RUNT))

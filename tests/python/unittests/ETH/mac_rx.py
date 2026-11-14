"""Receiver alone: nibbles in, bytes and flags out."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import reset_edges
from tests.python.unittests.ETH.model import drive_rx, wire_nibbles
from tests.python.utils.rng import seeded

CLOCK_NS = 40
ENTITY_RX_PINS = ("i_clk", "i_rxd", "i_rx_dv", "i_rx_er")
LAST = 0x100
FLAG_CRC = 0x01
FLAG_PHY = 0x02
FLAG_ALIGN = 0x04
FLAG_RUNT = 0x08
FLAG_OVERFLOW = 0x10
GAP = 40


async def collect(dut: Dut, words: list[int]) -> None:
    """Record every word the receiver writes to the FIFO.

    Parameters
    ----------
    dut : Dut
        The design under test.
    words : list[int]
        Receives the words in order.
    """
    while True:
        await RisingEdge(dut.i_clk)
        if int(dut.o_wr_en.value):
            words.append(int(dut.o_wr_data.value))


async def receive(
    dut: Dut,
    nibbles: list[int],
    error_at: int | None = None,
    full: int = 0,
) -> list[int]:
    """Present one frame and return the words written.

    Parameters
    ----------
    dut : Dut
        The design under test.
    nibbles : list[int]
        Nibbles of the frame.
    error_at : int | None
        Index of the nibble with RX_ER.
    full : int
        Value of the FIFO full input.

    Returns
    -------
    list[int]
        The words written.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    words: list[int] = []
    cocotb.start_soon(collect(dut, words))
    dut.i_rxd.value = 0
    dut.i_rx_dv.value = 0
    dut.i_rx_er.value = 0
    dut.i_full.value = full
    await reset_edges(dut, 3)
    await drive_rx(dut, nibbles, error_at, GAP, ENTITY_RX_PINS)
    return words


def split(words: list[int]) -> tuple[bytes, int]:
    """Separate the bytes of a frame from the flags of the final word.

    Parameters
    ----------
    words : list[int]
        Words written to the FIFO.

    Returns
    -------
    tuple[bytes, int]
        The frame bytes and the flags.
    """
    data = bytes(word & 0xFF for word in words[:-1])
    return data, words[-1] & 0x3F


@cocotb.test()
async def test_good_frame(dut: Dut) -> None:
    """The frame arrives without its FCS and with no flag set."""
    frame = seeded(1).randbytes(70)
    words = await receive(dut, wire_nibbles(frame))
    check_equal(words[-1] & LAST, LAST)
    check_equal(all(not word & LAST for word in words[:-1]), True)
    check_equal(split(words), (frame, 0))


@cocotb.test()
async def test_bad_fcs(dut: Dut) -> None:
    """A corrupt FCS sets the CRC flag and nothing else."""
    frame = seeded(2).randbytes(70)
    words = await receive(dut, wire_nibbles(frame, bad_fcs=True))
    check_equal(split(words), (frame, FLAG_CRC))


@cocotb.test()
async def test_phy_error(dut: Dut) -> None:
    """RX_ER inside the frame sets the PHY flag."""
    frame = seeded(3).randbytes(70)
    words = await receive(dut, wire_nibbles(frame), error_at=30)
    check_equal(split(words)[1], FLAG_PHY)


@cocotb.test()
async def test_alignment_and_runt(dut: Dut) -> None:
    """An odd nibble count sets the alignment flag, a runt its flag."""
    frame = seeded(4).randbytes(70)
    words = await receive(dut, wire_nibbles(frame)[:-1])
    check_equal(split(words)[1] & FLAG_ALIGN, FLAG_ALIGN)
    short = seeded(5).randbytes(30)
    words = await receive(dut, wire_nibbles(short))
    check_equal(split(words), (short, FLAG_RUNT))
    check_equal(len(words), len(short) + 1)


@cocotb.test()
async def test_fifo_full(dut: Dut) -> None:
    """With the FIFO full the bytes are lost, and the flag says so."""
    frame = seeded(6).randbytes(70)
    words = await receive(dut, wire_nibbles(frame), full=1)
    check_equal(words, [])
    dut.i_full.value = 0
    for _ in range(4):
        await RisingEdge(dut.i_clk)
    check_equal(words[-1] & LAST, LAST)
    check_equal(words[-1] & FLAG_OVERFLOW, FLAG_OVERFLOW)

"""Gray-code asynchronous FIFO: order, capacity and flags."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import hold, start_clocks
from tests.python.utils.rng import seeded

WRITE_NS = 7
READ_NS = 11
DEPTH = 8
WORDS = 400
RESET_EDGES = 6
IDLE_LIMIT = 20000


async def start(dut: Dut, write_ns: int, read_ns: int) -> None:
    """Start both clocks and reset both sides.

    Parameters
    ----------
    dut : Dut
        The design under test.
    write_ns : int
        Period of the write clock.
    read_ns : int
        Period of the read clock.
    """
    start_clocks((dut.i_wclk, write_ns), (dut.i_rclk, read_ns))
    dut.i_wr_en.value = 0
    dut.i_rd_en.value = 0
    dut.i_wdata.value = 0
    await hold(dut.i_wclk, [dut.i_wrst, dut.i_rrst], RESET_EDGES)
    for _ in range(RESET_EDGES):
        await RisingEdge(dut.i_rclk)


async def writer(dut: Dut, words: list[int], pace: int, seed: int) -> None:
    """Push the words in order, with random pauses.

    Parameters
    ----------
    dut : Dut
        The design under test.
    words : list[int]
        Words to write.
    pace : int
        One in this many cycles tries to write.
    seed : int
        Seed of the pauses.
    """
    rng = seeded(seed)
    index = 0
    while index < len(words):
        want = rng.randrange(pace) == 0
        dut.i_wr_en.value = int(want)
        dut.i_wdata.value = words[index]
        await RisingEdge(dut.i_wclk)
        if want and not int(dut.o_full.value):
            index += 1
    dut.i_wr_en.value = 0


async def reader(dut: Dut, count: int, pace: int, seed: int) -> list[int]:
    """Pop words with random pauses.

    Parameters
    ----------
    dut : Dut
        The design under test.
    count : int
        Number of words to collect.
    pace : int
        One in this many cycles tries to read.
    seed : int
        Seed of the pauses.

    Returns
    -------
    list[int]
        The words in the order they came out.
    """
    rng = seeded(seed)
    got: list[int] = []
    for _ in range(IDLE_LIMIT):
        want = rng.randrange(pace) == 0
        dut.i_rd_en.value = int(want)
        await RisingEdge(dut.i_rclk)
        if want and not int(dut.o_empty.value):
            got.append(int(dut.o_rdata.value))
            if len(got) == count:
                break
    dut.i_rd_en.value = 0
    return got


async def transfer(dut: Dut, wpace: int, rpace: int) -> None:
    """Move a random sequence through the FIFO and compare it.

    Parameters
    ----------
    dut : Dut
        The design under test.
    wpace : int
        Write pacing.
    rpace : int
        Read pacing.
    """
    rng = seeded(3)
    words = [rng.randrange(256) for _ in range(WORDS)]
    sent = cocotb.start_soon(writer(dut, words, wpace, 11))
    got = await reader(dut, WORDS, rpace, 12)
    await sent
    check_equal(got, words)


@cocotb.test()
async def test_fast_writer(dut: Dut) -> None:
    """A faster writer loses and reorders nothing."""
    await start(dut, WRITE_NS, READ_NS)
    await transfer(dut, 1, 3)


@cocotb.test()
async def test_fast_reader(dut: Dut) -> None:
    """A faster reader loses and reorders nothing."""
    await start(dut, READ_NS, WRITE_NS)
    await transfer(dut, 3, 1)


@cocotb.test()
async def test_capacity(dut: Dut) -> None:
    """It accepts exactly the depth, then reports full."""
    await start(dut, WRITE_NS, READ_NS)
    check_equal(int(dut.o_empty.value), 1)
    accepted = 0
    for value in range(DEPTH + 4):
        dut.i_wr_en.value = 1
        dut.i_wdata.value = value
        await RisingEdge(dut.i_wclk)
        if not int(dut.o_full.value):
            accepted += 1
    dut.i_wr_en.value = 0
    check_equal(accepted, DEPTH)
    check_equal(int(dut.o_full.value), 1)
    got = await reader(dut, DEPTH, 1, 5)
    check_equal(got, list(range(DEPTH)))
    for _ in range(RESET_EDGES * 2):
        await RisingEdge(dut.i_rclk)
    check_equal(int(dut.o_empty.value), 1)
    check_true(not int(dut.o_full.value))

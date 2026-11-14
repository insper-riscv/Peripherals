"""Dual-clock memory: write at one clock, read at another."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import start_clocks
from tests.python.utils.rng import seeded

WRITE_NS = 7
READ_NS = 11
WORDS = 24
SETTLE_EDGES = 3


async def start(dut: Dut) -> None:
    """Start both clocks and idle the ports.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    start_clocks((dut.i_wclk, WRITE_NS), (dut.i_rclk, READ_NS))
    dut.i_we.value = 0
    dut.i_waddr.value = 0
    dut.i_wdata.value = 0
    dut.i_raddr.value = 0
    await RisingEdge(dut.i_wclk)


async def read_at(dut: Dut, address: int) -> int:
    """Read one address, with the latency of one read clock.

    Parameters
    ----------
    dut : Dut
        The design under test.
    address : int
        Address to read.

    Returns
    -------
    int
        The word the memory returns.
    """
    dut.i_raddr.value = address
    for _ in range(SETTLE_EDGES):
        await RisingEdge(dut.i_rclk)
    return int(dut.o_rdata.value)


@cocotb.test()
async def test_write_then_read(dut: Dut) -> None:
    """Every written word reads back, and an overwrite replaces it."""
    await start(dut)
    rng = seeded(1)
    words = [rng.getrandbits(32) for _ in range(WORDS)]
    for address, word in enumerate(words):
        dut.i_we.value = 1
        dut.i_waddr.value = address
        dut.i_wdata.value = word
        await RisingEdge(dut.i_wclk)
    dut.i_we.value = 0
    for address, word in enumerate(words):
        check_equal(await read_at(dut, address), word)
    dut.i_we.value = 1
    dut.i_waddr.value = 3
    dut.i_wdata.value = 0xDEADBEEF
    await RisingEdge(dut.i_wclk)
    dut.i_we.value = 0
    check_equal(await read_at(dut, 3), 0xDEADBEEF)
    check_equal(await read_at(dut, 4), words[4])


@cocotb.test()
async def test_write_enable(dut: Dut) -> None:
    """Without the write enable the memory keeps its content."""
    await start(dut)
    dut.i_waddr.value = 100
    dut.i_wdata.value = 0x1234
    await RisingEdge(dut.i_wclk)
    await RisingEdge(dut.i_wclk)
    check_equal(await read_at(dut, 100), 0)

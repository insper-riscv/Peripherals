"""Speed selection: the SPEED register and the PHY poll."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal, check_true
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH import registers as reg
from tests.python.unittests.ETH.driver import reset_edges

CLOCK_NS = 20
PHY_ADDRESS = 16
POLL_CYCLES = 8
MASTER_LATENCY = 5
STATUS_1000 = (2 << 14) | reg.PHY_STATUS_LINK | reg.PHY_STATUS_RESOLVED
STATUS_100 = (1 << 14) | reg.PHY_STATUS_LINK | reg.PHY_STATUS_RESOLVED
RESERVED = (3 << 14) | reg.PHY_STATUS_LINK | reg.PHY_STATUS_RESOLVED


async def master(dut: Dut, answers: dict[str, int], starts: list[int]) -> None:
    """Play the MDIO master: each start is answered some cycles later.

    Parameters
    ----------
    dut : Dut
        The design under test.
    answers : dict[str, int]
        The `rdata` the master returns and `no_ack` (0 or 1).
    starts : list[int]
        Receives the register address of each start.
    """
    while True:
        await RisingEdge(dut.i_clk)
        if int(dut.o_mdio_start.value):
            starts.append(int(dut.o_mdio_reg_addr.value))
            check_equal(int(dut.o_mdio_phy_addr.value), PHY_ADDRESS)
            dut.i_mdio_busy.value = 1
            for _ in range(MASTER_LATENCY):
                await RisingEdge(dut.i_clk)
            dut.i_mdio_rdata.value = answers["rdata"]
            dut.i_mdio_no_ack.value = answers["no_ack"]
            dut.i_mdio_done.value = 1
            await RisingEdge(dut.i_clk)
            dut.i_mdio_done.value = 0
            dut.i_mdio_busy.value = 0


async def begin(dut: Dut) -> tuple[dict[str, int], list[int]]:
    """Start the clock, the master model and the reset.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    tuple[dict[str, int], list[int]]
        The answers of the master and the list of its starts.
    """
    answers = {"rdata": 0, "no_ack": 0}
    starts: list[int] = []
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    for name in ("i_write", "i_address", "i_data_in", "i_sw_start"):
        getattr(dut, name).value = 0
    for name in (
        "i_mdio_busy",
        "i_mdio_done",
        "i_mdio_no_ack",
        "i_mdio_rdata",
    ):
        getattr(dut, name).value = 0
    cocotb.start_soon(master(dut, answers, starts))
    await reset_edges(dut, 2)
    return answers, starts


async def active(dut: Dut) -> int:
    """Return the speed code in use.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    int
        0 for 10, 1 for 100 and 2 for 1000 Mbit/s.
    """
    await RisingEdge(dut.i_clk)
    return int(dut.o_speed.value)


async def write_mode(dut: Dut, mode: int) -> None:
    """Write the SPEED register.

    Parameters
    ----------
    dut : Dut
        The design under test.
    mode : int
        Value of the mode field.
    """
    dut.i_address.value = reg.SPEED
    dut.i_data_in.value = mode
    dut.i_write.value = 1
    await RisingEdge(dut.i_clk)
    dut.i_write.value = 0
    await RisingEdge(dut.i_clk)


@cocotb.test()
async def test_reset_and_forced(dut: Dut) -> None:
    """Reset is automatic at 1000 Mbit/s; a forced mode wins."""
    await begin(dut)
    check_equal(await active(dut), 2)
    check_equal(int(dut.o_data_out.value), 2 << reg.SPEED_ACTIVE_SHIFT)
    for mode, code in ((1, 0), (2, 1), (3, 2)):
        await write_mode(dut, mode)
        check_equal(await active(dut), code)
        check_equal(int(dut.o_data_out.value) & reg.SPEED_MODE_MASK, mode)
    await write_mode(dut, 0)
    check_equal(await active(dut), 2)


@cocotb.test()
async def test_poll_learns(dut: Dut) -> None:
    """The poll reads register 17 and follows the speed."""
    answers, starts = await begin(dut)
    answers["rdata"] = STATUS_100 | reg.PHY_STATUS_DUPLEX
    for _ in range(4 * (POLL_CYCLES + MASTER_LATENCY + 4)):
        await RisingEdge(dut.i_clk)
    check_true(starts and set(starts) == {reg.PHY_STATUS_REG}, f"{starts}")
    check_equal(await active(dut), 1)
    word = int(dut.o_data_out.value)
    flags = reg.SPEED_LINK | reg.SPEED_FULL_DUPLEX | reg.SPEED_RESOLVED
    check_equal(word & flags, flags)
    answers["rdata"] = RESERVED
    for _ in range(4 * (POLL_CYCLES + MASTER_LATENCY + 4)):
        await RisingEdge(dut.i_clk)
    check_equal(await active(dut), 1)
    answers["rdata"] = STATUS_1000 & ~reg.PHY_STATUS_LINK
    for _ in range(4 * (POLL_CYCLES + MASTER_LATENCY + 4)):
        await RisingEdge(dut.i_clk)
    check_equal(await active(dut), 1)
    answers["rdata"] = STATUS_1000
    answers["no_ack"] = 1
    for _ in range(4 * (POLL_CYCLES + MASTER_LATENCY + 4)):
        await RisingEdge(dut.i_clk)
    check_equal(await active(dut), 1)
    answers["no_ack"] = 0
    for _ in range(4 * (POLL_CYCLES + MASTER_LATENCY + 4)):
        await RisingEdge(dut.i_clk)
    check_equal(await active(dut), 2)


@cocotb.test()
async def test_request_of_the_program_wins(dut: Dut) -> None:
    """With a request of the program the poll does not start."""
    _, starts = await begin(dut)
    dut.i_sw_start.value = 1
    for _ in range(6 * POLL_CYCLES):
        await RisingEdge(dut.i_clk)
    check_equal(starts, [])
    check_equal(int(dut.o_mdio_hold.value), 0)
    dut.i_sw_start.value = 0
    for _ in range(3 * POLL_CYCLES):
        await RisingEdge(dut.i_clk)
    check_true(len(starts) >= 1, "the poll never started")

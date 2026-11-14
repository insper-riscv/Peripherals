"""MDIO master alone: frames at the pins against a PHY model."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import reset_edges, start_and_wait_done
from tests.python.unittests.ETH.phy_mdio import (
    OPCODE_READ,
    OPCODE_WRITE,
    MdioPhy,
)

CLOCK_NS = 20
PHY = 3
REGISTER = 7


async def start(dut: Dut) -> None:
    """Start the clock and reset the master.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_start.value = 0
    dut.i_write.value = 0
    dut.i_phy_addr.value = 0
    dut.i_reg_addr.value = 0
    dut.i_wdata.value = 0
    dut.i_mdio.value = 1
    await reset_edges(dut, 4)


async def transact(
    dut: Dut, phy: int, register: int, value: int | None
) -> int:
    """Run one transaction and wait for its end.

    Parameters
    ----------
    dut : Dut
        The design under test.
    phy : int
        PHY address.
    register : int
        Register address.
    value : int | None
        Value to write, or None for a read.

    Returns
    -------
    int
        The data read, or the data written for a write.
    """
    dut.i_phy_addr.value = phy
    dut.i_reg_addr.value = register
    dut.i_write.value = int(value is not None)
    dut.i_wdata.value = value or 0
    await start_and_wait_done(dut)
    return int(dut.o_rdata.value)


@cocotb.test()
async def test_write_and_read(dut: Dut) -> None:
    """A write stores the value in the PHY and a read returns it."""
    await start(dut)
    phy = MdioPhy(dut, PHY, {})
    await transact(dut, PHY, REGISTER, 0xBEEF)
    check_equal(phy.regs[REGISTER], 0xBEEF)
    check_equal(await transact(dut, PHY, REGISTER, None), 0xBEEF)
    check_equal(
        phy.frames,
        [(OPCODE_WRITE, PHY, REGISTER), (OPCODE_READ, PHY, REGISTER)],
    )
    check_equal(int(dut.o_no_ack.value), 0)


@cocotb.test()
async def test_absent_phy(dut: Dut) -> None:
    """Nobody answers: the data is all ones and no-ack is raised."""
    await start(dut)
    MdioPhy(dut, PHY + 1, {REGISTER: 0x1234})
    check_equal(await transact(dut, PHY, REGISTER, None), 0xFFFF)
    check_equal(int(dut.o_no_ack.value), 1)
    check_equal(int(dut.o_busy.value), 0)
    check_equal(int(dut.o_mdio_oe.value), 0)


@cocotb.test()
async def test_ignored_start_when_busy(dut: Dut) -> None:
    """A start while a transaction runs does not restart it."""
    await start(dut)
    phy = MdioPhy(dut, PHY, {REGISTER: 0x4321})
    dut.i_phy_addr.value = PHY
    dut.i_reg_addr.value = REGISTER
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    for _ in range(40):
        await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    while not int(dut.o_done.value):
        await RisingEdge(dut.i_clk)
    check_equal(len(phy.frames), 1)

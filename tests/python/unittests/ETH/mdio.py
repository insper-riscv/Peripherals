"""MDIO master: Clause 22 reads and writes against a PHY model."""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.utils import get_sim_time

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH import driver
from tests.python.unittests.ETH import registers as reg
from tests.python.unittests.ETH.phy_mdio import (
    OPCODE_READ,
    OPCODE_WRITE,
    MdioPhy,
)
from tests.python.utils import bus

PHY_ADDRESS = 0x10
WRITE_BIT = 1 << 10
MDC_PERIOD_NS = 400
ID_REGISTER = 2
CONTROL_REGISTER = 0
ID_VALUE = 0x0141


def command(phy: int, register: int, *, write: bool) -> int:
    """Build the value of MDIO_CMD.

    Parameters
    ----------
    phy : int
        PHY address.
    register : int
        Register address in the PHY.
    write : bool
        True for a write, false for a read.

    Returns
    -------
    int
        The register value.
    """
    return register | (phy << 5) | (WRITE_BIT if write else 0)


async def wait_idle(dut: Dut) -> None:
    """Wait for the master to finish the transaction.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    await bus.cycles(dut, 4)
    await driver.wait_status(dut, reg.STATUS_MDIO_BUSY, 0)


@cocotb.test()
async def test_write(dut: Dut) -> None:
    """A write reaches the PHY register and raises the done flag."""
    await driver.start(dut)
    phy = MdioPhy(dut, PHY_ADDRESS, {})
    await bus.write(dut, reg.MDIO_DATA, 0xA5C3)
    await bus.write(
        dut, reg.MDIO_CMD, command(PHY_ADDRESS, CONTROL_REGISTER, write=True)
    )
    await wait_idle(dut)
    check_equal(phy.regs[CONTROL_REGISTER], 0xA5C3)
    check_equal(phy.frames, [(OPCODE_WRITE, PHY_ADDRESS, CONTROL_REGISTER)])
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_MDIO_DONE, 8)


@cocotb.test()
async def test_read(dut: Dut) -> None:
    """A read leaves the register of the PHY in MDIO_DATA."""
    await driver.start(dut)
    phy = MdioPhy(dut, PHY_ADDRESS, {ID_REGISTER: ID_VALUE})
    await bus.write(
        dut, reg.MDIO_CMD, command(PHY_ADDRESS, ID_REGISTER, write=False)
    )
    await wait_idle(dut)
    check_equal(await bus.read(dut, reg.MDIO_DATA), ID_VALUE)
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_MDIO_NOACK, 0)
    check_equal(phy.frames, [(OPCODE_READ, PHY_ADDRESS, ID_REGISTER)])


@cocotb.test()
async def test_read_every_value(dut: Dut) -> None:
    """Reads return the exact 16 bits, extreme patterns included."""
    await driver.start(dut)
    values = {1: 0x0000, 2: 0xFFFF, 3: 0x8001, 4: 0x7FFE, 5: 0x5555}
    MdioPhy(dut, PHY_ADDRESS, dict(values))
    for register, value in values.items():
        await bus.write(
            dut, reg.MDIO_CMD, command(PHY_ADDRESS, register, write=False)
        )
        await wait_idle(dut)
        check_equal(await bus.read(dut, reg.MDIO_DATA), value)


@cocotb.test()
async def test_no_phy(dut: Dut) -> None:
    """With no PHY at the address, the read ends with no-ack."""
    await driver.start(dut)
    MdioPhy(dut, PHY_ADDRESS + 1, {ID_REGISTER: ID_VALUE})
    await bus.write(
        dut, reg.MDIO_CMD, command(PHY_ADDRESS, ID_REGISTER, write=False)
    )
    await wait_idle(dut)
    check_equal(
        await bus.read(dut, reg.STATUS) & reg.STATUS_MDIO_NOACK,
        reg.STATUS_MDIO_NOACK,
    )


@cocotb.test()
async def test_mdc_period(dut: Dut) -> None:
    """MDC runs at 2.5 MHz in a transaction and is low after."""
    await driver.start(dut)
    MdioPhy(dut, PHY_ADDRESS, {ID_REGISTER: ID_VALUE})
    await bus.write(
        dut, reg.MDIO_CMD, command(PHY_ADDRESS, ID_REGISTER, write=False)
    )
    await RisingEdge(dut.o_mdc)
    first = get_sim_time("ns")
    await RisingEdge(dut.o_mdc)
    check_equal(int(get_sim_time("ns") - first), MDC_PERIOD_NS)
    await wait_idle(dut)
    await Timer(1, unit="us")
    check_equal(int(dut.o_mdc.value), 0)
    check_equal(int(dut.o_mdio_oe.value), 0)

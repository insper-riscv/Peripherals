"""Registers, interrupts, reset and PHY pins of the Ethernet MAC."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH import driver
from tests.python.unittests.ETH import registers as reg
from tests.python.utils import bus

MAC_WORD_LOW = 0x89ABCDEF
MAC_WORD_HIGH = 0x4567


@cocotb.test()
async def test_reset_values(dut: Dut) -> None:
    """After reset the MAC is disabled and every counter is zero."""
    await driver.start(dut)
    check_equal(await bus.read(dut, reg.CTRL), reg.CTRL_BROADCAST)
    check_equal(await bus.read(dut, reg.STATUS), 0)
    check_equal(await bus.read(dut, reg.IRQ_STATUS), 0)
    check_equal(await bus.read(dut, reg.RX_LEN), 0)
    for address in range(reg.CNT_TX, reg.CNT_FILTER + 1):
        check_equal(await bus.read(dut, address), 0)
    check_equal(int(dut.o_mii_tx_en.value), 0)
    check_equal(int(dut.o_mii_tx_er.value), 0)
    check_equal(int(dut.o_irq.value), 0)


@cocotb.test()
async def test_read_back(dut: Dut) -> None:
    """The writable registers read back what was written."""
    await driver.start(dut)
    await bus.write(dut, reg.MAC_LO, MAC_WORD_LOW)
    await bus.write(dut, reg.MAC_HI, MAC_WORD_HIGH)
    await bus.write(dut, reg.TX_LEN, 123)
    await bus.write(dut, reg.IRQ_ENABLE, 0x1F)
    check_equal(await bus.read(dut, reg.MAC_LO), MAC_WORD_LOW)
    check_equal(await bus.read(dut, reg.MAC_HI), MAC_WORD_HIGH)
    check_equal(await bus.read(dut, reg.TX_LEN), 123)
    check_equal(await bus.read(dut, reg.IRQ_ENABLE), 0x1F)
    check_equal(await bus.read(dut, 0x3F), 0)


@cocotb.test()
async def test_tx_irq_and_counter_clear(dut: Dut) -> None:
    """The transmit interrupt follows its enable bit."""
    await driver.start(dut)
    await driver.configure(dut)
    await bus.write(dut, reg.IRQ_ENABLE, reg.IRQ_TX_DONE)
    await driver.send_frame(dut, bytes(range(80)))
    await driver.wait_status(dut, reg.STATUS_TX_BUSY, 0)
    check_equal(int(dut.o_irq.value), 1)
    check_equal(await bus.read(dut, reg.CNT_TX), 1)
    await bus.write(dut, reg.CNT_TX, 0)
    check_equal(await bus.read(dut, reg.CNT_TX), 0)
    await bus.write(dut, reg.IRQ_STATUS, reg.IRQ_TX_DONE)
    check_equal(int(dut.o_irq.value), 0)


@cocotb.test()
async def test_phy_interrupt_and_reset(dut: Dut) -> None:
    """INT_N low raises the PHY interrupt; the bit drives RESET_N."""
    await driver.start(dut)
    check_equal(int(dut.o_phy_rst_n.value), 1)
    await bus.write(dut, reg.IRQ_ENABLE, reg.IRQ_PHY)
    dut.i_phy_int_n.value = 0
    await bus.cycles(dut, 5)
    check_equal(int(dut.o_irq.value), 1)
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_PHY_INT, 8)
    dut.i_phy_int_n.value = 1
    await bus.cycles(dut, 5)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, reg.CTRL, reg.CTRL_PHY_RESET)
    await bus.cycles(dut, 2)
    check_equal(int(dut.o_phy_rst_n.value), 0)
    await bus.write(dut, reg.CTRL, 0)
    await bus.cycles(dut, 2)
    check_equal(int(dut.o_phy_rst_n.value), 1)


@cocotb.test()
async def test_soft_reset(dut: Dut) -> None:
    """The soft reset returns every register to its reset value."""
    await driver.start(dut)
    await driver.configure(dut, reg.CTRL_ENABLE | reg.CTRL_PROMISCUOUS)
    await bus.write(dut, reg.CTRL, reg.CTRL_SOFT_RESET)
    await Timer(2, unit="us")
    await bus.cycles(dut, 5)
    check_equal(await bus.read(dut, reg.CTRL), reg.CTRL_BROADCAST)
    check_equal(await bus.read(dut, reg.MAC_LO), 0)

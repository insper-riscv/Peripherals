"""Register file alone: accesses, commands and counters."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut, Signal
from tests.python.unittests.ETH import registers as reg
from tests.python.unittests.ETH.driver import pulse
from tests.python.utils import bus

QUIET = (
    "i_tx_done",
    "i_rx_ready",
    "i_mdio_busy",
    "i_mdio_done",
    "i_mdio_no_ack",
    "i_phy_int",
    "i_ev_frame",
    "i_ev_crc",
    "i_ev_phy",
    "i_ev_dropped",
    "i_ev_filtered",
)


async def start(dut: Dut) -> None:
    """Reset the register file and quiet every input.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    for name in QUIET:
        getattr(dut, name).value = 0
    dut.i_rx_len.value = 0
    dut.i_rx_ram_data.value = 0
    dut.i_mdio_rdata.value = 0
    await bus.reset(dut)


async def pulse_input(dut: Dut, name: str) -> None:
    """Raise one input for exactly one clock edge.

    Parameters
    ----------
    dut : Dut
        The design under test.
    name : str
        Name of the input port.
    """
    getattr(dut, name).value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    getattr(dut, name).value = 0


@cocotb.test()
async def test_registers(dut: Dut) -> None:
    """Reset values, read-back, configuration and unused reads."""
    await start(dut)
    check_equal(await bus.read(dut, reg.CTRL), reg.CTRL_BROADCAST)
    await bus.write(dut, reg.CTRL, 0x5B)
    check_equal(await bus.read(dut, reg.CTRL), 0x5B)
    check_equal(
        (
            int(dut.o_enable.value),
            int(dut.o_promiscuous.value),
            int(dut.o_broadcast.value),
            int(dut.o_multicast.value),
            int(dut.o_accept_errors.value),
            int(dut.o_phy_reset.value),
        ),
        (1, 1, 0, 1, 1, 1),
    )
    await bus.write(dut, reg.MAC_LO, 0x12345678)
    await bus.write(dut, reg.MAC_HI, 0xFFFF9ABC)
    check_equal(int(dut.o_mac_addr.value), 0x9ABC12345678)
    check_equal(await bus.read(dut, reg.MAC_HI), 0x9ABC)
    check_equal(await bus.read(dut, 0x3F), 0)
    check_equal(await bus.read(dut, 0x0E), 0)


@cocotb.test()
async def test_transmit_commands(dut: Dut) -> None:
    """The buffer port, the start pulse, the refusals and the end."""
    await start(dut)
    for index, word in enumerate((0x11, 0x22, 0x33)):
        await bus.write(dut, reg.TX_DATA, word)
        check_equal(int(dut.o_tx_ram_we.value), 1)
        check_equal(int(dut.o_tx_ram_addr.value), index)
        check_equal(int(dut.o_tx_ram_data.value), word)
    check_equal(await bus.read(dut, reg.TX_DATA), 3)
    await bus.write(dut, reg.TX_CMD, reg.TX_START)
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_ERROR, 4)
    await bus.write(dut, reg.IRQ_STATUS, reg.IRQ_ERROR)
    await bus.write(dut, reg.TX_LEN, 12)
    check_equal(
        await count_pulses(dut, reg.TX_CMD, reg.TX_START, dut.o_tx_start), 1
    )
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_TX_BUSY, 1)
    await bus.write(dut, reg.TX_LEN, 99)
    check_equal(await bus.read(dut, reg.TX_LEN), 12)
    await bus.write(dut, reg.TX_CMD, reg.TX_START)
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_ERROR, 4)
    await pulse_input(dut, "i_tx_done")
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_TX_BUSY, 0)
    check_equal(await bus.read(dut, reg.CNT_TX), 1)
    check_equal(await bus.read(dut, reg.TX_DATA), 0)


@cocotb.test()
async def test_receive_port(dut: Dut) -> None:
    """RX_DATA walks the buffer, and the commands rewind and release."""
    await start(dut)
    dut.i_rx_ready.value = 1
    dut.i_rx_len.value = 100
    dut.i_rx_ram_data.value = 0xCAFE
    check_equal(await bus.read(dut, reg.RX_LEN), 100)
    check_equal(int(dut.o_rx_ram_addr.value), 0)
    check_equal(await bus.read(dut, reg.RX_DATA), 0xCAFE)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_rx_ram_addr.value), 1)
    await bus.read(dut, reg.RX_DATA)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_rx_ram_addr.value), 2)
    await bus.write(dut, reg.RX_CMD, reg.RX_REWIND)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_rx_ram_addr.value), 0)
    await bus.read(dut, reg.RX_DATA)
    check_equal(
        await count_pulses(dut, reg.RX_CMD, reg.RX_RELEASE, dut.o_rx_release),
        1,
    )
    check_equal(int(dut.o_rx_ram_addr.value), 0)


@cocotb.test()
async def test_mdio_registers(dut: Dut) -> None:
    """The command starts a transaction and a read leaves its data."""
    await start(dut)
    await bus.write(dut, reg.MDIO_DATA, 0x6789)
    command = (1 << 10) | (0x11 << 5) | 0x13
    await bus.write(dut, reg.MDIO_CMD, command)
    check_equal(int(dut.o_mdio_start.value), 1)
    check_equal(int(dut.o_mdio_write.value), 1)
    check_equal(int(dut.o_mdio_phy_addr.value), 0x11)
    check_equal(int(dut.o_mdio_reg_addr.value), 0x13)
    check_equal(int(dut.o_mdio_wdata.value), 0x6789)
    await bus.write(dut, reg.MDIO_CMD, (0x11 << 5) | 0x02)
    dut.i_mdio_rdata.value = 0x0141
    await pulse_input(dut, "i_mdio_done")
    check_equal(await bus.read(dut, reg.MDIO_DATA), 0x0141)
    check_equal(await bus.read(dut, reg.IRQ_STATUS) & reg.IRQ_MDIO_DONE, 8)
    dut.i_mdio_busy.value = 1
    await bus.write(dut, reg.MDIO_DATA, 0x1111)
    check_equal(await bus.read(dut, reg.MDIO_DATA), 0x0141)
    check_equal(await bus.read(dut, reg.STATUS) & reg.STATUS_MDIO_BUSY, 4)


@cocotb.test()
async def test_counters_and_interrupts(dut: Dut) -> None:
    """Events count, a write clears them, masks gate the interrupt."""
    await start(dut)
    for name, address in (
        ("i_ev_frame", reg.CNT_RX),
        ("i_ev_crc", reg.CNT_CRC),
        ("i_ev_phy", reg.CNT_PHY),
        ("i_ev_dropped", reg.CNT_DROP),
        ("i_ev_filtered", reg.CNT_FILTER),
    ):
        await pulse_input(dut, name)
        await pulse_input(dut, name)
        check_equal(await bus.read(dut, address), 2)
        await bus.write(dut, address, 0)
        check_equal(await bus.read(dut, address), 0)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, reg.IRQ_STATUS, 0xF)
    await bus.write(dut, reg.IRQ_ENABLE, reg.IRQ_RX_FRAME | reg.IRQ_PHY)
    await pulse_input(dut, "i_ev_crc")
    check_equal(int(dut.o_irq.value), 0)
    await pulse_input(dut, "i_ev_frame")
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, reg.IRQ_STATUS, 0xF)
    check_equal(int(dut.o_irq.value), 0)
    dut.i_phy_int.value = 1
    await bus.cycles(dut, 1)
    check_equal(int(dut.o_irq.value), 1)
    check_equal(int(dut.o_soft_reset.value), 0)
    await bus.write(dut, reg.CTRL, reg.CTRL_SOFT_RESET)
    check_equal(int(dut.o_soft_reset.value), 1)


async def count_pulses(
    dut: Dut, address: int, value: int, output: Signal
) -> int:
    """Write a register and count the cycles an output stays high.

    Parameters
    ----------
    dut : Dut
        The design under test.
    address : int
        Register address to write.
    value : int
        Value to write.
    output : Signal
        Output that pulses as a result of the write.

    Returns
    -------
    int
        Number of cycles with the output high in the three cycles after.
    """
    dut.i_address.value = address
    dut.i_data_in.value = value
    await pulse(dut.i_clk, dut.i_write)
    total = 0
    for _ in range(3):
        await Timer(1, unit="ns")
        total += int(output.value)
        await RisingEdge(dut.i_clk)
    return total

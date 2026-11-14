"""Clocks, reset and speed helpers of the RGMII Ethernet tests."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer

from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH import driver
from tests.python.unittests.ETH import registers as reg
from tests.python.unittests.ETH.rgmii_phy import (
    CLOCK_DELAY_NS,
    RgmiiPhy,
)
from tests.python.utils import bus

SYSTEM_NS = 20
TX_CLOCK_NS = 8
SETTLE_NS = 3000
MODE_OF_SPEED = {
    10: reg.SPEED_MODE_10,
    100: reg.SPEED_MODE_100,
    1000: reg.SPEED_MODE_1000,
}
CODE_OF_SPEED = {10: 0, 100: 1, 1000: 2}
IDLE_INPUTS = {
    name: driver.IDLE_INPUTS[name]
    for name in (
        "i_write",
        "i_read",
        "i_address",
        "i_data_in",
        "i_mdio",
        "i_phy_int_n",
    )
}


async def _delayed_clock(
    signal: object, period_ns: int, delay_ns: int
) -> None:
    """Run a clock that starts a delay after the others.

    Parameters
    ----------
    signal : object
        The clock signal.
    period_ns : int
        Period in nanoseconds.
    delay_ns : int
        Delay of the first edge in nanoseconds.
    """
    await Timer(delay_ns, unit="ns")
    await Clock(signal, period_ns, unit="ns").start()  # type: ignore[arg-type]


async def start(
    dut: Dut, speed: int = 1000, *, mac_delays_txc: bool = True
) -> RgmiiPhy:
    """Start the clocks and the PHY model and reset the design.

    Parameters
    ----------
    dut : Dut
        The design under test.
    speed : int
        Link speed of the PHY model in Mbit/s.
    mac_delays_txc : bool
        TXC clock shifted by 90 degrees, which centres it on the data;
        otherwise TXC is edge-aligned and the PHY delays it.

    Returns
    -------
    RgmiiPhy
        The PHY model.
    """
    cocotb.start_soon(Clock(dut.i_clk, SYSTEM_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.i_tx_clk, TX_CLOCK_NS, unit="ns").start())
    if mac_delays_txc:
        cocotb.start_soon(
            _delayed_clock(dut.i_tx_clk_dly, TX_CLOCK_NS, CLOCK_DELAY_NS)
        )
        sample_delay = 0
    else:
        cocotb.start_soon(
            Clock(dut.i_tx_clk_dly, TX_CLOCK_NS, unit="ns").start()
        )
        sample_delay = CLOCK_DELAY_NS
    for name, value in IDLE_INPUTS.items():
        getattr(dut, name).value = value
    phy = RgmiiPhy(dut, speed, sample_delay)
    dut.i_rst.value = 1
    await bus.cycles(dut, 4)
    dut.i_rst.value = 0
    await bus.cycles(dut, driver.RESET_WAIT)
    return phy


async def force_speed(dut: Dut, speed: int) -> None:
    """Force the speed of the MAC and let it reach the PHY clocks.

    Parameters
    ----------
    dut : Dut
        The design under test.
    speed : int
        Speed in Mbit/s.
    """
    await bus.write(dut, reg.SPEED, MODE_OF_SPEED[speed])
    await Timer(SETTLE_NS, unit="ns")


async def active_speed_code(dut: Dut) -> int:
    """Read the speed code the MAC uses.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    int
        0 for 10, 1 for 100 and 2 for 1000 Mbit/s.
    """
    word = await bus.read(dut, reg.SPEED)
    return (word >> reg.SPEED_ACTIVE_SHIFT) & reg.SPEED_ACTIVE_MASK

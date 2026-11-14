"""MAC with RGMII and TXC in phase with the data."""

import cocotb

from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.rgmii_mac import speed_case


@cocotb.test()
async def test_speed_1000(dut: Dut) -> None:
    """Frames in both directions at 1000 Mbit/s."""
    await speed_case(dut, 1000, mac_delays_txc=False)


@cocotb.test()
async def test_speed_100(dut: Dut) -> None:
    """Frames in both directions at 100 Mbit/s."""
    await speed_case(dut, 100, mac_delays_txc=False)

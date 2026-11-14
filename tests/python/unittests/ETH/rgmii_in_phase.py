"""RGMII layer with TXC in phase with the data."""

import cocotb

from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.rgmii import run_tx


@cocotb.test()
async def test_tx_1000(dut: Dut) -> None:
    """At 1000 Mbit/s the PHY delay centres the sample on the data."""
    await run_tx(dut, 1000, delayed_txc=False)


@cocotb.test()
async def test_tx_100(dut: Dut) -> None:
    """At 100 Mbit/s the PHY delay centres the sample on the data."""
    await run_tx(dut, 100, delayed_txc=False)


@cocotb.test()
async def test_tx_10(dut: Dut) -> None:
    """At 10 Mbit/s the PHY delay centres the sample on the data."""
    await run_tx(dut, 10, delayed_txc=False)

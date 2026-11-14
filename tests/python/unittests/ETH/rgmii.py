"""RGMII layer: GMII bytes to the pins and back, at the three speeds."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.model import fcs
from tests.python.unittests.ETH.rgmii_phy import (
    CLOCK_DELAY_NS,
    NIBBLE_BITS,
    NIBBLE_MASK,
    RgmiiPhy,
    wire_bytes,
)
from tests.python.utils.rng import seeded

TX_CLOCK_NS = 8
SPEED_CODE = {10: 0, 100: 1, 1000: 2}
PERIOD_CYCLES = {10: 50, 100: 5, 1000: 1}
FRAME_BYTES = 70


async def start(dut: Dut, speed: int, delayed_txc: bool) -> RgmiiPhy:
    """Start the clocks and the PHY model of the layer.

    Parameters
    ----------
    dut : Dut
        The design under test.
    speed : int
        Link speed in Mbit/s.
    delayed_txc : bool
        TXC comes from a clock shifted by 90 degrees.

    Returns
    -------
    RgmiiPhy
        The PHY model.
    """
    cocotb.start_soon(Clock(dut.i_tx_clk, TX_CLOCK_NS, unit="ns").start())
    if delayed_txc:
        cocotb.start_soon(shifted(dut))
    else:
        cocotb.start_soon(
            Clock(dut.i_tx_clk_dly, TX_CLOCK_NS, unit="ns").start()
        )
    dut.i_tx_speed.value = SPEED_CODE[speed]
    dut.i_gmii_txd.value = 0
    dut.i_gmii_tx_en.value = 0
    dut.i_gmii_tx_er.value = 0
    phy = RgmiiPhy(dut, speed, 0 if delayed_txc else CLOCK_DELAY_NS)
    await Timer(4 * TX_CLOCK_NS, unit="ns")
    return phy


async def shifted(dut: Dut) -> None:
    """Run the clock of TXC a quarter period after the clock of the MAC.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    await Timer(CLOCK_DELAY_NS, unit="ns")
    await Clock(dut.i_tx_clk_dly, TX_CLOCK_NS, unit="ns").start()


async def mac_model(dut: Dut, units: list[int]) -> None:
    """Play the transmitter: a new unit at each enable, then idle.

    Parameters
    ----------
    dut : Dut
        The design under test.
    units : list[int]
        Bytes (1000 Mbit/s) or nibbles to send, one per enable.
    """
    index = 0
    sent = 0
    while sent < len(units) + 2:
        await RisingEdge(dut.i_tx_clk)
        if int(dut.o_tx_ce.value):
            if index < len(units):
                dut.i_gmii_txd.value = units[index]
                dut.i_gmii_tx_en.value = 1
            else:
                dut.i_gmii_txd.value = 0
                dut.i_gmii_tx_en.value = 0
            index += 1
            sent += 1


def units_of(data: bytes, speed: int) -> list[int]:
    """Split the wire bytes into the units the transmitter sends.

    Parameters
    ----------
    data : bytes
        Bytes of the wire.
    speed : int
        Link speed in Mbit/s.

    Returns
    -------
    list[int]
        The bytes at 1000 Mbit/s, else the nibbles, low first.
    """
    if speed == 1000:  # noqa: PLR2004 - the gigabit speed
        return list(data)
    return [
        part
        for byte in data
        for part in (byte & NIBBLE_MASK, byte >> NIBBLE_BITS)
    ]


async def run_tx(dut: Dut, speed: int, *, delayed_txc: bool) -> None:
    """Send one frame through the layer and check the PHY side.

    Parameters
    ----------
    dut : Dut
        The design under test.
    speed : int
        Link speed in Mbit/s.
    delayed_txc : bool
        TXC comes from a clock shifted by 90 degrees.
    """
    phy = await start(dut, speed, delayed_txc)
    frame = seeded(speed).randbytes(FRAME_BYTES)
    units = units_of(wire_bytes(frame), speed)
    cocotb.start_soon(mac_model(dut, units))
    await Timer(
        (len(units) + 8) * TX_CLOCK_NS * PERIOD_CYCLES[speed], unit="ns"
    )
    check_equal(len(phy.tx.frames), 1)
    check_equal(phy.decode(0), frame + fcs(frame))
    periods = {
        later - earlier
        for earlier, later in zip(
            phy.tx.rise_times[2:], phy.tx.rise_times[3:], strict=False
        )
    }
    check_equal(periods, {TX_CLOCK_NS * PERIOD_CYCLES[speed]})
    highs = {
        fall - rise
        for rise, fall in zip(
            phy.tx.rise_times[2:], phy.tx.fall_times[2:], strict=False
        )
    }
    check_equal(highs, {TX_CLOCK_NS * PERIOD_CYCLES[speed] // 2})


@cocotb.test()
async def test_tx_1000(dut: Dut) -> None:
    """At 1000 Mbit/s a byte leaves in two nibbles."""
    await run_tx(dut, 1000, delayed_txc=True)


@cocotb.test()
async def test_tx_100(dut: Dut) -> None:
    """At 100 Mbit/s TXC is 25 MHz with half of the cycle high."""
    await run_tx(dut, 100, delayed_txc=True)


@cocotb.test()
async def test_tx_10(dut: Dut) -> None:
    """At 10 Mbit/s TXC is 2.5 MHz with half of the cycle high."""
    await run_tx(dut, 10, delayed_txc=True)


async def collect_rx(dut: Dut, rows: list[tuple[int, int, int]]) -> None:
    """Record RXD, RX_DV and RX_ER of the GMII at each RXC edge.

    Parameters
    ----------
    dut : Dut
        The design under test.
    rows : list[tuple[int, int, int]]
        Receives one row per edge where RX_DV or RX_ER is high.
    """
    while True:
        await RisingEdge(dut.i_rgmii_rxc)
        valid = int(dut.o_gmii_rx_dv.value)
        error = int(dut.o_gmii_rx_er.value)
        if valid or error:
            rows.append((int(dut.o_gmii_rxd.value), valid, error))


async def run_rx(dut: Dut, speed: int, error_at: int | None) -> None:
    """Send a frame from the PHY and check what the GMII shows.

    Parameters
    ----------
    dut : Dut
        The design under test.
    speed : int
        Link speed in Mbit/s.
    error_at : int | None
        Index of the cycle that carries RX_ER, if any.
    """
    phy = await start(dut, speed, delayed_txc=True)
    phy.fall_noise = speed != 1000  # noqa: PLR2004 - the gigabit speed
    rows: list[tuple[int, int, int]] = []
    cocotb.start_soon(collect_rx(dut, rows))
    data = wire_bytes(seeded(speed).randbytes(FRAME_BYTES))
    phy.send(data, error_at=error_at)
    await phy.drain()
    units = units_of(data, speed)
    mask = 0xFF if speed == 1000 else NIBBLE_MASK  # noqa: PLR2004
    check_equal([row[0] & mask for row in rows], units)
    check_equal({row[1] for row in rows}, {1})
    errors = [index for index, row in enumerate(rows) if row[2]]
    check_equal(errors, [] if error_at is None else [error_at])


@cocotb.test()
async def test_rx_1000(dut: Dut) -> None:
    """At 1000 Mbit/s a pair of nibbles is one GMII byte."""
    await run_rx(dut, 1000, None)


@cocotb.test()
async def test_rx_100(dut: Dut) -> None:
    """At 100 Mbit/s the other edge is ignored."""
    await run_rx(dut, 100, None)


@cocotb.test()
async def test_rx_10(dut: Dut) -> None:
    """At 10 Mbit/s the other edge is ignored."""
    await run_rx(dut, 10, None)


@cocotb.test()
async def test_rx_error(dut: Dut) -> None:
    """RX_ER is the xor of RX_CTL on the two edges."""
    await run_rx(dut, 1000, 20)

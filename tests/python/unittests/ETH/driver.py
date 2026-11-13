"""Clocks, reset and register helpers of the Ethernet tests."""

from itertools import batched

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.dut import Dut, Signal
from tests.python.unittests.ETH import registers as reg
from tests.python.utils import bus

SYSTEM_NS = 10
MII_100_NS = 40
MII_10_NS = 400
RESET_WAIT = 400
POLL_LIMIT = 40000
MAC_ADDRESS = bytes((0x02, 0x11, 0x22, 0x33, 0x44, 0x55))
WORD_BYTES = 4
IDLE_INPUTS = {
    "i_write": 0,
    "i_read": 0,
    "i_address": 0,
    "i_data_in": 0,
    "i_mii_rxd": 0,
    "i_mii_rx_dv": 0,
    "i_mii_rx_er": 0,
    "i_mdio": 1,
    "i_phy_int_n": 1,
}


async def start(
    dut: Dut, rx_ns: int = MII_100_NS, tx_ns: int = MII_100_NS
) -> None:
    """Start the three clocks, reset the design and release it.

    Parameters
    ----------
    dut : Dut
        The design under test.
    rx_ns : int
        Period of RX_CLK in nanoseconds.
    tx_ns : int
        Period of TX_CLK in nanoseconds.
    """
    start_clocks(
        (dut.i_clk, SYSTEM_NS),
        (dut.i_mii_rx_clk, rx_ns),
        (dut.i_mii_tx_clk, tx_ns),
    )
    for name, value in IDLE_INPUTS.items():
        getattr(dut, name).value = value
    dut.i_rst.value = 1
    await bus.cycles(dut, 4)
    dut.i_rst.value = 0
    await bus.cycles(dut, RESET_WAIT)


async def configure(dut: Dut, ctrl: int = reg.CTRL_ENABLE) -> None:
    """Program the MAC address and the control register.

    Parameters
    ----------
    dut : Dut
        The design under test.
    ctrl : int
        Value of the control register, with the enable bit by default.
    """
    low = int.from_bytes(MAC_ADDRESS[:4], "little")
    high = int.from_bytes(MAC_ADDRESS[4:], "little")
    await bus.write(dut, reg.MAC_LO, low)
    await bus.write(dut, reg.MAC_HI, high)
    await bus.write(dut, reg.CTRL, ctrl | reg.CTRL_BROADCAST)


def pack_words(data: bytes) -> list[int]:
    """Pack bytes into little-endian words, padding with zeros.

    Parameters
    ----------
    data : bytes
        Bytes to pack.

    Returns
    -------
    list[int]
        The 32-bit words, the first byte in the low bits.
    """
    padded = data + bytes(-len(data) % WORD_BYTES)
    return [
        int.from_bytes(bytes(chunk), "little")
        for chunk in batched(padded, WORD_BYTES, strict=True)
    ]


async def send_frame(dut: Dut, frame: bytes) -> None:
    """Fill the transmit buffer and start the transmission.

    Parameters
    ----------
    dut : Dut
        The design under test.
    frame : bytes
        Frame without FCS.
    """
    await bus.write(dut, reg.TX_CMD, reg.TX_RESET_POINTER)
    for word in pack_words(frame):
        await bus.write(dut, reg.TX_DATA, word)
    await bus.write(dut, reg.TX_LEN, len(frame))
    await bus.write(dut, reg.TX_CMD, reg.TX_START)


async def wait_status(dut: Dut, mask: int, want: int) -> None:
    """Poll STATUS until the masked bits equal the wanted value.

    Parameters
    ----------
    dut : Dut
        The design under test.
    mask : int
        Bits of STATUS to look at.
    want : int
        Value those bits must reach.

    Raises
    ------
    TimeoutError
        If the value is not reached within the polling limit.
    """
    for _ in range(POLL_LIMIT):
        if await bus.read(dut, reg.STATUS) & mask == want:
            return
    message = f"STATUS & {mask:#x} never became {want:#x}"
    raise TimeoutError(message)


async def read_frame(dut: Dut) -> bytes:
    """Read the ready frame through RX_DATA and release the buffer.

    Parameters
    ----------
    dut : Dut
        The design under test.

    Returns
    -------
    bytes
        The frame without FCS.
    """
    length = await bus.read(dut, reg.RX_LEN)
    data = bytearray()
    for _ in range((length + WORD_BYTES - 1) // WORD_BYTES):
        word = await bus.read(dut, reg.RX_DATA)
        data.extend(word.to_bytes(WORD_BYTES, "little"))
    await bus.write(dut, reg.RX_CMD, reg.RX_RELEASE)
    return bytes(data[:length])


async def settle(dut: Dut, microseconds: int) -> None:
    """Let the simulation run for a while.

    Parameters
    ----------
    dut : Dut
        The design under test.
    microseconds : int
        Time to run.
    """
    await Timer(microseconds, unit="us")
    await RisingEdge(dut.i_clk)


async def start_and_wait_done(dut: Dut) -> None:
    """Pulse i_start for one cycle and wait for the o_done pulse.

    Parameters
    ----------
    dut : Dut
        An entity with the start and done ports of a sequencer.
    """
    await pulse(dut.i_clk, dut.i_start)
    while True:
        await RisingEdge(dut.i_clk)
        if int(dut.o_done.value):
            break


async def pulse(clock: Signal, signal: Signal) -> None:
    """Raise a signal for exactly one edge of a clock.

    Parameters
    ----------
    clock : Signal
        Clock that times the pulse.
    signal : Signal
        Signal to raise and lower.
    """
    signal.value = 1
    await RisingEdge(clock)
    signal.value = 0


async def reset_edges(dut: Dut, edges: int) -> None:
    """Hold i_rst for some edges of i_clk and release it.

    Parameters
    ----------
    dut : Dut
        An entity with the i_clk and i_rst ports.
    edges : int
        Edges of i_clk with the reset raised.
    """
    dut.i_rst.value = 1
    for _ in range(edges):
        await RisingEdge(dut.i_clk)
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)


def start_clocks(*clocks: tuple[Signal, int]) -> None:
    """Start free-running clocks.

    Parameters
    ----------
    *clocks : tuple[Signal, int]
        Each clock signal with its period in nanoseconds.
    """
    for signal, period in clocks:
        cocotb.start_soon(Clock(signal, period, unit="ns").start())


async def hold(clock: Signal, signals: list[Signal], edges: int) -> None:
    """Hold signals high for some edges of a clock, then lower them.

    Parameters
    ----------
    clock : Signal
        Clock that times the hold.
    signals : list[Signal]
        Signals to raise and lower together.
    edges : int
        Edges of the clock with the signals high.
    """
    for signal in signals:
        signal.value = 1
    for _ in range(edges):
        await RisingEdge(clock)
    for signal in signals:
        signal.value = 0

"""Test model of the ps2_host byte interface, seen by the mouse."""

from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.PS2.mouse.registers import (
    CMD_ENABLE,
    CMD_RESET,
    RSP_ACK,
    RSP_ID,
    RSP_SELF_TEST,
)
from tests.python.utils import bus
from tests.python.utils.dut import ByteHostDut

MAX_WAIT = 400


async def send_byte(dut: ByteHostDut, value: int) -> None:
    """Deliver one received byte to the mouse, as a one-cycle pulse.

    Parameters
    ----------
    dut : ByteHostDut
        The design under test.
    value : int
        The byte the device sent.
    """
    dut.i_rx_data.value = value
    dut.i_rx_valid.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rx_valid.value = 0


async def send_rx_error(dut: ByteHostDut) -> None:
    """Deliver a one-cycle framing or parity error.

    Parameters
    ----------
    dut : ByteHostDut
        The design under test.
    """
    dut.i_rx_error.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rx_error.value = 0


async def expect_tx(dut: ByteHostDut, value: int) -> None:
    """Wait for the mouse to send a byte and check it.

    The transmitter is ready only while waiting, so the byte goes out
    in the first cycle it is asked for, and the request lasts one cycle.

    Parameters
    ----------
    dut : ByteHostDut
        The design under test.
    value : int
        The byte the mouse must send.

    Raises
    ------
    AssertionError
        If the byte does not come in time or is not the expected one.
    """
    dut.i_tx_ready.value = 1
    await Timer(1, unit="ns")
    for _ in range(MAX_WAIT):
        if int(dut.o_tx_valid.value) == 1:
            got = int(dut.o_tx_data.value)
            if got != value:
                raise AssertionError(f"sent {got:#x}, want {value:#x}")
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            if int(dut.o_tx_valid.value) != 0:
                raise AssertionError("tx_valid lasted more than a cycle")
            dut.i_tx_ready.value = 0
            return
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    raise AssertionError(f"byte {value:#x} was never sent")


async def initialize(dut: ByteHostDut) -> None:
    """Run the whole initialization handshake of a mouse.

    Parameters
    ----------
    dut : ByteHostDut
        The design under test.
    """
    await expect_tx(dut, CMD_RESET)
    for response in (RSP_ACK, RSP_SELF_TEST, RSP_ID):
        await send_byte(dut, response)
    await expect_tx(dut, CMD_ENABLE)
    await send_byte(dut, RSP_ACK)


async def send_packet(
    dut: ByteHostDut, dx: int, dy: int, buttons: int = 0, overflow: int = 0
) -> None:
    """Send one 3-byte movement packet.

    Parameters
    ----------
    dut : ByteHostDut
        The design under test.
    dx : int
        Signed X displacement, from -256 to 255.
    dy : int
        Signed Y displacement, from -256 to 255.
    buttons : int
        Bit 0 left, bit 1 right, bit 2 middle.
    overflow : int
        Bit 0 X overflow, bit 1 Y overflow.
    """
    first = 0x08 | buttons
    first |= ((dx >> 8) & 1) << 4
    first |= ((dy >> 8) & 1) << 5
    first |= (overflow & 3) << 6
    for value in (first, dx & 0xFF, dy & 0xFF):
        await send_byte(dut, value)


async def reset_idle(dut: ByteHostDut) -> None:
    """Reset the design with the byte interface idle and the host busy.

    Parameters
    ----------
    dut : ByteHostDut
        The design under test.
    """
    dut.i_rx_data.value = 0
    dut.i_rx_valid.value = 0
    dut.i_rx_error.value = 0
    dut.i_tx_ready.value = 0
    await bus.hold_reset(dut)

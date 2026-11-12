"""PS2_MOUSE_DECODER: initialization and packets, byte by byte."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.PS2.mouse.host_model import (
    expect_tx,
    initialize,
    reset_idle,
    send_byte,
    send_packet,
    send_rx_error,
)
from tests.python.unittests.PS2.mouse.registers import CMD_RESET, INIT_TIMEOUT
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MouseDecoderDut

DELTA_MASK = 0x1FF
BUTTONS_LEFT_MIDDLE = 0b101
DX_VALUE = 37
DY_VALUE = -90
MAX_DELTA = 255
MIN_DELTA = -256


async def start(dut: MouseDecoderDut) -> None:
    """Reset the decoder with idle inputs.

    Parameters
    ----------
    dut : MouseDecoderDut
        The design under test.
    """
    dut.i_restart.value = 0
    await reset_idle(dut)


async def packet_pulse(dut: MouseDecoderDut) -> int:
    """Count the cycles the packet pulse stays high from now.

    Parameters
    ----------
    dut : MouseDecoderDut
        The design under test.

    Returns
    -------
    int
        How many consecutive cycles the pulse stayed high.
    """
    width = int(dut.o_packet_valid.value)
    for _ in range(3):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        width += int(dut.o_packet_valid.value)
    return width


def signed9(value: int) -> int:
    """Interpret a 9-bit displacement as a signed number.

    Parameters
    ----------
    value : int
        The raw 9-bit value.

    Returns
    -------
    int
        The signed value.
    """
    return value - (1 << 9) if value & (1 << 8) else value


@cocotb.test()
async def test_streaming_flag(dut: MouseDecoderDut) -> None:
    """The streaming output rises only after the whole handshake."""
    await start(dut)
    check(int(dut.o_streaming.value) == 0)
    await initialize(dut)
    await bus.cycles(dut, 1)
    check(int(dut.o_streaming.value) == 1)
    dut.i_restart.value = 1
    await bus.cycles(dut, 1)
    dut.i_restart.value = 0
    check(int(dut.o_streaming.value) == 0)
    await expect_tx(dut, CMD_RESET)


@cocotb.test()
async def test_packet_fields(dut: MouseDecoderDut) -> None:
    """A packet gives one pulse and stable buttons and displacements."""
    await start(dut)
    await initialize(dut)
    await send_packet(dut, DX_VALUE, DY_VALUE, buttons=BUTTONS_LEFT_MIDDLE)
    check_equal(await packet_pulse(dut), 1)
    check_equal(int(dut.o_buttons.value), BUTTONS_LEFT_MIDDLE)
    check_equal(signed9(int(dut.o_dx.value)), DX_VALUE)
    check_equal(signed9(int(dut.o_dy.value)), DY_VALUE)
    check(int(dut.o_overflow.value) == 0)


@cocotb.test()
async def test_overflow_clips(dut: MouseDecoderDut) -> None:
    """An overflow bit clips that axis at the limit of its sign."""
    await start(dut)
    await initialize(dut)
    await send_packet(dut, 1, -1, overflow=0b11)
    await packet_pulse(dut)
    check_equal(signed9(int(dut.o_dx.value)), MAX_DELTA)
    check_equal(signed9(int(dut.o_dy.value)), MIN_DELTA)
    check(int(dut.o_overflow.value) == 1)


@cocotb.test()
async def test_error_pulses(dut: MouseDecoderDut) -> None:
    """A bad first byte and a framing error give one pulse each."""
    await start(dut)
    await initialize(dut)
    pulses = 0
    await send_byte(dut, 0x00)
    pulses += int(dut.o_error.value)
    await send_rx_error(dut)
    pulses += int(dut.o_error.value)
    await bus.cycles(dut, 2)
    check_equal(pulses, 2)
    check(int(dut.o_error.value) == 0)


@cocotb.test()
async def test_init_silence_restarts(dut: MouseDecoderDut) -> None:
    """Silence after the reset command sends the reset command again."""
    await start(dut)
    await expect_tx(dut, CMD_RESET)
    await bus.cycles(dut, INIT_TIMEOUT + 10)
    await expect_tx(dut, CMD_RESET)

"""Sequencer of the MAX 10 ADC peripheral, driven as the core would.

The test plays the ready and the response by hand.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import Max10AdcSequencerDut

MASK = (1 << 2) | (1 << 7) | (1 << 17)
SINGLE = 5
SINGLE_DATA = 0xABC
SECOND = 6
SETTLE_NS = 1


async def _start(dut: Max10AdcSequencerDut) -> None:
    """Start the clock, reset the design and quiet the core inputs.

    Parameters
    ----------
    dut : Max10AdcSequencerDut
        The design under test.
    """
    dut.i_start.value = 0
    dut.i_mask.value = 0
    dut.i_cmd_ready.value = 0
    dut.i_rsp_valid.value = 0
    dut.i_rsp_channel.value = 0
    dut.i_rsp_data.value = 0
    await bus.hold_reset(dut)
    await RisingEdge(dut.i_clk)
    await Timer(SETTLE_NS, unit="ns")


async def _tick(dut: Max10AdcSequencerDut) -> None:
    """Wait for one clock edge and let the signals settle.

    Parameters
    ----------
    dut : Max10AdcSequencerDut
        The design under test.
    """
    await RisingEdge(dut.i_clk)
    await Timer(SETTLE_NS, unit="ns")


async def _begin(dut: Max10AdcSequencerDut, mask: int) -> None:
    """Pulse the start request with a mask.

    Parameters
    ----------
    dut : Max10AdcSequencerDut
        The design under test.
    mask : int
        Channels of the scan.
    """
    dut.i_mask.value = mask
    dut.i_start.value = 1
    await _tick(dut)
    dut.i_start.value = 0


async def _wait_command(dut: Max10AdcSequencerDut) -> int:
    """Wait for the command to be valid and return its channel.

    Parameters
    ----------
    dut : Max10AdcSequencerDut
        The design under test.

    Returns
    -------
    int
        The channel of the command.

    Raises
    ------
    TimeoutError
        If no command appears.
    """
    for _ in range(8):
        if int(dut.o_cmd_valid.value):
            return int(dut.o_cmd_channel.value)
        await _tick(dut)
    raise TimeoutError("no command")


async def _wait_idle(dut: Max10AdcSequencerDut) -> None:
    """Wait until the sequencer is free.

    Parameters
    ----------
    dut : Max10AdcSequencerDut
        The design under test.

    Raises
    ------
    TimeoutError
        If the sequencer stays busy.
    """
    for _ in range(6):
        if not int(dut.o_busy.value):
            return
        await _tick(dut)
    raise TimeoutError("the sequencer stayed busy")


async def _complete(
    dut: Max10AdcSequencerDut, channel: int, data: int, together: bool
) -> None:
    """Give the ready and the response of a command.

    Parameters
    ----------
    dut : Max10AdcSequencerDut
        The design under test.
    channel : int
        Channel the response carries.
    data : int
        Sample of the response.
    together : bool
        The response comes with the ready, otherwise one cycle after.
    """
    dut.i_cmd_ready.value = 1
    dut.i_rsp_channel.value = channel
    dut.i_rsp_data.value = data
    dut.i_rsp_valid.value = 1 if together else 0
    await _tick(dut)
    dut.i_cmd_ready.value = 0
    if not together:
        dut.i_rsp_valid.value = 1
        await _tick(dut)
    dut.i_rsp_valid.value = 0


@cocotb.test()
async def test_idle_after_reset(dut: Max10AdcSequencerDut) -> None:
    """After the reset nothing is busy, valid or done."""
    await _start(dut)
    check(not int(dut.o_busy.value) and not int(dut.o_cmd_valid.value))
    check(not int(dut.o_done.value) and not int(dut.o_sample_valid.value))


@cocotb.test()
async def test_channels_in_order_with_packet_marks(
    dut: Max10AdcSequencerDut,
) -> None:
    """The channels come lowest first, with sop and eop marks."""
    await _start(dut)
    await _begin(dut, MASK)
    seen: list[tuple[int, int, int]] = []
    for channel in (2, 7, 17):
        got = await _wait_command(dut)
        check(got == channel, f"wanted {channel}, got {got}")
        seen.append((got, int(dut.o_cmd_sop.value), int(dut.o_cmd_eop.value)))
        await _complete(dut, channel, 0x100 + channel, together=True)
    check(seen == [(2, 1, 0), (7, 0, 0), (17, 0, 1)], f"{seen}")
    await _wait_idle(dut)


@cocotb.test()
async def test_sample_pulse_carries_the_response(
    dut: Max10AdcSequencerDut,
) -> None:
    """The sample output is a pulse with the channel and the data."""
    await _start(dut)
    await _begin(dut, 1 << SINGLE)
    await _wait_command(dut)
    dut.i_cmd_ready.value = 1
    dut.i_rsp_channel.value = SINGLE
    dut.i_rsp_data.value = SINGLE_DATA
    dut.i_rsp_valid.value = 1
    await Timer(SETTLE_NS, unit="ns")
    check(int(dut.o_sample_valid.value) == 1)
    check(int(dut.o_sample_channel.value) == SINGLE)
    check(int(dut.o_sample_data.value) == SINGLE_DATA)
    await _tick(dut)
    dut.i_cmd_ready.value = 0
    dut.i_rsp_valid.value = 0
    await Timer(SETTLE_NS, unit="ns")
    check(int(dut.o_sample_valid.value) == 0, "one cycle only")


@cocotb.test()
async def test_response_after_ready(dut: Max10AdcSequencerDut) -> None:
    """A response one cycle after the ready is still taken."""
    await _start(dut)
    await _begin(dut, 1 << 4)
    await _wait_command(dut)
    await _complete(dut, 4, 0x321, together=False)
    await _wait_idle(dut)


@cocotb.test()
async def test_wrong_channel_response_is_ignored(
    dut: Max10AdcSequencerDut,
) -> None:
    """A response for another channel does not end the command."""
    await _start(dut)
    await _begin(dut, 1 << 4)
    await _wait_command(dut)
    await _complete(dut, 9, 0x111, together=True)
    check(int(dut.o_busy.value) == 1, "still waiting")
    dut.i_rsp_channel.value = 4
    dut.i_rsp_valid.value = 1
    await _tick(dut)
    dut.i_rsp_valid.value = 0
    await _wait_idle(dut)


@cocotb.test()
async def test_response_before_ready_is_ignored(
    dut: Max10AdcSequencerDut,
) -> None:
    """A response with no accepted command is not a sample."""
    await _start(dut)
    await _begin(dut, 1 << 4)
    await _wait_command(dut)
    dut.i_rsp_channel.value = 4
    dut.i_rsp_valid.value = 1
    await Timer(SETTLE_NS, unit="ns")
    check(int(dut.o_sample_valid.value) == 0)
    await _tick(dut)
    dut.i_rsp_valid.value = 0
    check(int(dut.o_cmd_valid.value) == 1, "the command is held")


@cocotb.test()
async def test_start_while_busy_and_mask_latched(
    dut: Max10AdcSequencerDut,
) -> None:
    """A start during a scan is ignored, and the mask is taken once."""
    await _start(dut)
    await _begin(dut, (1 << 1) | (1 << 6))
    await _wait_command(dut)
    await _begin(dut, 1 << 9)
    check(int(dut.o_cmd_channel.value) == 1)
    await _complete(dut, 1, 1, together=True)
    got = await _wait_command(dut)
    check(got == SECOND, "the second scan did not replace the mask")
    await _complete(dut, SECOND, 2, together=True)
    await _wait_idle(dut)


@cocotb.test()
async def test_empty_mask(dut: Max10AdcSequencerDut) -> None:
    """An empty mask ends in a done pulse with no command."""
    await _start(dut)
    await _begin(dut, 0)
    done = 0
    for _ in range(4):
        check(not int(dut.o_cmd_valid.value))
        done += int(dut.o_done.value)
        await _tick(dut)
    check(done == 1, "one done pulse")
    check(int(dut.o_busy.value) == 0)

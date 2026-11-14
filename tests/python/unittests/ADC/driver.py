"""Helpers of the MAX 10 ADC tests.

The analog inputs, the command log and the software sequences the C
example of the document performs.
"""

from dataclasses import dataclass, field

import cocotb
from cocotb.triggers import FallingEdge

from tests.python.unittests.ADC.registers import (
    BUSY,
    CHANNEL_BASE,
    CTRL,
    DONE,
    ENABLE,
    MASK,
    START,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.dut import Max10AdcDut

SAMPLE_BITS = 12
POLL_LIMIT = 4000


@dataclass(frozen=True)
class Command:
    """One command the peripheral gave the core.

    Attributes
    ----------
    cycle : int
        Clock cycle of the handshake, counted from the log start.
    channel : int
        Channel number of the command.
    sop : bool
        The command opened the scan.
    eop : bool
        The command closed the scan.
    """

    cycle: int
    channel: int
    sop: bool
    eop: bool


@dataclass
class CommandLog:
    """The commands the core accepted, in order.

    Attributes
    ----------
    commands : list[Command]
        Accepted commands.
    """

    commands: list[Command] = field(default_factory=list[Command])

    def channels(self) -> list[int]:
        """Return the channels of the accepted commands.

        Returns
        -------
        list[int]
            Channel numbers in the order of acceptance.
        """
        return [command.channel for command in self.commands]


def pack(values: dict[int, int]) -> int:
    """Pack channel values into the analog input vector.

    Parameters
    ----------
    values : dict[int, int]
        Value of each channel by number; the missing ones are zero.

    Returns
    -------
    int
        The vector, 12 bits per channel, channel 0 lowest.
    """
    word = 0
    for channel, value in values.items():
        word |= (value & ((1 << SAMPLE_BITS) - 1)) << (channel * SAMPLE_BITS)
    return word


async def _watch(dut: Max10AdcDut, log: CommandLog) -> None:
    """Record every handshake of the command interface.

    Parameters
    ----------
    dut : Max10AdcDut
        The design under test.
    log : CommandLog
        Where the commands go.
    """
    cycle = 0
    while True:
        await FallingEdge(dut.i_clk)
        cycle += 1
        if int(dut.o_cmd_valid.value) and int(dut.o_cmd_ready.value):
            log.commands.append(
                Command(
                    cycle,
                    int(dut.o_cmd_channel.value),
                    bool(int(dut.o_cmd_sop.value)),
                    bool(int(dut.o_cmd_eop.value)),
                )
            )


async def start(
    dut: Max10AdcDut, analog: dict[int, int] | None = None
) -> CommandLog:
    """Set the analog inputs, reset the design and log the commands.

    Parameters
    ----------
    dut : Max10AdcDut
        The design under test.
    analog : dict[int, int] | None
        Value of each channel by number.

    Returns
    -------
    CommandLog
        The log the monitor fills from now on.
    """
    dut.i_analog.value = pack(analog or {})
    await bus.reset(dut)
    log = CommandLog()
    cocotb.start_soon(_watch(dut, log))
    return log


async def wait_done(dut: Max10AdcDut) -> int:
    """Poll the status until the scan ends.

    Parameters
    ----------
    dut : Max10AdcDut
        The design under test.

    Returns
    -------
    int
        The status word read when the busy bit was clear.

    Raises
    ------
    TimeoutError
        If the scan does not end in time.
    """
    for _ in range(POLL_LIMIT):
        status = await bus.read(dut, STATUS)
        if not status & BUSY:
            return status
    raise TimeoutError("the ADC scan did not end")


async def scan(dut: Max10AdcDut, mask: int) -> int:
    """Run one scan: set the mask, start it and wait for the end.

    Parameters
    ----------
    dut : Max10AdcDut
        The design under test.
    mask : int
        Channels of the scan.

    Returns
    -------
    int
        The status word at the end of the scan.
    """
    await bus.write(dut, MASK, mask)
    await bus.write(dut, CTRL, ENABLE)
    await bus.write(dut, CTRL, ENABLE | START)
    status = await wait_done(dut)
    check_done = status & DONE
    if not check_done:
        raise AssertionError("the scan ended without the done flag")
    return status


async def read_channel(dut: Max10AdcDut, channel: int) -> int:
    """Read the result register of a channel.

    Parameters
    ----------
    dut : Max10AdcDut
        The design under test.
    channel : int
        Channel number.

    Returns
    -------
    int
        The register: sample, valid and overrun flags.
    """
    return await bus.read(dut, CHANNEL_BASE + channel)

"""Line state machine of the I2C master with the lines wired by hand."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import I2cCoreDut

START, STOP, READ, WRITE = 1, 2, 4, 8
LIMIT = 2000
COMMANDS = 2
IDLE_INPUTS = {
    "i_abort": 0,
    "i_cmd_valid": 0,
    "i_cmd_start": 0,
    "i_cmd_stop": 0,
    "i_cmd_read": 0,
    "i_cmd_write": 0,
    "i_cmd_nack": 0,
    "i_tx_data": 0,
    "i_enable": 1,
    "i_divider": 3,
    "i_scl": 1,
    "i_sda": 1,
}


class Lines:
    """The wired-AND bus seen by the core, with two external drivers.

    Attributes
    ----------
    sda_low : bool
        An external device holds SDA low.
    scl_low : bool
        An external device holds SCL low (clock stretching).
    pulses : dict[str, int]
        Cycles in which each one-cycle output was seen high.
    """

    def __init__(self, dut: I2cCoreDut) -> None:
        """Start following the outputs of the core.

        Parameters
        ----------
        dut : I2cCoreDut
            The design under test.
        """
        self.dut = dut
        self.sda_low = False
        self.scl_low = False
        self.pulses = {"done": 0, "nack": 0, "arb": 0}
        cocotb.start_soon(self._run())

    async def _run(self) -> None:
        """Drive the input lines from the outputs once per cycle."""
        while True:
            await RisingEdge(self.dut.i_clk)
            await Timer(1, unit="ns")
            dut = self.dut
            scl = not (int(dut.o_scl_low.value) or self.scl_low)
            sda = not (int(dut.o_sda_low.value) or self.sda_low)
            dut.i_scl.value = int(scl)
            dut.i_sda.value = int(sda)
            self.pulses["done"] += int(dut.o_done.value)
            self.pulses["nack"] += int(dut.o_nack.value)
            self.pulses["arb"] += int(dut.o_arb_lost.value)


async def setup(dut: I2cCoreDut) -> Lines:
    """Reset the core, enable it and wire the lines.

    Parameters
    ----------
    dut : I2cCoreDut
        The design under test.

    Returns
    -------
    Lines
        The model of the bus.
    """
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    for name, value in IDLE_INPUTS.items():
        getattr(dut, name).value = value
    await bus.hold_reset(dut)
    return Lines(dut)


async def run(dut: I2cCoreDut, flags: int, tx: int = 0) -> None:
    """Load a command and wait for the busy output to fall.

    Parameters
    ----------
    dut : I2cCoreDut
        The design under test.
    flags : int
        START, STOP, READ and WRITE bits of the command.
    tx : int
        Byte to send.

    Raises
    ------
    TimeoutError
        If the core stays busy.
    """
    dut.i_cmd_start.value = flags & START
    dut.i_cmd_stop.value = (flags & STOP) >> 1
    dut.i_cmd_read.value = (flags & READ) >> 2
    dut.i_cmd_write.value = (flags & WRITE) >> 3
    dut.i_tx_data.value = tx
    dut.i_cmd_valid.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_cmd_valid.value = 0
    for _ in range(LIMIT):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if not int(dut.o_busy.value):
            return
    raise TimeoutError("the core stayed busy")


@cocotb.test()
async def test_idle_lines_are_released(dut: I2cCoreDut) -> None:
    """After reset the core is idle and pulls no line."""
    await setup(dut)
    check(int(dut.o_busy.value) == 0 and int(dut.o_bus_active.value) == 0)
    check(int(dut.o_scl_low.value) == 0 and int(dut.o_sda_low.value) == 0)


@cocotb.test()
async def test_start_then_stop(dut: I2cCoreDut) -> None:
    """A start holds SCL low afterwards and a stop frees both lines."""
    lines = await setup(dut)
    await run(dut, START)
    check(int(dut.o_bus_active.value) == 1)
    check(int(dut.o_scl_low.value) == 1 and int(dut.o_sda_low.value) == 1)
    await run(dut, STOP)
    check(int(dut.o_bus_active.value) == 0)
    check(int(dut.o_scl_low.value) == 0 and int(dut.o_sda_low.value) == 0)
    await bus.cycles(dut, 2)
    check(lines.pulses["done"] == COMMANDS and lines.pulses["arb"] == 0)


@cocotb.test()
async def test_ack_and_nack_of_a_sent_byte(dut: I2cCoreDut) -> None:
    """A slave holding SDA low in the ACK bit acknowledges the byte."""
    lines = await setup(dut)
    await run(dut, START | WRITE, 0x00)
    check(lines.pulses["nack"] == 1, "nobody answers: NACK")
    lines.sda_low = True
    await run(dut, WRITE, 0x00)
    check(lines.pulses["nack"] == 1, "SDA held low: ACK")
    lines.sda_low = False
    await run(dut, STOP)


@cocotb.test()
async def test_losing_arbitration_releases_the_lines(dut: I2cCoreDut) -> None:
    """Sending a 1 while another device holds SDA low loses the bus."""
    lines = await setup(dut)
    await run(dut, START)
    lines.sda_low = True
    await run(dut, WRITE, 0xFF)
    await bus.cycles(dut, 2)
    check(lines.pulses["arb"] == 1)
    check(int(dut.o_bus_active.value) == 0)
    check(int(dut.o_scl_low.value) == 0 and int(dut.o_sda_low.value) == 0)


@cocotb.test()
async def test_clock_stretching_pauses_the_command(dut: I2cCoreDut) -> None:
    """The core waits while a slave holds SCL low, then goes on."""
    lines = await setup(dut)
    await run(dut, START)
    lines.scl_low = True
    dut.i_tx_data.value = 0x55
    dut.i_cmd_write.value = 1
    dut.i_cmd_start.value = 0
    dut.i_cmd_stop.value = 0
    dut.i_cmd_valid.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_cmd_valid.value = 0
    await bus.cycles(dut, 300)
    check(int(dut.o_busy.value) == 1, "still waiting")
    check(int(dut.o_scl_low.value) == 0, "SCL released and held by the slave")
    lines.scl_low = False
    await bus.cycles(dut, 400)
    check(int(dut.o_busy.value) == 0)


@cocotb.test()
async def test_abort_and_disable_release_everything(dut: I2cCoreDut) -> None:
    """The abort input and the enable input free the lines at once."""
    await setup(dut)
    await run(dut, START)
    dut.i_abort.value = 1
    await bus.cycles(dut, 1)
    dut.i_abort.value = 0
    check(int(dut.o_bus_active.value) == 0)
    check(int(dut.o_scl_low.value) == 0 and int(dut.o_sda_low.value) == 0)
    await run(dut, START)
    dut.i_enable.value = 0
    await bus.cycles(dut, 1)
    check(int(dut.o_scl_low.value) == 0 and int(dut.o_sda_low.value) == 0)

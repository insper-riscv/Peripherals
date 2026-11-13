"""Infrared receiver: NEC frames, repeats, noise, raw widths, IRQ."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.IR import nec
from tests.python.unittests.IR.registers import (
    CTRL,
    CTRL_DEFAULT,
    CTRL_EN,
    CTRL_FLUSH,
    CTRL_FRAME_IE,
    DATA,
    FRAME_EXT,
    FRAME_REPEAT,
    RAW_MARK,
    RAW_SPACE,
    STAT_FRAME_ERR,
    STAT_LEVEL_SHIFT,
    STAT_NOT_EMPTY,
    STAT_RAW_NEW,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import IrDut
from tests.python.utils.rng import seeded

PERIOD_NS = 1000
GAP_US = 20000.0
SETTLE = 100
WIDTH_TOL = 3


def eq(actual: int, expected: int, message: str = "") -> None:
    """Fail the running test if two values differ.

    Parameters
    ----------
    actual : int
        The value observed.
    expected : int
        The value that was due.
    message : str
        Text of the failure.
    """
    try:
        check_equal(actual, expected)
    except AssertionError as error:
        raise AssertionError(f"{message}: {error}") from error


async def start(dut: IrDut, ctrl: int = CTRL_DEFAULT) -> None:
    """Reset the design, idle the pin and enable the receiver.

    Parameters
    ----------
    dut : IrDut
        The design under test.
    ctrl : int
        Value written to the control register.
    """
    dut.i_irda_rxd.value = 1
    await bus.reset(dut, period_ns=PERIOD_NS)
    await bus.write(dut, CTRL, ctrl)
    await bus.cycles(dut, 10)


def word(address: int, command: int, flags: int = 0) -> int:
    """Pack a frame as the data register shows it.

    Parameters
    ----------
    address : int
        Address of 16 bits.
    command : int
        Command of 8 bits.
    flags : int
        Repeat and extended bits.

    Returns
    -------
    int
        The data register value.
    """
    return address | (command << 16) | flags


async def send(dut: IrDut, levels: list[nec.Level]) -> None:
    """Play levels, wait the gap and let the logic settle.

    Parameters
    ----------
    dut : IrDut
        The design under test.
    levels : list[nec.Level]
        Levels to play.
    """
    await nec.play(dut, levels, GAP_US)
    await bus.cycles(dut, SETTLE)


async def level(dut: IrDut) -> int:
    """Return the FIFO level from the status register.

    Parameters
    ----------
    dut : IrDut
        The design under test.

    Returns
    -------
    int
        Number of frames stored.
    """
    status = await bus.read(dut, STATUS)
    return (status >> STAT_LEVEL_SHIFT) & 0xFF


@cocotb.test()
async def test_reset_state(dut: IrDut) -> None:
    """After reset the receiver is off, empty and quiet."""
    await start(dut, 0)
    eq(await bus.read(dut, CTRL), 0, "ctrl")
    eq(int(dut.o_irq.value), 0, "irq")
    eq(await bus.read(dut, DATA), 0, "data")
    eq(await level(dut), 0, "level")


@cocotb.test()
async def test_standard_frame(dut: IrDut) -> None:
    """A frame with complemented address and command is decoded."""
    await start(dut)
    await send(dut, nec.frame_levels(nec.frame_bytes(0x04, 0xA5, False)))
    status = await bus.read(dut, STATUS)
    check(status & STAT_NOT_EMPTY != 0, "not empty")
    eq(int(dut.o_irq.value), 1, "irq")
    eq(await bus.read(dut, DATA), word(0x0004, 0xA5), "frame")
    eq(await level(dut), 0, "popped")
    eq(await bus.read(dut, DATA), 0, "empty reads zero")
    eq(int(dut.o_irq.value), 0, "irq cleared")


@cocotb.test()
async def test_extended_frame(dut: IrDut) -> None:
    """A 16-bit address frame is decoded as extended."""
    await start(dut)
    await send(dut, nec.frame_levels(nec.frame_bytes(0x1234, 0x0F, True)))
    eq(await bus.read(dut, DATA), word(0x1234, 0x0F, FRAME_EXT), "frame")


@cocotb.test()
async def test_extended_disabled(dut: IrDut) -> None:
    """With the extended mode off the frame is an error."""
    await start(dut, CTRL_EN | CTRL_FRAME_IE)
    await send(dut, nec.frame_levels(nec.frame_bytes(0x1234, 0x0F, True)))
    eq(await level(dut), 0, "no frame")
    status = await bus.read(dut, STATUS)
    check(status & STAT_FRAME_ERR != 0, "error flag")


@cocotb.test()
async def test_repeat(dut: IrDut) -> None:
    """Repeat codes repeat the address and command of the frame."""
    await start(dut)
    levels = nec.frame_levels(nec.frame_bytes(0x40, 0x12, False))
    await nec.play(dut, levels, 40000.0)
    for _ in range(3):
        await nec.play(dut, nec.repeat_levels(), 96000.0)
    await bus.cycles(dut, SETTLE)
    eq(await level(dut), 4, "level")
    eq(await bus.read(dut, DATA), word(0x40, 0x12), "first")
    for index in range(3):
        eq(
            await bus.read(dut, DATA),
            word(0x40, 0x12, FRAME_REPEAT),
            f"repeat {index}",
        )


@cocotb.test()
async def test_repeat_without_frame(dut: IrDut) -> None:
    """A repeat code with no earlier frame is an error."""
    await start(dut)
    await send(dut, nec.repeat_levels())
    eq(await level(dut), 0, "level")
    status = await bus.read(dut, STATUS)
    check(status & STAT_FRAME_ERR != 0, "error flag")


@cocotb.test()
async def test_bad_complement(dut: IrDut) -> None:
    """A command whose complement is wrong is dropped and flagged."""
    await start(dut)
    data = nec.frame_bytes(0x04, 0xA5, False)
    data[3] ^= 0x01
    await send(dut, nec.frame_levels(data))
    eq(await level(dut), 0, "level")
    status = await bus.read(dut, STATUS)
    check(status & STAT_FRAME_ERR != 0, "error flag")
    await bus.write(dut, STATUS, STAT_FRAME_ERR)
    status = await bus.read(dut, STATUS)
    eq(status & STAT_FRAME_ERR, 0, "flag cleared by writing one")
    await send(dut, nec.frame_levels(nec.frame_bytes(0x04, 0xA5, False)))
    eq(await bus.read(dut, DATA), word(0x0004, 0xA5), "next frame")


@cocotb.test()
async def test_truncated_frame_recovers(dut: IrDut) -> None:
    """A truncated frame times out, is flagged, and the next works."""
    await start(dut)
    levels = nec.frame_levels(nec.frame_bytes(0x04, 0xA5, False))
    await send(dut, levels[:30])
    status = await bus.read(dut, STATUS)
    check(status & STAT_FRAME_ERR != 0, "error flag")
    eq(await level(dut), 0, "level")
    await send(dut, levels)
    eq(await bus.read(dut, DATA), word(0x0004, 0xA5), "next frame")


@cocotb.test()
async def test_wrong_widths(dut: IrDut) -> None:
    """A bit space outside both ranges makes the frame malformed."""
    await start(dut)
    levels = nec.frame_levels(nec.frame_bytes(0x04, 0xA5, False))
    levels[7] = (False, 1100.0)
    await send(dut, levels)
    eq(await level(dut), 0, "level")
    status = await bus.read(dut, STATUS)
    check(status & STAT_FRAME_ERR != 0, "error flag")


@cocotb.test()
async def test_jitter_and_glitches(dut: IrDut) -> None:
    """Widths within the tolerance and short glitches still decode."""
    await start(dut)
    rng = seeded(0x1CE)
    for index in range(4):
        data = nec.frame_bytes(index * 17 + 1, 0xFF - index * 31, False)
        levels = nec.frame_levels(data, rng, 0.12)
        # Glitches of 8 us, below the filter, in a mark and a space.
        mark = levels[6]
        space = levels[7]
        noisy = levels[:6]
        noisy += [(True, mark[1] / 2), (False, 8.0), (True, mark[1] / 2)]
        noisy += [(False, space[1] / 2), (True, 8.0), (False, space[1] / 2)]
        noisy += levels[8:]
        await send(dut, noisy)
        eq(
            await bus.read(dut, DATA),
            word(index * 17 + 1, 0xFF - index * 31),
            f"frame {index}",
        )


@cocotb.test()
async def test_noise_outside_frame(dut: IrDut) -> None:
    """Pulses that are not a leader are ignored without an error."""
    await start(dut)
    for width in (300.0, 1500.0, 3000.0, 20000.0):
        await send(dut, [(True, width)])
    eq(await level(dut), 0, "level")
    status = await bus.read(dut, STATUS)
    eq(status & STAT_FRAME_ERR, 0, "no error flag")
    await send(dut, nec.frame_levels(nec.frame_bytes(0x07, 0x09, False)))
    eq(await bus.read(dut, DATA), word(0x07, 0x09), "frame after noise")


@cocotb.test()
async def test_disabled_ignores_frames(dut: IrDut) -> None:
    """With the enable bit off nothing is decoded."""
    await start(dut, 0)
    await send(dut, nec.frame_levels(nec.frame_bytes(0x04, 0xA5, False)))
    eq(await level(dut), 0, "level")
    await bus.write(dut, CTRL, CTRL_DEFAULT)
    await bus.cycles(dut, 10)
    await send(dut, nec.frame_levels(nec.frame_bytes(0x04, 0xA5, False)))
    eq(await bus.read(dut, DATA), word(0x0004, 0xA5), "enabled")


@cocotb.test()
async def test_flush_and_irq_mask(dut: IrDut) -> None:
    """Flush empties the FIFO; the frame interrupt follows its mask."""
    await start(dut, CTRL_EN)
    await send(dut, nec.frame_levels(nec.frame_bytes(0x04, 0xA5, False)))
    eq(await level(dut), 1, "level")
    eq(int(dut.o_irq.value), 0, "masked")
    await bus.write(dut, CTRL, CTRL_EN | CTRL_FRAME_IE)
    await bus.cycles(dut, 2)
    eq(int(dut.o_irq.value), 1, "unmasked")
    await bus.write(dut, CTRL, CTRL_EN | CTRL_FRAME_IE | CTRL_FLUSH)
    await bus.cycles(dut, 2)
    eq(await level(dut), 0, "flushed")
    eq(int(dut.o_irq.value), 0, "irq off")
    eq(await bus.read(dut, CTRL), CTRL_EN | CTRL_FRAME_IE, "flush reads 0")


@cocotb.test()
async def test_raw_widths(dut: IrDut) -> None:
    """The raw registers hold the last mark and space, in cycles."""
    await start(dut)
    await bus.write(dut, STATUS, STAT_RAW_NEW)
    await nec.play(dut, [(True, 1000.0), (False, 2500.0), (True, 700.0)])
    await bus.cycles(dut, 60)
    status = await bus.read(dut, STATUS)
    check(status & STAT_RAW_NEW != 0, "raw new")
    mark = await bus.read(dut, RAW_MARK)
    space = await bus.read(dut, RAW_SPACE)
    check(abs(mark - 700) <= WIDTH_TOL, f"mark {mark}")
    check(abs(space - 2500) <= WIDTH_TOL, f"space {space}")
    await bus.write(dut, STATUS, STAT_RAW_NEW)
    status = await bus.read(dut, STATUS)
    eq(status & STAT_RAW_NEW, 0, "raw new cleared")
    await Timer(1, unit="us")

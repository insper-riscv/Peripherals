"""Ext_irq_controller (8 lines): pending, enable, source id and MEIP."""

import cocotb

from tests.python.unittests.intc.registers import (
    ENABLE,
    PENDING,
    RESERVED,
    SOURCE_ID,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import ExtIrqControllerDut

LINES = 8
ALL_LINES = (1 << LINES) - 1
SYNC_CYCLES = 2


async def raise_lines(dut: ExtIrqControllerDut, mask: int) -> None:
    """Drive the lines and wait until the synchronizer shows them.

    Parameters
    ----------
    dut : ExtIrqControllerDut
        The design under test.
    mask : int
        Value of the lines.
    """
    dut.i_irq_lines.value = mask
    await bus.cycles(dut, SYNC_CYCLES)


async def setup(dut: ExtIrqControllerDut) -> None:
    """Release every line and reset the controller.

    Parameters
    ----------
    dut : ExtIrqControllerDut
        The design under test.
    """
    dut.i_irq_lines.value = 0
    await bus.reset(dut)


@cocotb.test()
async def test_reset_state(dut: ExtIrqControllerDut) -> None:
    """Every register reads zero and MEIP is low."""
    await setup(dut)
    check(await bus.read(dut, PENDING) == 0, "pending")
    check(await bus.read(dut, ENABLE) == 0, "enable")
    check(await bus.read(dut, SOURCE_ID) == 0, "source id")
    check(await bus.read(dut, RESERVED) == 0, "reserved")
    check(int(dut.o_irq_external.value) == 0, "MEIP")


@cocotb.test()
async def test_each_line_reaches_pending_after_the_synchronizer(
    dut: ExtIrqControllerDut,
) -> None:
    """A line shows in PENDING after two cycles, and only its own bit."""
    await setup(dut)
    for n in range(LINES):
        dut.i_irq_lines.value = 1 << n
        await bus.cycles(dut, 1)
        check(await bus.read(dut, PENDING) == 0, f"line {n} too early")
        await bus.cycles(dut, 1)
        check(await bus.read(dut, PENDING) == 1 << n, f"line {n}")
        await raise_lines(dut, 0)
        check(await bus.read(dut, PENDING) == 0, f"line {n} released")


@cocotb.test()
async def test_enable_reads_back_and_masks_the_output(
    dut: ExtIrqControllerDut,
) -> None:
    """A pending line raises MEIP only when its enable bit is set."""
    await setup(dut)
    await raise_lines(dut, 0b00100000)
    check(int(dut.o_irq_external.value) == 0, "masked line")
    await bus.write(dut, ENABLE, 0b00000100)
    check(await bus.read(dut, ENABLE) == 0b00000100, "enable read back")
    check(int(dut.o_irq_external.value) == 0, "other line enabled")
    await bus.write(dut, ENABLE, 0b00100100)
    check(int(dut.o_irq_external.value) == 1, "enabled line")
    await bus.write(dut, ENABLE, 0)
    check(int(dut.o_irq_external.value) == 0, "disabled again")


@cocotb.test()
async def test_enable_keeps_only_the_existing_lines(
    dut: ExtIrqControllerDut,
) -> None:
    """Bits above the last line are not stored."""
    await setup(dut)
    await bus.write(dut, ENABLE, 0xFFFFFFFF)
    check(await bus.read(dut, ENABLE) == ALL_LINES, "enable mask")


@cocotb.test()
async def test_output_follows_the_level_of_the_line(
    dut: ExtIrqControllerDut,
) -> None:
    """The interrupt is level sensitive: it falls with the line."""
    await setup(dut)
    await bus.write(dut, ENABLE, ALL_LINES)
    await raise_lines(dut, 0b1000)
    check(int(dut.o_irq_external.value) == 1, "raised")
    await raise_lines(dut, 0)
    check(int(dut.o_irq_external.value) == 0, "fell with the line")
    check(await bus.read(dut, PENDING) == 0, "nothing latched")


@cocotb.test()
async def test_several_sources_and_source_id(
    dut: ExtIrqControllerDut,
) -> None:
    """The lowest enabled pending line is reported, as its index plus one."""
    await setup(dut)
    await bus.write(dut, ENABLE, 0b11111010)
    await raise_lines(dut, 0b10010101)
    check(await bus.read(dut, PENDING) == 0b10010101, "pending")
    check(int(dut.o_irq_external.value) == 1, "MEIP")
    check(await bus.read(dut, SOURCE_ID) == 5, "line 4 wins over line 7")
    await raise_lines(dut, 0b10000101)
    check(await bus.read(dut, SOURCE_ID) == 8, "line 7 is the last")
    await raise_lines(dut, 0b00000101)
    check(int(dut.o_irq_external.value) == 0, "only disabled lines left")
    check(await bus.read(dut, SOURCE_ID) == 0, "no source")


@cocotb.test()
async def test_source_id_of_the_first_line(dut: ExtIrqControllerDut) -> None:
    """Line zero is reported as one, so zero keeps meaning no source."""
    await setup(dut)
    await bus.write(dut, ENABLE, ALL_LINES)
    await raise_lines(dut, ALL_LINES)
    check(await bus.read(dut, SOURCE_ID) == 1, "line 0 wins")


@cocotb.test()
async def test_read_only_registers_ignore_writes(
    dut: ExtIrqControllerDut,
) -> None:
    """Writes to PENDING, SOURCE_ID and the reserved word change nothing."""
    await setup(dut)
    await bus.write(dut, ENABLE, 0b0101)
    await raise_lines(dut, 0b0100)
    for address in (PENDING, SOURCE_ID, RESERVED):
        await bus.write(dut, address, 0xFFFFFFFF)
    check(await bus.read(dut, ENABLE) == 0b0101, "enable intact")
    check(await bus.read(dut, PENDING) == 0b0100, "pending intact")
    check(await bus.read(dut, SOURCE_ID) == 3, "source id intact")


@cocotb.test()
async def test_reads_have_no_side_effect(dut: ExtIrqControllerDut) -> None:
    """Reading every register twice changes neither state nor MEIP."""
    await setup(dut)
    await bus.write(dut, ENABLE, 0b10)
    await raise_lines(dut, 0b10)
    for _ in range(2):
        for address in (PENDING, ENABLE, SOURCE_ID, RESERVED):
            await bus.read(dut, address)
    check(int(dut.o_irq_external.value) == 1, "MEIP")
    check(await bus.read(dut, PENDING) == 0b10, "pending")
    check(await bus.read(dut, SOURCE_ID) == 2, "source id")


@cocotb.test()
async def test_data_without_write_strobe_is_not_stored(
    dut: ExtIrqControllerDut,
) -> None:
    """The enable register changes only with the write strobe."""
    await setup(dut)
    dut.i_address.value = ENABLE
    dut.i_data_in.value = ALL_LINES
    await bus.cycles(dut, 2)
    check(await bus.read(dut, ENABLE) == 0, "no strobe, no write")


@cocotb.test()
async def test_reset_clears_the_enable(dut: ExtIrqControllerDut) -> None:
    """A reset empties the enable register and drops MEIP."""
    await setup(dut)
    await bus.write(dut, ENABLE, ALL_LINES)
    await raise_lines(dut, 0b1)
    check(int(dut.o_irq_external.value) == 1, "MEIP before the reset")
    dut.i_rst.value = 1
    await bus.cycles(dut, 1)
    dut.i_rst.value = 0
    check(await bus.read(dut, ENABLE) == 0, "enable after the reset")
    check(int(dut.o_irq_external.value) == 0, "MEIP after the reset")

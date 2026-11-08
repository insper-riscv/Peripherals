"""FLASH controller: registers, command pulse, status, page buffer."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.flash_controller.registers import (
    ADDR,
    BUF_DATA,
    BUF_PTR,
    CMD,
    ERASE,
    IRQ_DONE,
    IRQ_ENABLE,
    IRQ_REFUSED,
    IRQ_STATUS,
    PROGRAM,
    RESERVED,
    STATUS,
    WREN,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import FlashControllerDut

PAGE_WORDS = 64
ONES = 0xFFFFFFFF
ADDRESS = 0x20003100
ADDRESS_LOW = 0x0003FF04
FAR_INDEX = 40
NEXT_INDEX = 41
FIRST_WORD = 0xDEAD0001
SECOND_WORD = 0xDEAD0002
LATE_INDEX = 9
LATE_WORD = 0x0BADCAFE
KEPT_INDEX = 7
KEPT_WORD = 0x77


async def start(dut: FlashControllerDut) -> None:
    """Reset the controller and idle the chip side.

    Parameters
    ----------
    dut : FlashControllerDut
        The design under test.
    """
    dut.i_busy.value = 0
    dut.i_wel.value = 0
    dut.i_refused.value = 0
    dut.i_buf_idx.value = 0
    await bus.reset(dut)


async def chip_read(dut: FlashControllerDut, index: int) -> int:
    """Read one word of the page buffer the way the chip does.

    The index is registered by the chip, and the word comes one clock
    later.

    Parameters
    ----------
    dut : FlashControllerDut
        The design under test.
    index : int
        Word index in the page buffer.

    Returns
    -------
    int
        The word read.
    """
    dut.i_buf_idx.value = index
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return int(dut.o_buf_data.value)


@cocotb.test()
async def test_reset_state(dut: FlashControllerDut) -> None:
    """Registers read zero and the buffer holds ones after the reset."""
    await start(dut)
    for register in (CMD, ADDR, STATUS, BUF_PTR, BUF_DATA, *RESERVED):
        check(await bus.read(dut, register) == 0, f"register {register}")
    check(int(dut.o_cmd_valid.value) == 0)
    for index in (0, 1, PAGE_WORDS - 1):
        check(await chip_read(dut, index) == ONES, f"word {index}")


@cocotb.test()
async def test_address_register(dut: FlashControllerDut) -> None:
    """ADDR keeps the whole word and only a write to ADDR changes it."""
    await start(dut)
    await bus.write(dut, ADDR, ADDRESS)
    check(await bus.read(dut, ADDR) == ADDRESS)
    await bus.write(dut, ADDR, ADDRESS_LOW)
    check(await bus.read(dut, ADDR) == ADDRESS_LOW)
    await bus.write(dut, BUF_PTR, 5)
    await bus.write(dut, BUF_DATA, 0x1234)
    await bus.write(dut, CMD, WREN)
    for register in RESERVED:
        await bus.write(dut, register, ONES)
    check(await bus.read(dut, ADDR) == ADDRESS_LOW)
    check(int(dut.o_cmd_addr.value) == ADDRESS_LOW)


@cocotb.test()
async def test_command_pulse(dut: FlashControllerDut) -> None:
    """A write to CMD pulses the command with the op and the address."""
    await start(dut)
    await bus.write(dut, ADDR, ADDRESS)
    seen: list[tuple[int, int]] = []

    async def watch() -> None:
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.o_cmd_valid.value) == 1:
                seen.append(
                    (int(dut.o_cmd_op.value), int(dut.o_cmd_addr.value))
                )

    cocotb.start_soon(watch())
    for op in (WREN, ERASE, PROGRAM):
        await bus.write(dut, CMD, op)
    # only the low three bits are the code
    await bus.write(dut, CMD, 0xFFFFFFFA)
    await bus.write(dut, ADDR, ADDRESS_LOW)
    await bus.write(dut, BUF_DATA, ERASE)
    await bus.write(dut, BUF_PTR, ERASE)
    for register in RESERVED:
        await bus.write(dut, register, ERASE)
    await bus.cycles(dut, 3)
    check(
        seen
        == [
            (WREN, ADDRESS),
            (ERASE, ADDRESS),
            (PROGRAM, ADDRESS),
            (2, ADDRESS),
        ],
        str(seen),
    )


@cocotb.test()
async def test_the_pulse_lasts_the_write_cycle(
    dut: FlashControllerDut,
) -> None:
    """The pulse is high in the cycle of the write and nowhere else."""
    await start(dut)
    dut.i_address.value = CMD
    dut.i_data_in.value = WREN
    await Timer(1, unit="ns")
    check(int(dut.o_cmd_valid.value) == 0, "no pulse without the write")
    dut.i_write.value = 1
    await Timer(1, unit="ns")
    check(int(dut.o_cmd_valid.value) == 1, "pulse in the write cycle")
    await RisingEdge(dut.i_clk)
    dut.i_write.value = 0
    await Timer(1, unit="ns")
    check(int(dut.o_cmd_valid.value) == 0, "pulse gone after the write")


@cocotb.test()
async def test_status_follows_the_chip(dut: FlashControllerDut) -> None:
    """STATUS shows busy, latch and refusal, and only on a read."""
    await start(dut)
    for busy in (0, 1):
        for wel in (0, 1):
            for refused in (0, 1):
                dut.i_busy.value = busy
                dut.i_wel.value = wel
                dut.i_refused.value = refused
                value = await bus.read(dut, STATUS)
                check(value == busy | (wel << 1) | (refused << 2), str(value))
    dut.i_address.value = STATUS
    dut.i_read.value = 0
    await Timer(1, unit="ns")
    check(int(dut.o_data_out.value) == 0, "no read, no data")


@cocotb.test()
async def test_buffer_fills_with_the_pointer(dut: FlashControllerDut) -> None:
    """BUF_DATA writes at BUF_PTR and advances it by one."""
    await start(dut)
    for index in range(PAGE_WORDS):
        check(await bus.read(dut, BUF_PTR) == index, f"pointer {index}")
        await bus.write(dut, BUF_DATA, 0xA5000000 + index)
    check(await bus.read(dut, BUF_PTR) == 0, "the pointer wraps")
    for index in range(PAGE_WORDS):
        value = await chip_read(dut, index)
        check(value == 0xA5000000 + index, f"word {index}")


@cocotb.test()
async def test_the_pointer_can_be_set(dut: FlashControllerDut) -> None:
    """Writing BUF_PTR moves the next BUF_DATA write."""
    await start(dut)
    untouched = await chip_read(dut, 4)
    await bus.write(dut, BUF_PTR, FAR_INDEX)
    await bus.write(dut, BUF_DATA, FIRST_WORD)
    check(await bus.read(dut, BUF_PTR) == NEXT_INDEX)
    await bus.write(dut, BUF_PTR, 3)
    await bus.write(dut, BUF_DATA, SECOND_WORD)
    check(await chip_read(dut, FAR_INDEX) == FIRST_WORD)
    check(await chip_read(dut, 3) == SECOND_WORD)
    check(await chip_read(dut, 4) == untouched, "word 4 kept its content")


@cocotb.test()
async def test_the_chip_reads_one_clock_late(dut: FlashControllerDut) -> None:
    """The buffer read is registered, like the storage of the chip."""
    await start(dut)
    await bus.write(dut, BUF_PTR, LATE_INDEX)
    await bus.write(dut, BUF_DATA, LATE_WORD)
    dut.i_buf_idx.value = LATE_INDEX
    await Timer(1, unit="ns")
    check(int(dut.o_buf_data.value) != LATE_WORD, "not before the edge")
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(int(dut.o_buf_data.value) == LATE_WORD, "after the edge")


@cocotb.test()
async def test_reset_clears_the_registers(dut: FlashControllerDut) -> None:
    """Reset zeroes ADDR and BUF_PTR and keeps the buffer."""
    await start(dut)
    await bus.write(dut, ADDR, ADDRESS)
    await bus.write(dut, BUF_PTR, KEPT_INDEX)
    await bus.write(dut, BUF_DATA, KEPT_WORD)
    dut.i_rst.value = 1
    await bus.cycles(dut, 2)
    dut.i_rst.value = 0
    await Timer(1, unit="ns")
    check(await bus.read(dut, ADDR) == 0)
    check(await bus.read(dut, BUF_PTR) == 0)
    check(await chip_read(dut, KEPT_INDEX) == KEPT_WORD)


async def pulse_busy(dut: FlashControllerDut, cycles: int) -> None:
    """Hold the chip busy for a few cycles, as a command would.

    Parameters
    ----------
    dut : FlashControllerDut
        The design under test.
    cycles : int
        How many cycles busy stays high.
    """
    dut.i_busy.value = 1
    await bus.cycles(dut, cycles)
    dut.i_busy.value = 0
    await bus.cycles(dut, 1)


@cocotb.test()
async def test_irq_registers_reset_and_read_back(
    dut: FlashControllerDut,
) -> None:
    """The enable holds two bits, the status starts clear."""
    await start(dut)
    check(await bus.read(dut, IRQ_ENABLE) == 0)
    check(await bus.read(dut, IRQ_STATUS) == 0)
    await bus.write(dut, IRQ_ENABLE, ONES)
    check(await bus.read(dut, IRQ_ENABLE) == IRQ_DONE | IRQ_REFUSED)
    check(int(dut.o_irq.value) == 0, "enabled, nothing happened")
    await bus.write(dut, IRQ_ENABLE, IRQ_REFUSED)
    check(await bus.read(dut, IRQ_ENABLE) == IRQ_REFUSED)


@cocotb.test()
async def test_done_interrupt_on_busy_falling_and_w1c(
    dut: FlashControllerDut,
) -> None:
    """The end of a command raises DONE; writing 1 clears it."""
    await start(dut)
    await bus.write(dut, IRQ_ENABLE, IRQ_DONE)
    dut.i_busy.value = 1
    await bus.cycles(dut, 3)
    check(int(dut.o_irq.value) == 0, "still busy")
    check(await bus.read(dut, IRQ_STATUS) == 0)
    dut.i_busy.value = 0
    await bus.cycles(dut, 2)
    check(int(dut.o_irq.value) == 1, "command finished")
    check(await bus.read(dut, IRQ_STATUS) == IRQ_DONE)
    check(await bus.read(dut, IRQ_STATUS) == IRQ_DONE, "read does not clear")
    await bus.write(dut, IRQ_STATUS, IRQ_REFUSED)
    check(await bus.read(dut, IRQ_STATUS) == IRQ_DONE, "0 and other bits keep")
    await bus.write(dut, IRQ_STATUS, IRQ_DONE)
    check(await bus.read(dut, IRQ_STATUS) == 0)
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_refused_interrupt_on_rising_edge(
    dut: FlashControllerDut,
) -> None:
    """A refusal raises REFUSED once; the enable reaches o_irq."""
    await start(dut)
    dut.i_refused.value = 1
    await bus.cycles(dut, 3)
    check(await bus.read(dut, IRQ_STATUS) == IRQ_REFUSED, "pending anyway")
    check(int(dut.o_irq.value) == 0, "not enabled")
    await bus.write(dut, IRQ_ENABLE, IRQ_REFUSED)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, IRQ_STATUS, IRQ_REFUSED)
    await bus.cycles(dut, 3)
    check(int(dut.o_irq.value) == 0, "level stays at one, no new edge")
    dut.i_refused.value = 0
    await bus.cycles(dut, 2)
    dut.i_refused.value = 1
    await bus.cycles(dut, 2)
    check(int(dut.o_irq.value) == 1, "a new refusal")


@cocotb.test()
async def test_irq_mask_and_independent_causes(
    dut: FlashControllerDut,
) -> None:
    """Each enable only lets its own cause through."""
    await start(dut)
    await bus.write(dut, IRQ_ENABLE, IRQ_REFUSED)
    await pulse_busy(dut, 3)
    check(int(dut.o_irq.value) == 0, "DONE pending but not enabled")
    check(await bus.read(dut, IRQ_STATUS) == IRQ_DONE)
    await bus.write(dut, IRQ_ENABLE, IRQ_DONE)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, IRQ_ENABLE, 0)
    check(int(dut.o_irq.value) == 0)

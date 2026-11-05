"""CLINT: mtime, mtimecmp, msip, the MTIP and MSIP outputs."""

import cocotb

from tests.python.unittests.CLINT.registers import (
    MASK32,
    MSIP,
    MTIME_HI,
    MTIME_LO,
    MTIMECMP_HI,
    MTIMECMP_LO,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import ClintDut

HOLD_CYCLES = 4
READ_WINDOW = 40
HIGH_WORD = 7
CMP_LOW_WORD = 0x1234_5678
CMP_HIGH_WORD = 0x9ABC_DEF0
MTIME_START = 10
CMP_VALUE = 25


async def write64(dut: ClintDut, lo_addr: int, value: int) -> None:
    """Write a 64-bit register, high half first and then the low half.

    Parameters
    ----------
    dut : ClintDut
        The design under test.
    lo_addr : int
        Address of the low half (the high half is the next word).
    value : int
        The 64-bit value.
    """
    await bus.write(dut, lo_addr + 1, value >> 32)
    await bus.write(dut, lo_addr, value & MASK32)


async def write_mtimecmp(dut: ClintDut, value: int) -> list[int]:
    """Write mtimecmp with the sequence of the FreeRTOS port.

    Parameters
    ----------
    dut : ClintDut
        The design under test.
    value : int
        The new 64-bit value.

    Returns
    -------
    list[int]
        The MTIP seen in every cycle of the sequence.
    """
    seen: list[int] = []
    for addr, data in (
        (MTIMECMP_LO, MASK32),
        (MTIMECMP_HI, value >> 32),
        (MTIMECMP_LO, value & MASK32),
    ):
        await bus.write(dut, addr, data)
        seen.append(int(dut.o_irq_timer.value))
    return seen


@cocotb.test()
async def test_reset_state(dut: ClintDut) -> None:
    """After reset: mtimecmp all ones, msip zero, no interrupt."""
    await bus.reset(dut)
    check(await bus.read(dut, MTIMECMP_LO) == MASK32)
    check(await bus.read(dut, MTIMECMP_HI) == MASK32)
    check(await bus.read(dut, MSIP) == 0)
    check(await bus.read(dut, MTIME_HI) == 0)
    check(int(dut.o_irq_timer.value) == 0)
    check(int(dut.o_irq_software.value) == 0)


@cocotb.test()
async def test_mtime_counts_one_per_cycle(dut: ClintDut) -> None:
    """The mtime halves are writable and count one per cycle."""
    await bus.reset(dut)
    await write64(dut, MTIME_LO, (HIGH_WORD << 32) | 0x100)
    values = [await bus.read(dut, MTIME_LO) for _ in range(5)]
    check(values == [0x100 + k for k in range(5)], f"{values}")
    check(await bus.read(dut, MTIME_HI) == HIGH_WORD)


@cocotb.test()
async def test_carry_is_visible_in_the_high_half(dut: ClintDut) -> None:
    """High, low and high reads across the low wrap give one value."""
    await bus.reset(dut)
    start = 0x0000_0003_FFFF_FFFC
    await write64(dut, MTIME_LO, start)
    for k in range(12):
        hi_a = await bus.read(dut, MTIME_HI)
        lo = await bus.read(dut, MTIME_LO)
        hi_b = await bus.read(dut, MTIME_HI)
        # The three reads of one iteration are at start + 3k + 0, 1, 2.
        base = start + 3 * k
        lo_wanted = (base + 1) & MASK32
        check(hi_a == (base >> 32), f"hi {hi_a:#x} at {base:#x}")
        check(lo == lo_wanted, f"lo {lo:#x} at {base + 1:#x}")
        check(hi_b == ((base + 2) >> 32), f"hi {hi_b:#x}")


@cocotb.test()
async def test_mtimecmp_reads_back(dut: ClintDut) -> None:
    """Both halves of mtimecmp read back what was written."""
    await bus.reset(dut)
    await bus.write(dut, MTIMECMP_LO, CMP_LOW_WORD)
    await bus.write(dut, MTIMECMP_HI, CMP_HIGH_WORD)
    check(await bus.read(dut, MTIMECMP_LO) == CMP_LOW_WORD)
    check(await bus.read(dut, MTIMECMP_HI) == CMP_HIGH_WORD)


@cocotb.test()
async def test_mtip_is_the_registered_comparison(dut: ClintDut) -> None:
    """MTIP is mtime >= mtimecmp of the cycle before, in every cycle."""
    await bus.reset(dut)
    await write64(dut, MTIME_LO, MTIME_START)
    await write64(dut, MTIMECMP_LO, CMP_VALUE)
    # Two writes ran after the mtime write, so the first sample is 12.
    first = MTIME_START + 2
    fired = None
    for k in range(READ_WINDOW):
        await bus.read(dut, MSIP)
        # After the read edge MTIP compares the cycle just sampled.
        irq = int(dut.o_irq_timer.value)
        wanted = int(first + k >= CMP_VALUE)
        check(irq == wanted, f"cycle {k}: irq {irq}, wanted {wanted}")
        if irq and fired is None:
            fired = k
    check(fired == CMP_VALUE - first, f"first MTIP after sample {fired}")


@cocotb.test()
async def test_comparison_uses_all_64_bits(dut: ClintDut) -> None:
    """The high half decides before the low half."""
    await bus.reset(dut)
    await write64(dut, MTIME_LO, 0x1_0000_0000)
    await write64(dut, MTIMECMP_LO, 0xFFFF_FFFF)
    await bus.read(dut, MSIP)
    await bus.read(dut, MSIP)
    check(int(dut.o_irq_timer.value) == 1, "high half above")
    await write64(dut, MTIME_LO, 0xFFFF_FFF0)
    await write64(dut, MTIMECMP_LO, 0x1_0000_0005)
    for _ in range(4):
        await bus.read(dut, MSIP)
        check(int(dut.o_irq_timer.value) == 0, "low half above only")
    await write64(dut, MTIME_LO, 0x1_0000_0005)
    await write64(dut, MTIMECMP_LO, 0x1_0000_0005)
    await bus.read(dut, MSIP)
    await bus.read(dut, MSIP)
    check(int(dut.o_irq_timer.value) == 1, "equal values fire")


@cocotb.test()
async def test_port_sequence_never_fires_in_between(dut: ClintDut) -> None:
    """The write sequence of the port raises no MTIP that is not due."""
    await bus.reset(dut)
    await write64(dut, MTIME_LO, 0x40)
    await write64(dut, MTIMECMP_LO, 0x80)
    for _ in range(3):
        await bus.read(dut, MSIP)
    seen = await write_mtimecmp(dut, 0x1_0000_0010)
    check(seen == [0, 0, 0], f"MTIP in the sequence: {seen}")
    for _ in range(HOLD_CYCLES):
        await bus.read(dut, MSIP)
        check(int(dut.o_irq_timer.value) == 0, "MTIP after the sequence")


@cocotb.test()
async def test_port_sequence_drops_a_pending_mtip(dut: ClintDut) -> None:
    """Moving the compare value above mtime lowers a pending MTIP."""
    await bus.reset(dut)
    await write64(dut, MTIME_LO, 0x100)
    await write64(dut, MTIMECMP_LO, 0x80)
    for _ in range(3):
        await bus.read(dut, MSIP)
    check(int(dut.o_irq_timer.value) == 1, "pending")
    await write_mtimecmp(dut, 0x1000)
    for _ in range(3):
        await bus.read(dut, MSIP)
    check(int(dut.o_irq_timer.value) == 0, "dropped")


@cocotb.test()
async def test_naive_low_first_write_would_fire(dut: ClintDut) -> None:
    """Writing the low half first does raise a spurious MTIP."""
    await bus.reset(dut)
    await write64(dut, MTIME_LO, 0x40)
    await write64(dut, MTIMECMP_LO, 0x80)
    await bus.write(dut, MTIMECMP_LO, 0x10)
    await bus.read(dut, MSIP)
    await bus.read(dut, MSIP)
    check(int(dut.o_irq_timer.value) == 1, "the unsafe order fires")


@cocotb.test()
async def test_msip(dut: ClintDut) -> None:
    """Bit 0 of msip drives MSIP; the other bits are not stored."""
    await bus.reset(dut)
    await bus.write(dut, MSIP, 0xFFFF_FFFF)
    check(int(dut.o_irq_software.value) == 1)
    check(await bus.read(dut, MSIP) == 1, "only bit 0 is stored")
    await bus.write(dut, MSIP, 0xFFFF_FFFE)
    check(int(dut.o_irq_software.value) == 0)
    check(await bus.read(dut, MSIP) == 0)


@cocotb.test()
async def test_unmapped_addresses(dut: ClintDut) -> None:
    """Addresses outside the map read zero and ignore writes."""
    await bus.reset(dut)
    for address in (1, 0x1000 - 1, 0x1002, 0x2FFD, 0x3FFF):
        await bus.write(dut, address, MASK32)
        check(await bus.read(dut, address) == 0, f"{address:#x}")
    check(await bus.read(dut, MSIP) == 0)
    check(await bus.read(dut, MTIMECMP_LO) == MASK32)
    check(int(dut.o_irq_software.value) == 0)

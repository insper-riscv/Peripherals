"""PLIC: priority, threshold, enable, claim, complete, gateway."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.PLIC.registers import (
    CLAIM,
    MASK32,
    PENDING_BASE,
    THRESHOLD,
    enable_word,
    pending_word,
    priority,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import PlicDut
from tests.python.utils.rng import seeded

RANDOM_STEPS = 3000
SEED = 0x91C
WORD_SOURCES = 32
MIN_SOURCES_TIE = 3
MIN_BITS_TIE = 2
MIN_SOURCES_PAIR = 2
MIN_BITS_PAIR = 2
LINE_TOGGLE_PROB = 0.15
WRITE_BELOW = 0.3
READ_BELOW = 0.6


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
    check(actual == expected, f"{message}: {actual:#x} != {expected:#x}")


def sources_of(dut: PlicDut) -> int:
    """Return the number of sources from the width of the port.

    Parameters
    ----------
    dut : PlicDut
        The design under test.

    Returns
    -------
    int
        The number of sources.
    """
    return len(dut.i_sources)


async def prio_bits_of(dut: PlicDut) -> int:
    """Return the priority width, from the threshold register.

    Parameters
    ----------
    dut : PlicDut
        The design under test.

    Returns
    -------
    int
        The number of priority bits.
    """
    await bus.write(dut, THRESHOLD, MASK32)
    value = await bus.read(dut, THRESHOLD)
    await bus.write(dut, THRESHOLD, 0)
    return value.bit_length()


async def start(dut: PlicDut) -> tuple[int, int]:
    """Reset the PLIC with the lines low and find its generics.

    Parameters
    ----------
    dut : PlicDut
        The design under test.

    Returns
    -------
    tuple[int, int]
        The number of sources and of priority bits.
    """
    dut.i_sources.value = 0
    await bus.reset(dut)
    bits = await prio_bits_of(dut)
    return sources_of(dut), bits


async def program(
    dut: PlicDut, source: int, level: int, enabled: bool = True
) -> None:
    """Set the priority and the enable bit of a source.

    Parameters
    ----------
    dut : PlicDut
        The design under test.
    source : int
        Source id.
    level : int
        Priority.
    enabled : bool
        Whether the source is enabled.
    """
    await bus.write(dut, priority(source), level)
    word = await bus.read(dut, enable_word(source))
    bit = 1 << (source % 32)
    word = (word | bit) if enabled else (word & ~bit)
    await bus.write(dut, enable_word(source), word)


async def line(dut: PlicDut, source: int, value: int) -> None:
    """Drive one source line and let the gateway see it for a cycle.

    Parameters
    ----------
    dut : PlicDut
        The design under test.
    source : int
        Source id.
    value : int
        Level of the line.
    """
    current = int(dut.i_sources.value)
    mask = 1 << (source - 1)
    dut.i_sources.value = (current | mask) if value else (current & ~mask)
    await bus.cycles(dut, 1)


@cocotb.test()
async def test_reset_state(dut: PlicDut) -> None:
    """After reset nothing is pending, enabled or interrupting."""
    count, _ = await start(dut)
    eq(int(dut.o_meip.value), 0, "meip")
    eq(await bus.read(dut, CLAIM), 0, "claim")
    eq(await bus.read(dut, THRESHOLD), 0, "threshold")
    for source in range(0, count + 1):
        eq(await bus.read(dut, priority(source)), 0, f"priority {source}")
    eq(await bus.read(dut, PENDING_BASE), 0, "pending")
    eq(await bus.read(dut, enable_word(1)), 0, "enable")


@cocotb.test()
async def test_registers(dut: PlicDut) -> None:
    """Priority and threshold keep priority_bits; gaps read zero."""
    count, bits = await start(dut)
    top = (1 << bits) - 1
    for source in (1, count, (count + 1) // 2):
        await bus.write(dut, priority(source), MASK32)
        eq(await bus.read(dut, priority(source)), top, f"priority {source}")
        await bus.write(dut, priority(source), 0)
    await bus.write(dut, priority(0), MASK32)
    eq(await bus.read(dut, priority(0)), 0, "source 0 priority")
    await bus.write(dut, THRESHOLD, MASK32)
    eq(await bus.read(dut, THRESHOLD), top, "threshold")
    await bus.write(dut, THRESHOLD, 0)
    # The enable word keeps only existing sources; bit 0 is source 0.
    await bus.write(dut, enable_word(0), MASK32)
    expected = sum(1 << s for s in range(1, count + 1) if s < WORD_SOURCES)
    eq(await bus.read(dut, enable_word(0)), expected, "enable word 0")
    await bus.write(dut, enable_word(0), 0)
    # Addresses outside the map read zero and ignore writes.
    for address in (
        priority(count + 1),
        pending_word(count) + 0x40,
        0x7FFFF,
        CLAIM + 1,
    ):
        if address < (1 << len(dut.i_address)):
            await bus.write(dut, address, MASK32)
            eq(await bus.read(dut, address), 0, f"gap {address:#x}")
    eq(int(dut.o_meip.value), 0, "meip")
    eq(await bus.read(dut, enable_word(0)), 0, "enable word untouched")


@cocotb.test()
async def test_claim_complete_flow(dut: PlicDut) -> None:
    """One source: pending, MEIP, claim clears it, complete unmasks."""
    count, _ = await start(dut)
    source = count
    await program(dut, source, 1)
    await line(dut, source, 1)
    eq(int(dut.o_meip.value), 1, "meip after the line rises")
    eq(
        await bus.read(dut, pending_word(source)),
        1 << (source % 32),
        "pending bit",
    )
    eq(await bus.read(dut, CLAIM), source, "claim")
    eq(int(dut.o_meip.value), 0, "meip after claim")
    eq(await bus.read(dut, pending_word(source)), 0, "pending after claim")
    # The line is still high: masked until the complete.
    await bus.cycles(dut, 4)
    eq(int(dut.o_meip.value), 0, "masked while in flight")
    eq(await bus.read(dut, CLAIM), 0, "claim while masked")
    await bus.write(dut, CLAIM, source)
    await bus.cycles(dut, 1)
    eq(
        int(dut.o_meip.value),
        1,
        "level still high: a new request after complete",
    )
    eq(await bus.read(dut, CLAIM), source, "second claim")
    await line(dut, source, 0)
    await bus.write(dut, CLAIM, source)
    await bus.cycles(dut, 3)
    eq(int(dut.o_meip.value), 0, "line low at complete: no new request")


@cocotb.test()
async def test_pending_survives_line_drop(dut: PlicDut) -> None:
    """A request stays pending after the line falls until the claim."""
    count, _ = await start(dut)
    await program(dut, 1, 1)
    await line(dut, 1, 1)
    await line(dut, 1, 0)
    await bus.cycles(dut, 2)
    eq(int(dut.o_meip.value), 1, "meip kept")
    eq(await bus.read(dut, CLAIM), 1, "claim")
    eq(count >= 1, True)


@cocotb.test()
async def test_priority_zero_never_interrupts(dut: PlicDut) -> None:
    """Priority 0 is pending but never raises MEIP or wins a claim."""
    count, _ = await start(dut)
    await program(dut, count, 0)
    await line(dut, count, 1)
    await bus.cycles(dut, 2)
    eq(await bus.read(dut, pending_word(count)), 1 << (count % 32), "pending")
    eq(int(dut.o_meip.value), 0, "meip")
    eq(await bus.read(dut, CLAIM), 0, "claim")
    await bus.write(dut, priority(count), 1)
    eq(int(dut.o_meip.value), 1, "meip with priority 1")


@cocotb.test()
async def test_threshold(dut: PlicDut) -> None:
    """Only a priority strictly above the threshold interrupts."""
    count, bits = await start(dut)
    top = (1 << bits) - 1
    await program(dut, 1, top)
    await line(dut, 1, 1)
    eq(int(dut.o_meip.value), 1, "above a zero threshold")
    await bus.write(dut, THRESHOLD, top)
    eq(int(dut.o_meip.value), 0, "equal to the threshold")
    eq(await bus.read(dut, CLAIM), 0, "claim at the threshold")
    if top > 1:
        await bus.write(dut, THRESHOLD, top - 1)
        eq(int(dut.o_meip.value), 1, "one above the threshold")
        eq(await bus.read(dut, CLAIM), 1, "claim above the threshold")
    eq(count >= 1, True)


@cocotb.test()
async def test_enable(dut: PlicDut) -> None:
    """A disabled source is pending but does not interrupt."""
    count, _ = await start(dut)
    await program(dut, count, 1, enabled=False)
    await line(dut, count, 1)
    await bus.cycles(dut, 1)
    eq(await bus.read(dut, pending_word(count)), 1 << (count % 32), "pending")
    eq(int(dut.o_meip.value), 0, "meip")
    await program(dut, count, 1, enabled=True)
    eq(int(dut.o_meip.value), 1, "meip after enable")
    await program(dut, count, 1, enabled=False)
    eq(int(dut.o_meip.value), 0, "meip after disable")


@cocotb.test()
async def test_priority_and_tie(dut: PlicDut) -> None:
    """The highest priority wins; a tie goes to the lowest id."""
    count, bits = await start(dut)
    if count < MIN_SOURCES_TIE or bits < MIN_BITS_TIE:
        return
    top = (1 << bits) - 1
    for source in (1, 2, 3):
        await program(dut, source, 1)
        await line(dut, source, 1)
    eq(await bus.read(dut, CLAIM), 1, "tie among 1, 2 and 3")
    eq(await bus.read(dut, CLAIM), 2, "tie among 2 and 3")
    await program(dut, 3, top)
    eq(await bus.read(dut, CLAIM), 3, "higher priority, higher id")
    eq(await bus.read(dut, CLAIM), 0, "nothing left")


@cocotb.test()
async def test_masked_source_and_complete_rules(dut: PlicDut) -> None:
    """A complete of a wrong or disabled id does not unmask."""
    count, _ = await start(dut)
    source = min(2, count)
    await program(dut, source, 1)
    await line(dut, source, 1)
    eq(await bus.read(dut, CLAIM), source, "claim")
    other = source + 1 if source < count else source - 1
    for wrong in (0, other, count + 1, 0x80000000 | source, MASK32):
        await bus.write(dut, CLAIM, wrong)
        await bus.cycles(dut, 2)
        eq(int(dut.o_meip.value), 0, f"complete {wrong:#x} does not unmask")
    # Complete of a disabled source is ignored: it stays masked.
    await program(dut, source, 1, enabled=False)
    await bus.write(dut, CLAIM, source)
    await program(dut, source, 1, enabled=True)
    await bus.cycles(dut, 2)
    eq(int(dut.o_meip.value), 0, "complete while disabled is ignored")
    await bus.write(dut, CLAIM, source)
    await bus.cycles(dut, 2)
    eq(int(dut.o_meip.value), 1, "complete of the claimed id unmasks")


@cocotb.test()
async def test_independent_gateways(dut: PlicDut) -> None:
    """Completing one source does not unmask another in flight."""
    count, bits = await start(dut)
    if count < MIN_SOURCES_PAIR or bits < MIN_BITS_PAIR:
        return
    await program(dut, 1, 1)
    await program(dut, 2, 2)
    dut.i_sources.value = 3
    await bus.cycles(dut, 2)
    eq(await bus.read(dut, CLAIM), 2, "claim 2")
    eq(await bus.read(dut, CLAIM), 1, "claim 1")
    await bus.write(dut, CLAIM, 2)
    await bus.cycles(dut, 2)
    eq(await bus.read(dut, CLAIM), 2, "2 is back, 1 is still masked")
    eq(await bus.read(dut, CLAIM), 0, "1 stays masked")


@cocotb.test()
async def test_claim_read_without_candidate_is_inert(dut: PlicDut) -> None:
    """A claim read with no candidate returns 0 and changes nothing."""
    count, _ = await start(dut)
    await program(dut, 1, 1, enabled=False)
    await line(dut, 1, 1)
    for _ in range(3):
        eq(await bus.read(dut, CLAIM), 0, "claim")
    eq(await bus.read(dut, pending_word(1)), 2, "pending kept")
    eq(count >= 1, True)


@cocotb.test()
async def test_every_source(dut: PlicDut) -> None:
    """Each source, the highest ids included, is claimed by its id."""
    count, _ = await start(dut)
    step = max(1, count // 40)
    for source in sorted({1, count} | set(range(1, count + 1, step))):
        await program(dut, source, 1)
        await line(dut, source, 1)
        eq(await bus.read(dut, CLAIM), source, f"claim {source}")
        await bus.write(dut, CLAIM, source)
        await line(dut, source, 0)
        await program(dut, source, 0, enabled=False)
        eq(int(dut.o_meip.value), 0, f"meip after {source}")


class Model:
    """Reference model of the PLIC, one step per clock edge."""

    def __init__(self, count: int, bits: int) -> None:
        """Create the model with every source idle.

        Parameters
        ----------
        count : int
            Number of sources.
        bits : int
            Priority width in bits.
        """
        self.count = count
        self.bits = bits
        self.prio = [0] * (count + 1)
        self.enable = [False] * (count + 1)
        self.thr = 0
        self.pend = [False] * (count + 1)
        self.fly = [False] * (count + 1)

    def winner(self) -> int:
        """Return the claimable source or 0."""
        best, best_id = self.thr, 0
        for n in range(1, self.count + 1):
            if self.pend[n] and self.enable[n] and self.prio[n] > best:
                best, best_id = self.prio[n], n
        return best_id

    def read(self, address: int) -> int:
        """Return the data a read of the address shows now."""
        mask = (1 << self.bits) - 1
        if address == THRESHOLD:
            return self.thr
        if address == CLAIM:
            return self.winner()
        if 1 <= address <= self.count:
            return self.prio[address] & mask
        for base, state in (
            (PENDING_BASE, self.pend),
            (enable_word(0), self.enable),
        ):
            if base <= address <= base + self.count // 32:
                word = address - base
                return sum(
                    1 << (n % 32)
                    for n in range(
                        max(1, word * 32), min(self.count, word * 32 + 31) + 1
                    )
                    if state[n]
                )
        return 0

    def _complete_target(self, write: bool, address: int, data: int) -> int:
        """Return the source a write to CLAIM completes, or 0."""
        valid = 1 <= data <= self.count and self.enable[data]
        return data if (write and address == CLAIM and valid) else 0

    def _write_registers(self, address: int, data: int) -> None:
        """Apply a write to the threshold, priority and enable words."""
        mask = (1 << self.bits) - 1
        if address == THRESHOLD:
            self.thr = data & mask
        for n in range(1, self.count + 1):
            if address == n:
                self.prio[n] = data & mask
            if address == enable_word(n):
                self.enable[n] = bool((data >> (n % 32)) & 1)

    def _update_gateways(self, lines: int, claimed: int, done: int) -> None:
        """Advance the pending and in-flight flags of every gateway."""
        for n in range(1, self.count + 1):
            old_fly = self.fly[n]
            if claimed == n:
                self.pend[n] = False
            if done == n:
                self.fly[n] = False
            if (lines >> (n - 1)) & 1 and not old_fly:
                self.pend[n] = True
                self.fly[n] = True

    def step(
        self, lines: int, write: bool, read: bool, address: int, data: int
    ) -> None:
        """Advance the model by one clock edge."""
        claimed = self.winner() if (read and address == CLAIM) else 0
        done = self._complete_target(write, address, data)
        if write:
            self._write_registers(address, data)
        self._update_gateways(lines, claimed, done)


@cocotb.test()
async def test_random_against_model(dut: PlicDut) -> None:
    """Random traffic: reads, MEIP and pending follow the model."""
    count, bits = await start(dut)
    rng = seeded(SEED + count)
    model = Model(count, bits)
    lines = 0
    address_limit = 1 << len(dut.i_address)
    registers = [THRESHOLD, CLAIM, CLAIM]
    registers += [priority(n) for n in range(0, count + 2)]
    registers += [enable_word(n) for n in range(0, count + 1, 32)]
    registers += [pending_word(n) for n in range(0, count + 1, 32)]
    registers += [rng.randrange(address_limit) for _ in range(4)]
    for _ in range(RANDOM_STEPS):
        for n in range(count):
            if rng.random() < LINE_TOGGLE_PROB:
                lines ^= 1 << n
        address = rng.choice(registers)
        op = rng.random()
        write, read = op < WRITE_BELOW, WRITE_BELOW <= op < READ_BELOW
        data = rng.choice(
            [
                rng.getrandbits(32),
                rng.randrange(count + 2),
                rng.getrandbits(bits),
            ]
        )
        dut.i_sources.value = lines
        dut.i_address.value = address
        dut.i_data_in.value = data
        dut.i_write.value = int(write)
        dut.i_read.value = int(read)
        await Timer(1, unit="ns")
        eq(int(dut.o_meip.value), int(model.winner() != 0), "meip")
        eq(
            int(dut.o_data_out.value),
            model.read(address),
            f"read {address:#x}",
        )
        model.step(lines, write, read, address, data)
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")

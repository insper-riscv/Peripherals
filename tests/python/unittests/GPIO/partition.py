"""Shared checks of the adaptive GPIO block (gpio_tb), by pin layout.

A layout says how many pins the block has, which pins each group lists
(in the written order), the fixed direction of each pin and its
polarity.
Each partition test module builds a Layout and runs these checks.
"""

from dataclasses import dataclass

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import GpioDut

DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL = 0, 1, 2, 3, 4
IRQ_MASK, RISE_MASK, FALL_MASK, IRQ_STAT, PINS, LEVEL_MASK = 5, 6, 7, 8, 9, 10
GROUP_WORDS = 16
WORD_MASK = 0xFFFFFFFF
SYNC_CYCLES = 4
PATTERN = 0x5A5A5A5A


@dataclass(frozen=True)
class Layout:
    """Pin layout of one block.

    Attributes
    ----------
    pins : int
        Pins of the block.
    groups : tuple[tuple[int, ...], ...]
        Pin indices of each group, in the written order.
    dirs : str
        One character per pin: f free, i input only, o output only.
    lows : str
        One character per pin: h active high, l active low.
    """

    pins: int
    groups: tuple[tuple[int, ...], ...]
    dirs: str
    lows: str

    def place(self, pin: int) -> tuple[int, int] | None:
        """Return the (group, bit) of a pin, or None when it is off."""
        for g, members in enumerate(self.groups):
            if pin in members:
                return g, members.index(pin)
        return None

    def mask(self, g: int) -> int:
        """Return the mask of the bits a group has."""
        return (1 << len(self.groups[g])) - 1

    def fixed_dir(self, g: int) -> tuple[int, int]:
        """Return the fixed ones and the fixed mask of a group DIR."""
        ones = mask = 0
        for k, pin in enumerate(self.groups[g]):
            if self.dirs[pin] != "f":
                mask |= 1 << k
                ones |= (self.dirs[pin] == "o") << k
        return ones, mask

    def eff_dir(self, g: int, written: int) -> int:
        """Return the DIR value a group reads after a write."""
        ones, mask = self.fixed_dir(g)
        return ((written & ~mask) | ones) & self.mask(g)


def addr(group: int, register: int) -> int:
    """Return the word address of a register of a group."""
    return group * GROUP_WORDS + register


def expected_pin(
    layout: Layout, state: list[tuple[int, int]], pin: int
) -> str:
    """Return the resolved level of one pin: 0, 1 or Z.

    Parameters
    ----------
    layout : Layout
        The pin layout.
    state : list[tuple[int, int]]
        The (DIR written, OUT_LOAD) of each group.
    pin : int
        The pin.

    Returns
    -------
    str
        The level of the pin.
    """
    place = layout.place(pin)
    low = layout.lows[pin] == "l"
    if place is None:
        return ("1" if low else "0") if layout.dirs[pin] == "o" else "Z"
    g, k = place
    written, value = state[g]
    if (layout.eff_dir(g, written) >> k) & 1:
        return str(((value >> k) & 1) ^ low)
    return "Z"


def expected_pins(layout: Layout, state: list[tuple[int, int]]) -> str:
    """Return the resolved pins, most significant first.

    Parameters
    ----------
    layout : Layout
        The pin layout.
    state : list[tuple[int, int]]
        The (DIR written, OUT_LOAD) of each group.

    Returns
    -------
    str
        One character per pin: 0, 1 or Z.
    """
    return "".join(
        expected_pin(layout, state, pin)
        for pin in reversed(range(layout.pins))
    )


async def setup(dut: GpioDut) -> None:
    """Release the pins and reset the design."""
    dut.i_pin_drive.value = 0
    dut.i_pin_drive_en.value = 0
    await bus.reset(dut)


async def check_registers(dut: GpioDut, layout: Layout) -> None:
    """Each group keeps its own DIR and OUT, masked to its size."""
    await setup(dut)
    count = len(layout.groups)
    for g in range(count):
        await bus.write(dut, addr(g, OUT_LOAD), WORD_MASK)
    for g in range(count):
        got = await bus.read(dut, addr(g, OUT_LOAD))
        check(got == layout.mask(g), f"group {g} OUT_LOAD {got:#x}")
    await bus.write(dut, addr(0, OUT_CLR), WORD_MASK)
    check(await bus.read(dut, addr(0, OUT_LOAD)) == 0, "group 0 cleared")
    for g in range(1, count):
        got = await bus.read(dut, addr(g, OUT_LOAD))
        check(got == layout.mask(g), f"group {g} untouched by group 0")
    for g in range(count):
        await bus.write(dut, addr(g, DIR), WORD_MASK)
        got = await bus.read(dut, addr(g, DIR))
        check(got == layout.eff_dir(g, WORD_MASK), f"group {g} DIR {got:#x}")
        await bus.write(dut, addr(g, DIR), 0)
        got = await bus.read(dut, addr(g, DIR))
        check(got == layout.eff_dir(g, 0), f"group {g} DIR cleared {got:#x}")


async def check_pin_mapping(dut: GpioDut, layout: Layout) -> None:
    """Bit k of a group drives the k-th pin; off pins stay put."""
    await setup(dut)
    count = len(layout.groups)
    state = [(0, 0)] * count
    check(
        str(dut.o_pins.value) == expected_pins(layout, state),
        f"after reset {dut.o_pins.value}",
    )
    for g in range(count):
        value = PATTERN & layout.mask(g)
        await bus.write(dut, addr(g, OUT_LOAD), value)
        state[g] = (state[g][0], value)
        await bus.write(dut, addr(g, DIR), WORD_MASK)
        state[g] = (WORD_MASK, value)
        want = expected_pins(layout, state)
        check(
            str(dut.o_pins.value) == want,
            f"group {g}: {dut.o_pins.value} != {want}",
        )
    for g in range(count):
        await bus.write(dut, addr(g, OUT_TGL), WORD_MASK)
        state[g] = (state[g][0], state[g][1] ^ layout.mask(g))
        want = expected_pins(layout, state)
        check(
            str(dut.o_pins.value) == want,
            f"toggle {g}: {dut.o_pins.value} != {want}",
        )


def external_mask(layout: Layout) -> int:
    """Return the pins the outside world may drive (not output only)."""
    return sum(1 << p for p in range(layout.pins) if layout.dirs[p] != "o")


async def check_group_pins(
    dut: GpioDut, layout: Layout, g: int, level: int
) -> None:
    """Check PINS of one group against the levels driven outside."""
    got = await bus.read(dut, addr(g, PINS))
    for k, pin in enumerate(layout.groups[g]):
        if layout.dirs[pin] == "o":
            continue
        want = ((level >> pin) & 1) ^ (layout.lows[pin] == "l")
        check((got >> k) & 1 == want, f"group {g} bit {k} pin {pin}")
    check(got & ~layout.mask(g) == 0, f"group {g} high bits {got:#x}")


async def check_pins_read(dut: GpioDut, layout: Layout) -> None:
    """PINS of a group is the synchronized level of its pins."""
    await setup(dut)
    for level in (0x5555_5555, 0x2AAA_AAAA):
        dut.i_pin_drive.value = level & ((1 << layout.pins) - 1)
        dut.i_pin_drive_en.value = external_mask(layout)
        await bus.cycles(dut, SYNC_CYCLES)
        for g in range(len(layout.groups)):
            await check_group_pins(dut, layout, g, level)


async def check_unmapped(dut: GpioDut, layout: Layout) -> None:
    """Check that a missing group and an unused register read zero."""
    await setup(dut)
    count = len(layout.groups)
    for g in range(count):
        for register in (11, 12, 13, 14, 15):
            got = await bus.read(dut, addr(g, register))
            check(got == 0, f"group {g} register {register}")
    for g in range(count, 1 << max(0, (count - 1).bit_length())):
        await bus.write(dut, addr(g, OUT_LOAD), WORD_MASK)
        for register in (DIR, OUT_LOAD, PINS, IRQ_STAT):
            got = await bus.read(dut, addr(g, register))
            check(got == 0, f"missing group {g} register {register}")
    for g in range(count):
        got = await bus.read(dut, addr(g, OUT_LOAD))
        check(got == 0, f"group {g} intact")


async def check_group_irq(
    dut: GpioDut, layout: Layout, g: int, k: int
) -> None:
    """Raise an edge on bit k of group g and check who sees it."""
    count = len(layout.groups)
    pin = layout.groups[g][k]
    idle = (1 << pin) if layout.lows[pin] == "l" else 0
    dut.i_pin_drive_en.value = external_mask(layout)
    dut.i_pin_drive.value = idle
    await bus.cycles(dut, SYNC_CYCLES)
    for h in range(count):
        await bus.write(dut, addr(h, IRQ_MASK), WORD_MASK)
        await bus.write(dut, addr(h, RISE_MASK), WORD_MASK)
    await bus.read(dut, addr(g, IRQ_STAT))
    dut.i_pin_drive.value = (1 << pin) ^ idle
    await bus.cycles(dut, SYNC_CYCLES)
    check(int(dut.o_irq.value) == 1, f"group {g}: o_irq")
    for h in range(count):
        got = await bus.read(dut, addr(h, IRQ_STAT))
        want = (1 << k) if h == g else 0
        check(got == want, f"group {g}: IRQ_STAT of {h} is {got:#x}")
    check(int(dut.o_irq.value) == 0, f"group {g}: cleared by the read")
    for h in range(count):
        await bus.write(dut, addr(h, IRQ_MASK), 0)
        await bus.write(dut, addr(h, RISE_MASK), 0)
    dut.i_pin_drive.value = idle
    await bus.cycles(dut, SYNC_CYCLES)
    for h in range(count):
        await bus.read(dut, addr(h, IRQ_STAT))


async def check_irq(dut: GpioDut, layout: Layout) -> None:
    """Check that an edge is pending in its own group only."""
    await setup(dut)
    for g, members in enumerate(layout.groups):
        inputs = [
            k for k, pin in enumerate(members) if layout.dirs[pin] != "o"
        ]
        if inputs:
            await check_group_irq(dut, layout, g, inputs[0])


def tests(layout: Layout) -> dict[str, object]:
    """Build the cocotb tests of a layout, for a thin test module.

    Parameters
    ----------
    layout : Layout
        The pin layout the tests check.

    Returns
    -------
    dict[str, object]
        The tests by name, for the namespace of the test module.
    """

    @cocotb.test()
    async def test_registers(dut: GpioDut) -> None:
        """Each group keeps its own registers, masked to its size."""
        await check_registers(dut, layout)

    @cocotb.test()
    async def test_pin_mapping(dut: GpioDut) -> None:
        """Bit k of a group drives the k-th listed pin."""
        await check_pin_mapping(dut, layout)

    @cocotb.test()
    async def test_pins_read(dut: GpioDut) -> None:
        """PINS follows the listed pins with their polarity."""
        await check_pins_read(dut, layout)

    @cocotb.test()
    async def test_unmapped(dut: GpioDut) -> None:
        """Missing groups and unused registers read zero."""
        await check_unmapped(dut, layout)

    @cocotb.test()
    async def test_irq(dut: GpioDut) -> None:
        """An edge is pending in its own group only."""
        await check_irq(dut, layout)

    return {
        "test_registers": test_registers,
        "test_pin_mapping": test_pin_mapping,
        "test_pins_read": test_pins_read,
        "test_unmapped": test_unmapped,
        "test_irq": test_irq,
    }

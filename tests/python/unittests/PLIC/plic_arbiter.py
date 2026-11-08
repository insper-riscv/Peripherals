"""PLIC_ARBITER: highest priority over the threshold, lowest id."""

import itertools

import cocotb
from cocotb.triggers import Timer

from tests.python.utils.check import check
from tests.python.utils.dut import PlicArbiterDut
from tests.python.utils.rng import seeded

SOURCES = 6
BITS = 3
RANDOM_STEPS = 3000
SEED = 0xA2B1


def expected(
    pending: int, enable: int, levels: list[int], threshold: int
) -> int:
    """Return the id the arbiter must choose.

    Parameters
    ----------
    pending : int
        Pending mask, bit n - 1 is source n.
    enable : int
        Enable mask, bit n - 1 is source n.
    levels : list[int]
        Priority of source n at index n - 1.
    threshold : int
        Threshold of the context.

    Returns
    -------
    int
        The winner, or 0 without a candidate.
    """
    best, winner = threshold, 0
    for n in range(1, SOURCES + 1):
        live = (pending >> (n - 1)) & (enable >> (n - 1)) & 1
        if live and levels[n - 1] > best:
            best, winner = levels[n - 1], n
    return winner


async def apply(
    dut: PlicArbiterDut,
    pending: int,
    enable: int,
    levels: list[int],
    threshold: int,
) -> tuple[int, int]:
    """Drive the arbiter and return its answer.

    Parameters
    ----------
    dut : PlicArbiterDut
        The design under test.
    pending : int
        Pending mask.
    enable : int
        Enable mask.
    levels : list[int]
        Priority of each source.
    threshold : int
        Threshold.

    Returns
    -------
    tuple[int, int]
        The id and the valid output.
    """
    dut.i_pending.value = pending
    dut.i_enable.value = enable
    dut.i_priorities.value = sum(p << (BITS * k) for k, p in enumerate(levels))
    dut.i_threshold.value = threshold
    await Timer(1, unit="ns")
    return int(dut.o_id.value), int(dut.o_valid.value)


@cocotb.test()
async def test_no_candidate(dut: PlicArbiterDut) -> None:
    """Nothing pending, enabled or priority 0: id 0, not valid."""
    levels = [1] * SOURCES
    check(await apply(dut, 0, 0x3F, levels, 0) == (0, 0), "nothing pending")
    check(await apply(dut, 0x3F, 0, levels, 0) == (0, 0), "nothing enabled")
    check(
        await apply(dut, 0x3F, 0x3F, [0] * SOURCES, 0) == (0, 0),
        "priority zero",
    )


@cocotb.test()
async def test_threshold_is_strict(dut: PlicArbiterDut) -> None:
    """A priority equal to the threshold does not qualify."""
    levels = [3] * SOURCES
    check(await apply(dut, 0x20, 0x20, levels, 3) == (0, 0))
    check(await apply(dut, 0x20, 0x20, levels, 2) == (6, 1))


@cocotb.test()
async def test_tie_lowest_id(dut: PlicArbiterDut) -> None:
    """On a tie the lowest id wins; a higher priority beats the id."""
    levels = [2] * SOURCES
    check(await apply(dut, 0b101100, 0x3F, levels, 0) == (3, 1))
    levels[5] = 7
    check(await apply(dut, 0b101100, 0x3F, levels, 0) == (6, 1))


@cocotb.test()
async def test_exhaustive_masks(dut: PlicArbiterDut) -> None:
    """Every pending and enable pair with a fixed priority ladder."""
    levels = [3, 5, 5, 1, 7, 5]
    for pending, enable in itertools.product(range(1 << SOURCES), repeat=2):
        for threshold in (0, 5):
            got = await apply(dut, pending, enable, levels, threshold)
            want = expected(pending, enable, levels, threshold)
            check(
                got == (want, int(want != 0)),
                f"{pending:b} {enable:b} {threshold}: {got} != {want}",
            )


@cocotb.test()
async def test_random(dut: PlicArbiterDut) -> None:
    """Random priorities and thresholds follow the reference."""
    rng = seeded(SEED)
    for _ in range(RANDOM_STEPS):
        pending = rng.getrandbits(SOURCES)
        enable = rng.getrandbits(SOURCES)
        levels = [rng.randrange(1 << BITS) for _ in range(SOURCES)]
        threshold = rng.randrange(1 << BITS)
        got = await apply(dut, pending, enable, levels, threshold)
        want = expected(pending, enable, levels, threshold)
        check(got == (want, int(want != 0)), f"{got} != {want}")

"""PLIC_GATEWAY: one pending request at a time, masked between claim and complete."""

import random

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import PlicGatewayDut

RANDOM_STEPS = 2000
SEED = 0x6A7E


async def step(
    dut: PlicGatewayDut, source: int = 0, claim: int = 0, complete: int = 0
) -> int:
    """Drive the inputs for one cycle and return the pending bit after the edge.

    Parameters
    ----------
    dut : PlicGatewayDut
        The design under test.
    source : int
        Level of the line.
    claim : int
        Claim pulse.
    complete : int
        Complete pulse.

    Returns
    -------
    int
        The pending output after the clock edge.
    """
    dut.i_source.value = source
    dut.i_claim.value = claim
    dut.i_complete.value = complete
    await bus.cycles(dut, 1)
    return int(dut.o_pending.value)


async def start(dut: PlicGatewayDut) -> None:
    """Reset the gateway with every input low.

    Parameters
    ----------
    dut : PlicGatewayDut
        The design under test.
    """
    dut.i_source.value = 0
    dut.i_claim.value = 0
    dut.i_complete.value = 0
    await bus.hold_reset(dut)


@cocotb.test()
async def test_reset(dut: PlicGatewayDut) -> None:
    """Nothing is pending after reset."""
    await start(dut)
    check(int(dut.o_pending.value) == 0)


@cocotb.test()
async def test_level_to_pending(dut: PlicGatewayDut) -> None:
    """A high line becomes pending, and the pending outlives the line."""
    await start(dut)
    check(await step(dut, source=1) == 1)
    check(await step(dut, source=0) == 1, "pending kept after the line falls")


@cocotb.test()
async def test_claim_clears_and_masks(dut: PlicGatewayDut) -> None:
    """The claim clears the pending, the line stays masked until the complete."""
    await start(dut)
    await step(dut, source=1)
    check(await step(dut, source=1, claim=1) == 0, "claim clears")
    for _ in range(4):
        check(await step(dut, source=1) == 0, "masked in flight")
    check(await step(dut, source=1, complete=1) == 0, "complete cycle")
    check(await step(dut, source=1) == 1, "new request after the complete")


@cocotb.test()
async def test_complete_with_line_low(dut: PlicGatewayDut) -> None:
    """Without the line, the complete leaves nothing pending."""
    await start(dut)
    await step(dut, source=1)
    await step(dut, source=0, claim=1)
    await step(dut, source=0, complete=1)
    check(await step(dut) == 0)
    check(await step(dut, source=1) == 1, "the gateway accepts again")


@cocotb.test()
async def test_complete_without_claim(dut: PlicGatewayDut) -> None:
    """A complete in flight before the claim unmasks, but the pending request stays."""
    await start(dut)
    await step(dut, source=1)
    check(await step(dut, source=0, complete=1) == 1, "pending untouched by a complete")
    check(await step(dut, source=1) == 1, "no duplicate")


@cocotb.test()
async def test_complete_alone_is_harmless(dut: PlicGatewayDut) -> None:
    """A complete on an idle gateway changes nothing."""
    await start(dut)
    check(await step(dut, complete=1) == 0)
    check(await step(dut, source=1, complete=1) == 1, "the line wins over an idle complete")


@cocotb.test()
async def test_random_against_model(dut: PlicGatewayDut) -> None:
    """Random inputs: the pending bit follows the reference."""
    await start(dut)
    rng = random.Random(SEED)
    pending = inflight = False
    for _ in range(RANDOM_STEPS):
        source = int(rng.random() < 0.5)
        claim = int(rng.random() < 0.3)
        complete = int(rng.random() < 0.3)
        old_inflight = inflight
        if claim:
            pending = False
        if complete:
            inflight = False
        if source and not old_inflight:
            pending, inflight = True, True
        seen = await step(dut, source, claim, complete)
        check(seen == int(pending), f"pending {seen} != {int(pending)}")

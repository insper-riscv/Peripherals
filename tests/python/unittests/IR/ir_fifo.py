"""Frame FIFO of the infrared receiver: order, refusal, flush."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.dut import Dut
from tests.python.utils import bus
from tests.python.utils.check import check

DEPTH = 8


def clear_strobes(dut: Dut) -> None:
    """Lower the push, pop and flush requests.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    dut.i_push.value = 0
    dut.i_pop.value = 0
    dut.i_flush.value = 0


async def start(dut: Dut) -> None:
    """Start the clock and reset the FIFO.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    dut.i_push_data.value = 0
    clear_strobes(dut)
    await bus.hold_reset(dut)
    await bus.cycles(dut, 1)
    check(int(dut.o_empty.value) == 1, "empty after reset")


async def step(
    dut: Dut, push: int = 0, data: int = 0, pop: int = 0, flush: int = 0
) -> None:
    """Drive one cycle of the FIFO inputs.

    Parameters
    ----------
    dut : Dut
        The design under test.
    push : int
        Push request.
    data : int
        Word to push.
    pop : int
        Pop request.
    flush : int
        Flush request.
    """
    inputs = {
        "i_push": push,
        "i_push_data": data,
        "i_pop": pop,
        "i_flush": flush,
    }
    for name, value in inputs.items():
        getattr(dut, name).value = value
    await bus.cycles(dut, 1)
    clear_strobes(dut)


@cocotb.test()
async def test_order_and_flags(dut: Dut) -> None:
    """Frames leave in the order they came; flags follow the level."""
    await start(dut)
    check(int(dut.o_pop_data.value) == 0, "empty head is zero")
    for word in range(1, DEPTH + 1):
        await step(dut, push=1, data=word * 0x111)
        check(int(dut.o_level.value) == word, f"level {word}")
    check(int(dut.o_full.value) == 1, "full")
    for word in range(1, DEPTH + 1):
        check(int(dut.o_pop_data.value) == word * 0x111, f"head {word}")
        await step(dut, pop=1)
    check(int(dut.o_empty.value) == 1, "empty again")


@cocotb.test()
async def test_refusal_when_full(dut: Dut) -> None:
    """A push into a full FIFO is refused, even with a pop."""
    await start(dut)
    for word in range(DEPTH):
        await step(dut, push=1, data=word + 1)
    dut.i_push.value = 1
    dut.i_pop.value = 1
    await Timer(1, unit="ns")
    check(int(dut.o_refused.value) == 1, "refused is reported")
    await step(dut, push=1, data=0x77, pop=1)
    check(int(dut.o_level.value) == DEPTH - 1, "only the pop counted")
    for word in range(2, DEPTH + 1):
        check(int(dut.o_pop_data.value) == word, f"kept {word}")
        await step(dut, pop=1)
    check(int(dut.o_empty.value) == 1, "the refused word is not stored")


@cocotb.test()
async def test_flush_and_wrap(dut: Dut) -> None:
    """Flush empties the FIFO and the pointers wrap around."""
    await start(dut)
    for word in range(5):
        await step(dut, push=1, data=word + 1)
    await step(dut, flush=1, push=1, data=0x55)
    check(int(dut.o_empty.value) == 1, "flush wins over push")
    for round_ in range(3 * DEPTH):
        await step(dut, push=1, data=round_ + 1)
        check(int(dut.o_pop_data.value) == round_ + 1, "wrapped head")
        await step(dut, pop=1)

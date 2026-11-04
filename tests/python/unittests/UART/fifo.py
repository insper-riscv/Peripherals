"""Unit tests for the synchronous FIFO used by the UART wrapper."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


DEPTH = 4


async def setup(dut):
    cocotb.start_soon(Clock(dut.clock, 10, unit="ns").start())
    dut.clear.value = 1
    dut.push.value = 0
    dut.pop.value = 0
    dut.push_data.value = 0
    for _ in range(3):
        await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.clear.value = 0
    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")


async def request(dut, *, push=False, value=0, pop=False):
    """Apply one request cycle and return pre-edge acceptance and head data."""
    dut.push.value = int(push)
    dut.push_data.value = value
    dut.pop.value = int(pop)
    await Timer(1, unit="ns")

    result = (
        int(dut.push_accepted.value),
        int(dut.pop_accepted.value),
        int(dut.pop_data.value),
    )

    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.push.value = 0
    dut.pop.value = 0
    return result


async def pop_value(dut):
    push_accepted, pop_accepted, value = await request(dut, pop=True)
    assert push_accepted == 0
    assert pop_accepted == 1
    return value


@cocotb.test()
async def test_reset_and_rejected_empty_pop(dut):
    await setup(dut)

    assert int(dut.empty.value) == 1
    assert int(dut.full.value) == 0
    assert int(dut.level.value) == 0
    assert int(dut.pop_data.value) == 0

    assert await request(dut, pop=True) == (0, 0, 0)
    assert int(dut.empty.value) == 1
    assert int(dut.level.value) == 0


@cocotb.test()
async def test_fill_order_and_rejected_full_push(dut):
    await setup(dut)

    for index in range(DEPTH):
        accepted, popped, _ = await request(dut, push=True, value=0x20 + index)
        assert accepted == 1
        assert popped == 0
        assert int(dut.level.value) == index + 1

    assert int(dut.full.value) == 1
    assert int(dut.empty.value) == 0

    accepted, popped, head = await request(dut, push=True, value=0xFF)
    assert (accepted, popped, head) == (0, 0, 0x20)
    assert int(dut.level.value) == DEPTH

    assert [await pop_value(dut) for _ in range(DEPTH)] == [0x20, 0x21, 0x22, 0x23]
    assert int(dut.empty.value) == 1


@cocotb.test()
async def test_pointer_wraparound_preserves_order(dut):
    await setup(dut)

    for value in (0x10, 0x11, 0x12, 0x13):
        await request(dut, push=True, value=value)

    assert await pop_value(dut) == 0x10
    assert await pop_value(dut) == 0x11

    await request(dut, push=True, value=0x14)
    await request(dut, push=True, value=0x15)

    assert [await pop_value(dut) for _ in range(DEPTH)] == [0x12, 0x13, 0x14, 0x15]


@cocotb.test()
async def test_simultaneous_push_and_pop_boundaries(dut):
    await setup(dut)

    # An empty FIFO does not provide fall-through: the pushed byte remains for
    # the next cycle and the simultaneous pop is rejected.
    accepted, popped, value = await request(dut, push=True, value=0x31, pop=True)
    assert (accepted, popped, value) == (1, 0, 0)
    assert int(dut.level.value) == 1
    assert await pop_value(dut) == 0x31

    for value in (0x40, 0x41, 0x42, 0x43):
        await request(dut, push=True, value=value)

    # At full capacity, an accepted pop releases the slot used by the push.
    accepted, popped, value = await request(dut, push=True, value=0x44, pop=True)
    assert (accepted, popped, value) == (1, 1, 0x40)
    assert int(dut.full.value) == 1
    assert int(dut.level.value) == DEPTH
    assert [await pop_value(dut) for _ in range(DEPTH)] == [0x41, 0x42, 0x43, 0x44]

"""TIMER (32 bits): counting modes, prescaler, PWM, overflow status and interrupt."""

import cocotb

from tests.python.utils import bus

CONFIG, TIMER_LOAD, TIMER_RESET, TOP, DUTY, OVF_STATUS, PWM, PRESCALER = range(8)
START, MODE_SATURATE, PWM_EN, IRQ_EN = 0b0001, 0b0010, 0b0100, 0b1000


async def counts(dut, n):
    return [await bus.read(dut, TIMER_LOAD) for _ in range(n)]


@cocotb.test()
async def test_reset_state(dut):
    await bus.reset(dut)
    assert await bus.read(dut, CONFIG) == 0
    assert await bus.read(dut, TIMER_LOAD) == 0
    assert await bus.read(dut, TOP) == 0xFFFFFFFF, "top resets to all ones"
    assert await bus.read(dut, DUTY) == 0
    assert await bus.read(dut, PRESCALER) == 0
    assert await bus.read(dut, OVF_STATUS) == 0
    assert int(dut.irq.value) == 0


@cocotb.test()
async def test_registers_read_back_what_was_written(dut):
    await bus.reset(dut)
    await bus.write(dut, TOP, 1234)
    await bus.write(dut, DUTY, 77)
    await bus.write(dut, PRESCALER, 9)
    await bus.write(dut, CONFIG, 0b1111)
    assert await bus.read(dut, TOP) == 1234
    assert await bus.read(dut, DUTY) == 77
    assert await bus.read(dut, PRESCALER) == 9
    assert await bus.read(dut, CONFIG) == 0b1111


@cocotb.test()
async def test_stopped_timer_does_not_count(dut):
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    assert await counts(dut, 6) == [0] * 6


@cocotb.test()
async def test_counts_up_to_top_and_wraps(dut):
    """Mode 0: 0..top, then back to 0 (a period of top + 1 cycles)."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    await bus.write(dut, CONFIG, START)
    assert await counts(dut, 14) == [0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1]


@cocotb.test()
async def test_saturates_at_top_in_mode_one(dut):
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    await bus.write(dut, CONFIG, START | MODE_SATURATE)
    assert await counts(dut, 10) == [0, 1, 2, 3, 4, 5, 5, 5, 5, 5]


@cocotb.test()
async def test_reset_and_load_write_the_counter(dut):
    await bus.reset(dut)
    await bus.write(dut, TOP, 100)
    await bus.write(dut, TIMER_LOAD, 40)
    assert await bus.read(dut, TIMER_LOAD) == 40, "a load writes the counter"
    await bus.write(dut, CONFIG, START)
    await bus.cycles(dut, 5)
    assert await bus.read(dut, TIMER_LOAD) > 40, "and it counts on from there"
    await bus.write(dut, CONFIG, 0)
    assert await bus.read(dut, TIMER_LOAD) > 40, "stopped, it holds its value"
    await bus.write(dut, TIMER_RESET, 0)
    assert await bus.read(dut, TIMER_LOAD) == 0, "a reset clears it"


@cocotb.test()
async def test_prescaler_divides_the_count_rate(dut):
    """A prescaler of 3 advances the counter once every 4 cycles."""
    await bus.reset(dut)
    await bus.write(dut, PRESCALER, 3)
    await bus.write(dut, CONFIG, START)
    seq = await counts(dut, 14)
    assert seq == [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3], seq


@cocotb.test()
async def test_pwm_is_high_while_the_counter_is_below_duty(dut):
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    await bus.write(dut, DUTY, 2)
    await bus.write(dut, CONFIG, START | PWM_EN)
    trace = []
    for _ in range(14):
        await bus.cycles(dut, 1)
        trace.append((int(dut.counter.value), str(dut.pwm.value)))
    for counter, pwm in trace:
        assert pwm == ("1" if counter < 2 else "0"), f"counter={counter}: pwm={pwm}"
    assert {c for c, p in trace if p == "1"} == {0, 1}


@cocotb.test()
async def test_pwm_pin_is_released_when_disabled(dut):
    await bus.reset(dut)
    await bus.write(dut, DUTY, 2)
    await bus.write(dut, CONFIG, START)
    await bus.cycles(dut, 3)
    assert str(dut.pwm.value) == "Z"


@cocotb.test()
async def test_overflow_is_a_sticky_status_cleared_by_reading_it(dut):
    await bus.reset(dut)
    await bus.write(dut, TOP, 3)
    await bus.write(dut, CONFIG, START | MODE_SATURATE)
    await bus.cycles(dut, 8)
    assert await bus.read(dut, OVF_STATUS) == 1, "the read returns the pending overflow"
    assert await bus.read(dut, OVF_STATUS) == 0, "and clears it (saturated: no new overflow event)"


@cocotb.test()
async def test_interrupt_needs_the_mask_and_is_cleared_by_reading_the_status(dut):
    await bus.reset(dut)
    await bus.write(dut, TOP, 3)
    await bus.write(dut, CONFIG, START | MODE_SATURATE)
    await bus.cycles(dut, 8)
    assert int(dut.irq.value) == 0, "overflowed, but the interrupt is masked"
    await bus.write(dut, CONFIG, START | MODE_SATURATE | IRQ_EN)
    assert int(dut.irq.value) == 1, "unmasking exposes the pending overflow"
    await bus.read(dut, OVF_STATUS)
    assert int(dut.irq.value) == 0

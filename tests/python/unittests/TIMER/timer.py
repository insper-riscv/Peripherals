"""TIMER (32 bits): modes, prescaler, PWM, overflow status and IRQ."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import TimerDut

(
    CONFIG,
    TIMER_LOAD,
    TIMER_RESET,
    TOP,
    DUTY,
    OVF_STATUS,
    _PWM,
    PRESCALER,
) = range(8)
START, MODE_SATURATE, PWM_EN, IRQ_EN = 0b0001, 0b0010, 0b0100, 0b1000
TOP_RESET = 0xFFFFFFFF
TRACE_CYCLES = 14
TOP_VALUE = 1234
DUTY_VALUE = 77
PRESCALER_VALUE = 9
CONFIG_VALUE = 0b1111
LOAD_VALUE = 40
DUTY_SMALL = 2


async def counts(dut: TimerDut, n: int) -> list[int]:
    """Read the counter on n consecutive cycles.

    Parameters
    ----------
    dut : TimerDut
        The design under test.
    n : int
        Number of reads.

    Returns
    -------
    list[int]
        The values read.
    """
    return [await bus.read(dut, TIMER_LOAD) for _ in range(n)]


@cocotb.test()
async def test_reset_state(dut: TimerDut) -> None:
    """The registers have their reset values."""
    await bus.reset(dut)
    check(await bus.read(dut, CONFIG) == 0)
    check(await bus.read(dut, TIMER_LOAD) == 0)
    check(await bus.read(dut, TOP) == TOP_RESET, "top resets to all ones")
    check(await bus.read(dut, DUTY) == 0)
    check(await bus.read(dut, PRESCALER) == 0)
    check(await bus.read(dut, OVF_STATUS) == 0)
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_registers_read_back_what_was_written(dut: TimerDut) -> None:
    """The registers answer with what was written."""
    await bus.reset(dut)
    await bus.write(dut, TOP, TOP_VALUE)
    await bus.write(dut, DUTY, DUTY_VALUE)
    await bus.write(dut, PRESCALER, PRESCALER_VALUE)
    await bus.write(dut, CONFIG, CONFIG_VALUE)
    check(await bus.read(dut, TOP) == TOP_VALUE)
    check(await bus.read(dut, DUTY) == DUTY_VALUE)
    check(await bus.read(dut, PRESCALER) == PRESCALER_VALUE)
    check(await bus.read(dut, CONFIG) == CONFIG_VALUE)


@cocotb.test()
async def test_stopped_timer_does_not_count(dut: TimerDut) -> None:
    """A timer that was never started stays at zero."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    check(await counts(dut, 6) == [0] * 6)


@cocotb.test()
async def test_counts_up_to_top_and_wraps(dut: TimerDut) -> None:
    """Mode 0 counts 0..top, then back to 0 (top + 1 cycles)."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    await bus.write(dut, CONFIG, START)
    want = [0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1]
    check(await counts(dut, 14) == want)


@cocotb.test()
async def test_saturates_at_top_in_mode_one(dut: TimerDut) -> None:
    """Mode 1 holds the counter at top."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    await bus.write(dut, CONFIG, START | MODE_SATURATE)
    check(await counts(dut, 10) == [0, 1, 2, 3, 4, 5, 5, 5, 5, 5])


@cocotb.test()
async def test_reset_and_load_write_the_counter(dut: TimerDut) -> None:
    """Load and reset write the counter, and stopping holds it."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 100)
    await bus.write(dut, TIMER_LOAD, LOAD_VALUE)
    check(
        await bus.read(dut, TIMER_LOAD) == LOAD_VALUE,
        "a load writes the counter",
    )
    await bus.write(dut, CONFIG, START)
    await bus.cycles(dut, 5)
    check(
        await bus.read(dut, TIMER_LOAD) > LOAD_VALUE, "it counts on from there"
    )
    await bus.write(dut, CONFIG, 0)
    check(await bus.read(dut, TIMER_LOAD) > LOAD_VALUE, "stopped, it holds")
    await bus.write(dut, TIMER_RESET, 0)
    check(await bus.read(dut, TIMER_LOAD) == 0, "a reset clears it")


@cocotb.test()
async def test_prescaler_divides_the_count_rate(dut: TimerDut) -> None:
    """A prescaler of 3 advances the counter once every 4 cycles."""
    await bus.reset(dut)
    await bus.write(dut, PRESCALER, 3)
    await bus.write(dut, CONFIG, START)
    seq = await counts(dut, 14)
    check(seq == [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3], f"{seq}")


@cocotb.test()
async def test_pwm_is_high_while_the_counter_is_below_duty(
    dut: TimerDut,
) -> None:
    """The PWM output is high while the counter is below the duty."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 5)
    await bus.write(dut, DUTY, DUTY_SMALL)
    await bus.write(dut, CONFIG, START | PWM_EN)
    trace: list[tuple[int, str]] = []
    for _ in range(TRACE_CYCLES):
        await bus.cycles(dut, 1)
        trace.append((int(dut.counter.value), str(dut.o_pwm.value)))
    for counter, pwm in trace:
        want = "1" if counter < DUTY_SMALL else "0"
        check(pwm == want, f"counter={counter}: pwm={pwm}")
    check({c for c, p in trace if p == "1"} == {0, 1})


@cocotb.test()
async def test_pwm_pin_is_released_when_disabled(dut: TimerDut) -> None:
    """The PWM pin is high impedance when the PWM is disabled."""
    await bus.reset(dut)
    await bus.write(dut, DUTY, DUTY_SMALL)
    await bus.write(dut, CONFIG, START)
    await bus.cycles(dut, 3)
    check(str(dut.o_pwm.value) == "Z")


@cocotb.test()
async def test_overflow_is_a_sticky_status_cleared_by_reading_it(
    dut: TimerDut,
) -> None:
    """The overflow status stays set until a read clears it."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 3)
    await bus.write(dut, CONFIG, START | MODE_SATURATE)
    await bus.cycles(dut, 8)
    pending = await bus.read(dut, OVF_STATUS)
    check(pending == 1, "the read returns the pending overflow")
    cleared = await bus.read(dut, OVF_STATUS)
    check(cleared == 0, "and clears it (saturated: no new overflow)")


@cocotb.test()
async def test_interrupt_needs_the_mask_and_is_cleared_by_reading(
    dut: TimerDut,
) -> None:
    """The interrupt needs its enable and a status read clears it."""
    await bus.reset(dut)
    await bus.write(dut, TOP, 3)
    await bus.write(dut, CONFIG, START | MODE_SATURATE)
    await bus.cycles(dut, 8)
    check(int(dut.o_irq.value) == 0, "overflowed, but masked")
    await bus.write(dut, CONFIG, START | MODE_SATURATE | IRQ_EN)
    check(int(dut.o_irq.value) == 1, "unmasking exposes the overflow")
    await bus.read(dut, OVF_STATUS)
    check(int(dut.o_irq.value) == 0)

/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_timer.h"
#include <rv32_timer_platform.h>

static volatile uint32_t *timer_reg(rv32_timer_t timer, uintptr_t offset)
{
    return (volatile uint32_t *)(timer.base + offset);
}

rv32_timer_t rv32_timer_new(uintptr_t base)
{
    rv32_timer_t timer = {0};

    if (base != 0 && base % 4 == 0 && base <= UINTPTR_MAX - 28) {
        timer.base = base;
    }

    return timer;
}

bool rv32_timer_valid(rv32_timer_t timer)
{
    return timer.base != 0;
}

static void configure_bit(rv32_timer_t timer, uint32_t bit, bool enabled)
{
    if (!rv32_timer_valid(timer)) {
        return;
    }

    uint32_t value = *timer_reg(timer, 0x00);

    *timer_reg(timer, 0x00) = enabled ? value | bit : value & ~bit;
}

void rv32_timer_start(rv32_timer_t timer)
{
    configure_bit(timer, 1, true);
}

void rv32_timer_stop(rv32_timer_t timer)
{
    configure_bit(timer, 1, false);
}

void rv32_timer_one_shot(rv32_timer_t timer, bool enabled)
{
    configure_bit(timer, 2, enabled);
}

void rv32_timer_irq_enable(rv32_timer_t timer, bool enabled)
{
    configure_bit(timer, 8, enabled);
}

void rv32_timer_pwm_enable(rv32_timer_t timer, bool enabled)
{
    configure_bit(timer, 4, enabled);
}

void rv32_timer_set_top(rv32_timer_t timer, uint32_t top)
{
    if (rv32_timer_valid(timer)) {
        *timer_reg(timer, 0x0c) = top;
    }
}

void rv32_timer_set_duty(rv32_timer_t timer, uint32_t duty)
{
    if (rv32_timer_valid(timer)) {
        *timer_reg(timer, 0x10) = duty;
    }
}

bool rv32_timer_set_divider(rv32_timer_t timer, uint32_t cycles)
{
    if (!rv32_timer_valid(timer) || cycles == 0) {
        return false;
    }

    *timer_reg(timer, 0x1c) = cycles - 1;

    return true;
}

void rv32_timer_load(rv32_timer_t timer, uint32_t ticks)
{
    if (rv32_timer_valid(timer)) {
        *timer_reg(timer, 0x04) = ticks;
    }
}

void rv32_timer_reset(rv32_timer_t timer)
{
    if (rv32_timer_valid(timer)) {
        *timer_reg(timer, 0x08) = 0;
    }
}

uint32_t rv32_timer_count(rv32_timer_t timer)
{
    return rv32_timer_valid(timer) ? *timer_reg(timer, 0x04) : 0;
}

bool rv32_timer_overflow_read_clear(rv32_timer_t timer)
{
    return rv32_timer_valid(timer) && (*timer_reg(timer, 0x14) & 1) != 0;
}

bool rv32_timer_pwm_read(rv32_timer_t timer)
{
    return rv32_timer_valid(timer) && (*timer_reg(timer, 0x18) & 1) != 0;
}

rv32_timer_t rv32_timer_platform_new(void)
{
    return rv32_timer_new(RV32_TIMER_DEFAULT_BASE);
}

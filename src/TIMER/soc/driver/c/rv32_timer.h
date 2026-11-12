/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_TIMER_H
#define RV32_TIMER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uintptr_t base;
} rv32_timer_t;

rv32_timer_t rv32_timer_new(uintptr_t base);
bool rv32_timer_valid(rv32_timer_t timer);
/* Configuration must be serialized against other writers. */
void rv32_timer_start(rv32_timer_t timer);
void rv32_timer_stop(rv32_timer_t timer);
void rv32_timer_one_shot(rv32_timer_t timer, bool enabled);
void rv32_timer_irq_enable(rv32_timer_t timer, bool enabled);
void rv32_timer_pwm_enable(rv32_timer_t timer, bool enabled);
void rv32_timer_set_top(rv32_timer_t timer, uint32_t top);
void rv32_timer_set_duty(rv32_timer_t timer, uint32_t duty);
/* The hardware divider is prescaler + 1; zero cycles is rejected. */
bool rv32_timer_set_divider(rv32_timer_t timer, uint32_t cycles);
void rv32_timer_load(rv32_timer_t timer, uint32_t ticks);
void rv32_timer_reset(rv32_timer_t timer);
uint32_t rv32_timer_count(rv32_timer_t timer);
/* Read-to-clear: consumes the overflow event. */
bool rv32_timer_overflow_read_clear(rv32_timer_t timer);
bool rv32_timer_pwm_read(rv32_timer_t timer);

#endif

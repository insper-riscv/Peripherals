/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_CLINT_H
#define RV32_CLINT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uintptr_t base;
} rv32_clint_t;

rv32_clint_t rv32_clint_new(uintptr_t base);
bool rv32_clint_valid(rv32_clint_t clint);
/* Coherent RV32 high/low/high read of the live 64-bit counter. */
uint64_t rv32_clint_time(rv32_clint_t clint);
/* Safe RV32 low=all-ones/high/low update, without spurious deadlines. */
void rv32_clint_set_deadline(rv32_clint_t clint, uint64_t deadline);
void rv32_clint_software_irq(rv32_clint_t clint, bool pending);
bool rv32_clint_software_irq_pending(rv32_clint_t clint);

/* Generated platform constructor: no application addresses or widths. */
rv32_clint_t rv32_clint_platform_new(void);

#endif

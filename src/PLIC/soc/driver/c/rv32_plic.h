/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_PLIC_H
#define RV32_PLIC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uintptr_t base;
    size_t source_count;
    uint32_t max_priority;
} rv32_plic_t;

/* Source IDs are 1..source_count; zero is reserved. Priority bits are 1..32. */
rv32_plic_t rv32_plic_new(uintptr_t base, size_t source_count, size_t priority_bits);
bool rv32_plic_valid(rv32_plic_t plic);
bool rv32_plic_set_priority(rv32_plic_t plic, size_t source, uint32_t priority);
bool rv32_plic_set_threshold(rv32_plic_t plic, uint32_t threshold);
/* Enable is RMW; serialize against concurrent configuration. */
bool rv32_plic_enable(rv32_plic_t plic, size_t source, bool enabled);
bool rv32_plic_pending(rv32_plic_t plic, size_t source);
/* Claim consumes the winning pending request; zero means no candidate. */
size_t rv32_plic_claim(rv32_plic_t plic);
bool rv32_plic_complete(rv32_plic_t plic, size_t source);

/* Generated platform constructor: no application addresses or widths. */
rv32_plic_t rv32_plic_platform_new(void);

#endif

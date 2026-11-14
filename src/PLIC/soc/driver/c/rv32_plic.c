/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_plic.h"
#include <rv32_plic_platform.h>

static volatile uint32_t *plic_reg(rv32_plic_t plic, uintptr_t offset)
{
    return (volatile uint32_t *)(plic.base + offset);
}

rv32_plic_t rv32_plic_new(uintptr_t base, size_t source_count, size_t priority_bits)
{
    rv32_plic_t plic = {0};

    if (base != 0 && base % 4 == 0 && base <= UINTPTR_MAX - 0x200004 &&
        source_count > 0 && source_count <= 1023 && priority_bits > 0 &&
        priority_bits <= 32) {
        plic.base = base;
        plic.source_count = source_count;
        plic.max_priority = UINT32_MAX >> (32 - priority_bits);
    }

    return plic;
}

bool rv32_plic_valid(rv32_plic_t plic)
{
    return plic.base != 0 && plic.source_count > 0;
}

static bool valid_source(rv32_plic_t plic, size_t source)
{
    return rv32_plic_valid(plic) && source > 0 && source <= plic.source_count;
}

bool rv32_plic_set_priority(rv32_plic_t plic, size_t source, uint32_t priority)
{
    if (!valid_source(plic, source) || priority > plic.max_priority) {
        return false;
    }

    *plic_reg(plic, 4 * source) = priority;

    return true;
}

bool rv32_plic_set_threshold(rv32_plic_t plic, uint32_t threshold)
{
    if (!rv32_plic_valid(plic) || threshold > plic.max_priority) {
        return false;
    }

    *plic_reg(plic, 0x200000) = threshold;

    return true;
}

bool rv32_plic_enable(rv32_plic_t plic, size_t source, bool enabled)
{
    if (!valid_source(plic, source)) {
        return false;
    }

    volatile uint32_t *reg = plic_reg(plic, 0x2000 + 4 * (source / 32));
    uint32_t bit = UINT32_C(1) << (source % 32);
    uint32_t value = *reg;

    *reg = enabled ? value | bit : value & ~bit;

    return true;
}

bool rv32_plic_pending(rv32_plic_t plic, size_t source)
{
    if (!valid_source(plic, source)) {
        return false;
    }

    uint32_t value = *plic_reg(plic, 0x1000 + 4 * (source / 32));

    return (value & (UINT32_C(1) << (source % 32))) != 0;
}

size_t rv32_plic_claim(rv32_plic_t plic)
{
    return rv32_plic_valid(plic) ? *plic_reg(plic, 0x200004) : 0;
}

bool rv32_plic_complete(rv32_plic_t plic, size_t source)
{
    if (!valid_source(plic, source)) {
        return false;
    }

    *plic_reg(plic, 0x200004) = (uint32_t)source;

    return true;
}

rv32_plic_t rv32_plic_platform_new(void)
{
    return rv32_plic_new(RV32_PLIC_DEFAULT_BASE, RV32_PLIC_DEFAULT_SOURCE_COUNT,
                         RV32_PLIC_DEFAULT_PRIORITY_BITS);
}

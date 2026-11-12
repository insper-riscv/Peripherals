/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_clint.h"

static volatile uint32_t *clint_reg(rv32_clint_t clint, uintptr_t offset)
{
    return (volatile uint32_t *)(clint.base + offset);
}

rv32_clint_t rv32_clint_new(uintptr_t base)
{
    rv32_clint_t clint = {0};

    if (base != 0 && base % 4 == 0 && base <= UINTPTR_MAX - 0xbffc) {
        clint.base = base;
    }

    return clint;
}

bool rv32_clint_valid(rv32_clint_t clint)
{
    return clint.base != 0;
}

uint64_t rv32_clint_time(rv32_clint_t clint)
{
    if (!rv32_clint_valid(clint)) {
        return 0;
    }

    uint32_t high;
    uint32_t low;
    uint32_t check;

    do {
        high = *clint_reg(clint, 0xbffc);
        low = *clint_reg(clint, 0xbff8);
        check = *clint_reg(clint, 0xbffc);
    } while (high != check);

    return ((uint64_t)high << 32) | low;
}

void rv32_clint_set_deadline(rv32_clint_t clint, uint64_t deadline)
{
    if (!rv32_clint_valid(clint)) {
        return;
    }

    *clint_reg(clint, 0x4000) = UINT32_MAX;
    *clint_reg(clint, 0x4004) = (uint32_t)(deadline >> 32);
    *clint_reg(clint, 0x4000) = (uint32_t)deadline;
}

void rv32_clint_software_irq(rv32_clint_t clint, bool pending)
{
    if (rv32_clint_valid(clint)) {
        *clint_reg(clint, 0x0000) = pending ? 1 : 0;
    }
}

bool rv32_clint_software_irq_pending(rv32_clint_t clint)
{
    return rv32_clint_valid(clint) && (*clint_reg(clint, 0x0000) & 1) != 0;
}

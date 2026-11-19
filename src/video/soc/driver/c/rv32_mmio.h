/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_DRIVER_MMIO_H
#define RV32_DRIVER_MMIO_H

#include <stdint.h>

/* Test hooks model device side effects. Production always uses volatile MMIO.
 * Serialize read/modify/write operations with interrupts and other writers. */
#ifdef RV32_MMIO_TEST
uint32_t rv32_mmio_read32(uintptr_t address);
void rv32_mmio_write32(uintptr_t address, uint32_t value);
void rv32_mmio_write8(uintptr_t address, uint8_t value);
void rv32_mmio_write16(uintptr_t address, uint16_t value);
#else
static inline uint32_t rv32_mmio_read32(uintptr_t address)
{
    return *(volatile uint32_t *)address;
}

static inline void rv32_mmio_write32(uintptr_t address, uint32_t value)
{
    *(volatile uint32_t *)address = value;
}

static inline void rv32_mmio_write8(uintptr_t address, uint8_t value)
{
    *(volatile uint8_t *)address = value;
}

static inline void rv32_mmio_write16(uintptr_t address, uint16_t value)
{
    *(volatile uint16_t *)address = value;
}
#endif

#endif

/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_flash.h"
#include <rv32_flash_platform.h>

static volatile uint32_t *flash_reg(rv32_flash_t flash, uintptr_t offset)
{
    return (volatile uint32_t *)(flash.base + offset);
}

rv32_flash_t rv32_flash_new(uintptr_t base, size_t page_bytes)
{
    rv32_flash_t flash = {0};

    if (base != 0 && base % 4 == 0 && base <= UINTPTR_MAX - 24 && page_bytes >= 8 &&
        (page_bytes & (page_bytes - 1)) == 0) {
        flash.base = base;
        flash.page_bytes = page_bytes;
    }

    return flash;
}

bool rv32_flash_valid(rv32_flash_t flash)
{
    return flash.base != 0 && flash.page_bytes >= 8;
}

bool rv32_flash_busy(rv32_flash_t flash)
{
    return rv32_flash_valid(flash) && (*flash_reg(flash, 0x08) & 1) != 0;
}

bool rv32_flash_refused(rv32_flash_t flash)
{
    return rv32_flash_valid(flash) && (*flash_reg(flash, 0x08) & 4) != 0;
}

bool rv32_flash_buffer_word(rv32_flash_t flash, size_t word, uint32_t value)
{
    if (!rv32_flash_valid(flash) || word >= flash.page_bytes / 4 ||
        rv32_flash_busy(flash)) {
        return false;
    }

    *flash_reg(flash, 0x0c) = (uint32_t)word;
    *flash_reg(flash, 0x10) = value;

    return true;
}

bool rv32_flash_submit(rv32_flash_t flash, rv32_flash_command_t command,
                       uint32_t byte_address)
{
    if (!rv32_flash_valid(flash) || command < RV32_FLASH_ERASE_SECTOR ||
        command > RV32_FLASH_UNPROTECT_SECTOR || rv32_flash_busy(flash)) {
        return false;
    }

    *flash_reg(flash, 0x04) = byte_address;
    *flash_reg(flash, 0x00) = 1;
    *flash_reg(flash, 0x00) = (uint32_t)command;

    return true;
}

void rv32_flash_irq_configure(rv32_flash_t flash, bool done, bool refused)
{
    if (rv32_flash_valid(flash)) {
        *flash_reg(flash, 0x14) = (done ? 1u : 0u) | (refused ? 2u : 0u);
    }
}

uint32_t rv32_flash_irq_pending(rv32_flash_t flash)
{
    return rv32_flash_valid(flash) ? *flash_reg(flash, 0x18) & 3 : 0;
}

void rv32_flash_irq_acknowledge(rv32_flash_t flash, bool done, bool refused)
{
    if (rv32_flash_valid(flash)) {
        *flash_reg(flash, 0x18) = (done ? 1u : 0u) | (refused ? 2u : 0u);
    }
}

rv32_flash_t rv32_flash_platform_new(void)
{
    return rv32_flash_new(RV32_FLASH_DEFAULT_BASE, RV32_FLASH_DEFAULT_PAGE_BYTES);
}

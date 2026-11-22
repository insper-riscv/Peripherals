/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_lcd.h"
#include "rv32_mmio.h"
#include <rv32_lcd_platform.h>

static const uintptr_t instance_bases[] = RV32_LCD_BASES;
static const size_t instance_count = RV32_LCD_INSTANCE_COUNT;

bool rv32_lcd_valid(rv32_lcd_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 23;
}

size_t rv32_lcd_instance_count(void)
{
    return instance_count;
}

rv32_lcd_t rv32_lcd_new(size_t instance)
{
    rv32_lcd_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_lcd_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_lcd_t device, size_t word)
{
    return rv32_lcd_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_lcd_t device, size_t word, uint32_t value)
{
    if (rv32_lcd_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_lcd_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

bool rv32_lcd_busy(rv32_lcd_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_lcd_initializing(rv32_lcd_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 3)) != 0;
}

uint8_t rv32_lcd_queue_level(rv32_lcd_t device)
{
    return (uint8_t)((read_reg(device, 2) >> 8) & UINT32_C(255));
}

void rv32_lcd_empty_interrupt(rv32_lcd_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_lcd_busy_polling(rv32_lcd_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_lcd_power(rv32_lcd_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_lcd_backlight(rv32_lcd_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_lcd_clear_errors(rv32_lcd_t device)
{
    write_reg(device, 2, UINT32_C(48));
}

bool rv32_lcd_try_command(rv32_lcd_t device, uint8_t value)
{
    if (!rv32_lcd_valid(device) || (read_reg(device, 2) & UINT32_C(2)) != 0) {
        return false;
    }

    write_reg(device, 0, (uint32_t)value);

    return true;
}

bool rv32_lcd_try_write(rv32_lcd_t device, uint8_t value)
{
    if (!rv32_lcd_valid(device) || (read_reg(device, 2) & UINT32_C(2)) != 0) {
        return false;
    }

    write_reg(device, 1, (uint32_t)value);

    return true;
}

bool rv32_lcd_clear(rv32_lcd_t device)
{
    return rv32_lcd_try_command(device, 1);
}

bool rv32_lcd_cursor(rv32_lcd_t device, size_t row, size_t column)
{
    if (row >= 2 || column >= 16) {
        return false;
    }

    return rv32_lcd_try_command(device,
                                (uint8_t)(0x80u | (row == 0 ? 0u : 0x40u) | column));
}

/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_display.h"

static volatile uint32_t *display_reg(rv32_display_t display)
{
    return (volatile uint32_t *)display.base;
}

rv32_display_t rv32_display_new(uintptr_t base, size_t digit_count)
{
    rv32_display_t display = {0};

    if (base != 0 && base % 4 == 0 && digit_count > 0 && digit_count <= 8) {
        display.base = base;
        display.digit_count = digit_count;
    }

    return display;
}

bool rv32_display_valid(rv32_display_t display)
{
    return display.base != 0 && display.digit_count > 0;
}

void rv32_display_write(rv32_display_t display, uint32_t value)
{
    if (rv32_display_valid(display)) {
        uint32_t mask = UINT32_MAX >> (32 - 4 * display.digit_count);

        *display_reg(display) = value & mask;
    }
}

uint32_t rv32_display_read(rv32_display_t display)
{
    return rv32_display_valid(display) ? *display_reg(display) : 0;
}

bool rv32_display_write_digit(rv32_display_t display, size_t digit, uint8_t value)
{
    if (!rv32_display_valid(display) || digit >= display.digit_count || value > 15) {
        return false;
    }

    size_t shift = 4 * digit;
    uint32_t word = rv32_display_read(display);
    uint32_t mask = UINT32_C(15) << shift;

    rv32_display_write(display, (word & ~mask) | ((uint32_t)value << shift));

    return true;
}

bool rv32_display_read_digit(rv32_display_t display, size_t digit, uint8_t *value)
{
    if (!rv32_display_valid(display) || digit >= display.digit_count || value == NULL) {
        return false;
    }

    *value = (uint8_t)((rv32_display_read(display) >> (4 * digit)) & 15);

    return true;
}

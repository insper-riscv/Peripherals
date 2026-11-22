/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_keyboard.h"
#include "rv32_mmio.h"
#include <rv32_keyboard_platform.h>

static const uintptr_t instance_bases[] = RV32_KEYBOARD_BASES;
static const size_t instance_count = RV32_KEYBOARD_INSTANCE_COUNT;

bool rv32_keyboard_valid(rv32_keyboard_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 15;
}

size_t rv32_keyboard_instance_count(void)
{
    return instance_count;
}

rv32_keyboard_t rv32_keyboard_new(size_t instance)
{
    rv32_keyboard_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_keyboard_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_keyboard_t device, size_t word)
{
    return rv32_keyboard_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_keyboard_t device, size_t word, uint32_t value)
{
    if (rv32_keyboard_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_keyboard_t device, size_t word, uint32_t mask,
                       uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

bool rv32_keyboard_try_read(rv32_keyboard_t device, uint8_t *value)
{
    if (value == NULL || (read_reg(device, 1) & UINT32_C(1)) == 0) {
        return false;
    }

    *value = (uint8_t)read_reg(device, 0);

    return true;
}

bool rv32_keyboard_try_command(rv32_keyboard_t device, uint8_t value)
{
    if (!rv32_keyboard_valid(device) || (read_reg(device, 1) & UINT32_C(2)) == 0) {
        return false;
    }

    write_reg(device, 2, (uint32_t)value);

    return true;
}

uint8_t rv32_keyboard_queue_level(rv32_keyboard_t device)
{
    return (uint8_t)((read_reg(device, 1) >> 8) & UINT32_C(255));
}

bool rv32_keyboard_ready(rv32_keyboard_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

void rv32_keyboard_receive_interrupt(rv32_keyboard_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_keyboard_error_interrupt(rv32_keyboard_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_keyboard_clear_errors(rv32_keyboard_t device)
{
    write_reg(device, 1, UINT32_C(44));
}

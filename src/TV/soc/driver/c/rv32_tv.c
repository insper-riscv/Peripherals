/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_tv.h"
#include "rv32_mmio.h"
#include <rv32_tv_platform.h>

static const uintptr_t instance_bases[] = RV32_TV_BASES;
static const size_t instance_count = RV32_TV_INSTANCE_COUNT;

bool rv32_tv_valid(rv32_tv_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 35;
}

size_t rv32_tv_instance_count(void)
{
    return instance_count;
}

rv32_tv_t rv32_tv_new(size_t instance)
{
    rv32_tv_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_tv_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_tv_t device, size_t word)
{
    return rv32_tv_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_tv_t device, size_t word, uint32_t value)
{
    if (rv32_tv_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_tv_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_tv_enable(rv32_tv_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_tv_frame_interrupt(rv32_tv_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_tv_error_interrupt(rv32_tv_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

bool rv32_tv_busy(rv32_tv_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_tv_ready(rv32_tv_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_tv_has_error(rv32_tv_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 2)) != 0;
}

void rv32_tv_clear_events(rv32_tv_t device)
{
    write_reg(device, 1, UINT32_C(6));
}

uint32_t rv32_tv_frame_count(rv32_tv_t device)
{
    return (uint32_t)read_reg(device, 2);
}

uint16_t rv32_tv_width(rv32_tv_t device)
{
    return (uint16_t)(read_reg(device, 5) & UINT32_C(65535));
}

uint16_t rv32_tv_height(rv32_tv_t device)
{
    return (uint16_t)((read_reg(device, 5) >> 16) & UINT32_C(65535));
}

bool rv32_tv_start(rv32_tv_t device)
{
    if (!rv32_tv_valid(device) || rv32_tv_busy(device) ||
        (read_reg(device, 0) & 8u) == 0) {
        return false;
    }

    write_reg(device, 0, (read_reg(device, 0) & 14u) | 1u);

    return true;
}

size_t rv32_tv_word_count(rv32_tv_t device)
{
    return ((size_t)rv32_tv_width(device) * rv32_tv_height(device) + 1u) / 2u;
}

bool rv32_tv_read_words(rv32_tv_t device, size_t first, uint32_t *words, size_t count)
{
    size_t capacity = rv32_tv_word_count(device);

    if (!rv32_tv_valid(device) || words == NULL || rv32_tv_busy(device) ||
        first > capacity || count > capacity - first) {
        return false;
    }

    write_reg(device, 6, (uint32_t)first);

    for (size_t index = 0; index < count; index++) {
        words[index] = read_reg(device, 7);
    }

    return true;
}

bool rv32_tv_set_decimation(rv32_tv_t device, uint8_t x, uint8_t y)
{
    if (!rv32_tv_valid(device) || x == 0 || y == 0 || rv32_tv_busy(device)) {
        return false;
    }

    write_reg(device, 3, x | ((uint32_t)y << 8));

    return true;
}

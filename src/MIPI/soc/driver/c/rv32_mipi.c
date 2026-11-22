/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_mipi.h"
#include "rv32_mmio.h"
#include <rv32_mipi_platform.h>

static const uintptr_t instance_bases[] = RV32_MIPI_BASES;
static const size_t instance_count = RV32_MIPI_INSTANCE_COUNT;

bool rv32_mipi_valid(rv32_mipi_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 39;
}

size_t rv32_mipi_instance_count(void)
{
    return instance_count;
}

rv32_mipi_t rv32_mipi_new(size_t instance)
{
    rv32_mipi_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_mipi_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_mipi_t device, size_t word)
{
    return rv32_mipi_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_mipi_t device, size_t word, uint32_t value)
{
    if (rv32_mipi_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_mipi_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_mipi_enable(rv32_mipi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_mipi_frame_interrupt(rv32_mipi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_mipi_error_interrupt(rv32_mipi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

bool rv32_mipi_busy(rv32_mipi_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_mipi_ready(rv32_mipi_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_mipi_has_error(rv32_mipi_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 2)) != 0;
}

void rv32_mipi_clear_events(rv32_mipi_t device)
{
    write_reg(device, 1, UINT32_C(6));
}

uint32_t rv32_mipi_frame_count(rv32_mipi_t device)
{
    return (uint32_t)read_reg(device, 2);
}

uint16_t rv32_mipi_width(rv32_mipi_t device)
{
    return (uint16_t)(read_reg(device, 4) & UINT32_C(65535));
}

uint16_t rv32_mipi_height(rv32_mipi_t device)
{
    return (uint16_t)((read_reg(device, 4) >> 16) & UINT32_C(65535));
}

bool rv32_mipi_start(rv32_mipi_t device)
{
    if (!rv32_mipi_valid(device) || rv32_mipi_busy(device) ||
        (read_reg(device, 0) & 8u) == 0) {
        return false;
    }

    write_reg(device, 0, (read_reg(device, 0) & 14u) | 1u);

    return true;
}

size_t rv32_mipi_word_count(rv32_mipi_t device)
{
    return ((size_t)rv32_mipi_width(device) * rv32_mipi_height(device) + 3u) / 4u;
}

bool rv32_mipi_read_words(rv32_mipi_t device, size_t first, uint32_t *words,
                          size_t count)
{
    size_t capacity = rv32_mipi_word_count(device);

    if (!rv32_mipi_valid(device) || words == NULL || rv32_mipi_busy(device) ||
        first > capacity || count > capacity - first) {
        return false;
    }

    write_reg(device, 5, (uint32_t)first);

    for (size_t index = 0; index < count; index++) {
        words[index] = read_reg(device, 6);
    }

    return true;
}

bool rv32_mipi_configure(rv32_mipi_t device, uint8_t data_type, uint8_t line_step)
{
    if (!rv32_mipi_valid(device) || data_type < 16 || data_type > 63 ||
        line_step == 0 || rv32_mipi_busy(device)) {
        return false;
    }

    write_reg(device, 3, data_type | ((uint32_t)line_step << 8));

    return true;
}

void rv32_mipi_clear_error_counts(rv32_mipi_t device)
{
    write_reg(device, 8, UINT32_C(0));
}

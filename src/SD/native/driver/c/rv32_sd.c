/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_sd.h"
#include "rv32_mmio.h"
#include <rv32_sd_platform.h>

static const uintptr_t instance_bases[] = RV32_SD_BASES;
static const size_t instance_count = RV32_SD_INSTANCE_COUNT;

bool rv32_sd_valid(rv32_sd_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 51;
}

size_t rv32_sd_instance_count(void)
{
    return instance_count;
}

rv32_sd_t rv32_sd_new(size_t instance)
{
    rv32_sd_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_sd_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_sd_t device, size_t word)
{
    return rv32_sd_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_sd_t device, size_t word, uint32_t value)
{
    if (rv32_sd_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_sd_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

bool rv32_sd_command_busy(rv32_sd_t device)
{
    return (read_reg(device, 6) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_sd_data_busy(rv32_sd_t device)
{
    return (read_reg(device, 6) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_sd_command_done(rv32_sd_t device)
{
    return (read_reg(device, 6) & (UINT32_C(1) << 2)) != 0;
}

bool rv32_sd_data_done(rv32_sd_t device)
{
    return (read_reg(device, 6) & (UINT32_C(1) << 3)) != 0;
}

bool rv32_sd_card_busy(rv32_sd_t device)
{
    return (read_reg(device, 6) & (UINT32_C(1) << 4)) != 0;
}

uint32_t rv32_sd_errors(rv32_sd_t device)
{
    return (uint32_t)read_reg(device, 7);
}

void rv32_sd_clear_events(rv32_sd_t device)
{
    write_reg(device, 6, UINT32_C(12));
}

void rv32_sd_clear_errors(rv32_sd_t device)
{
    write_reg(device, 7, UINT32_C(1023));
}

void rv32_sd_clock_enable(rv32_sd_t device, bool enabled)
{
    update_reg(device, 8, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_sd_wide_bus(rv32_sd_t device, bool enabled)
{
    update_reg(device, 8, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_sd_command_interrupt(rv32_sd_t device, bool enabled)
{
    update_reg(device, 8, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_sd_data_interrupt(rv32_sd_t device, bool enabled)
{
    update_reg(device, 8, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_sd_error_interrupt(rv32_sd_t device, bool enabled)
{
    update_reg(device, 8, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

void rv32_sd_abort(rv32_sd_t device)
{
    write_reg(device, 8, (read_reg(device, 8) & UINT32_C(31)) | (UINT32_C(1) << 8));
}

void rv32_sd_set_divider(rv32_sd_t device, uint16_t value)
{
    write_reg(device, 9, value);
}

bool rv32_sd_set_timeout(rv32_sd_t device, uint32_t clocks)
{
    if (!rv32_sd_valid(device) || clocks == 0 || clocks > 0xFFFFFFu) {
        return false;
    }

    write_reg(device, 10, clocks);

    return true;
}

bool rv32_sd_command(rv32_sd_t device, uint8_t index, uint32_t argument,
                     uint8_t response, bool wait_busy, uint8_t data_direction)
{
    if (!rv32_sd_valid(device) || index > 63 || response > 3 || data_direction > 2 ||
        rv32_sd_command_busy(device) || rv32_sd_data_busy(device)) {
        return false;
    }

    uint32_t value = index | ((uint32_t)response << 6) | ((uint32_t)wait_busy << 8);

    if (data_direction != 0) {
        value |= (1u << 9) | ((uint32_t)(data_direction == 2) << 10);
    }

    write_reg(device, 0, argument);
    write_reg(device, 1, value);

    return true;
}

uint32_t rv32_sd_response0(rv32_sd_t device)
{
    return (uint32_t)read_reg(device, 2);
}

uint32_t rv32_sd_response1(rv32_sd_t device)
{
    return (uint32_t)read_reg(device, 3);
}

uint32_t rv32_sd_response2(rv32_sd_t device)
{
    return (uint32_t)read_reg(device, 4);
}

uint32_t rv32_sd_response3(rv32_sd_t device)
{
    return (uint32_t)read_reg(device, 5);
}

bool rv32_sd_read_buffer(rv32_sd_t device, size_t first, uint32_t *words, size_t count)
{
    if (!rv32_sd_valid(device) || words == NULL || first > 128 || count > 128 - first ||
        rv32_sd_command_busy(device) || rv32_sd_data_busy(device)) {
        return false;
    }

    write_reg(device, 12, (uint32_t)first);

    for (size_t index = 0; index < count; index++) {
        words[index] = read_reg(device, 11);
    }

    return true;
}

bool rv32_sd_write_buffer(rv32_sd_t device, size_t first, const uint32_t *words,
                          size_t count)
{
    if (!rv32_sd_valid(device) || words == NULL || first > 128 || count > 128 - first ||
        rv32_sd_command_busy(device) || rv32_sd_data_busy(device)) {
        return false;
    }

    write_reg(device, 12, (uint32_t)first);

    for (size_t index = 0; index < count; index++) {
        write_reg(device, 11, words[index]);
    }

    return true;
}

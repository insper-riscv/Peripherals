/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_adxl345.h"
#include "rv32_mmio.h"
#include <rv32_adxl345_platform.h>

static const uintptr_t instance_bases[] = RV32_ADXL345_BASES;
static const size_t instance_count = RV32_ADXL345_INSTANCE_COUNT;

bool rv32_adxl345_valid(rv32_adxl345_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 31;
}

size_t rv32_adxl345_instance_count(void)
{
    return instance_count;
}

rv32_adxl345_t rv32_adxl345_new(size_t instance)
{
    rv32_adxl345_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_adxl345_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_adxl345_t device, size_t word)
{
    return rv32_adxl345_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_adxl345_t device, size_t word, uint32_t value)
{
    if (rv32_adxl345_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_adxl345_t device, size_t word, uint32_t mask,
                       uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

int32_t rv32_adxl345_x(rv32_adxl345_t device)
{
    return (int32_t)read_reg(device, 0);
}

int32_t rv32_adxl345_y(rv32_adxl345_t device)
{
    return (int32_t)read_reg(device, 1);
}

int32_t rv32_adxl345_z(rv32_adxl345_t device)
{
    return (int32_t)read_reg(device, 2);
}

bool rv32_adxl345_busy(rv32_adxl345_t device)
{
    return (read_reg(device, 3) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_adxl345_sample_ready(rv32_adxl345_t device)
{
    return (read_reg(device, 3) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_adxl345_valid_sample(rv32_adxl345_t device)
{
    return (read_reg(device, 3) & (UINT32_C(1) << 2)) != 0;
}

bool rv32_adxl345_configured(rv32_adxl345_t device)
{
    return (read_reg(device, 3) & (UINT32_C(1) << 3)) != 0;
}

void rv32_adxl345_clear_events(rv32_adxl345_t device)
{
    write_reg(device, 3, UINT32_C(50));
}

void rv32_adxl345_enable(rv32_adxl345_t device, bool enabled)
{
    update_reg(device, 4, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_adxl345_enable_interrupt(rv32_adxl345_t device, bool enabled)
{
    update_reg(device, 4, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_adxl345_full_resolution(rv32_adxl345_t device, bool enabled)
{
    update_reg(device, 4, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

void rv32_adxl345_interrupt_triggered(rv32_adxl345_t device, bool enabled)
{
    update_reg(device, 4, UINT32_C(32), enabled ? UINT32_C(32) : 0);
}

uint8_t rv32_adxl345_device_id(rv32_adxl345_t device)
{
    return (uint8_t)(read_reg(device, 6) & UINT32_C(255));
}

void rv32_adxl345_set_divider(rv32_adxl345_t device, uint16_t value)
{
    write_reg(device, 7, value);
}

bool rv32_adxl345_set_range(rv32_adxl345_t device, uint8_t value)
{
    if (!rv32_adxl345_valid(device) || value > 3u) {
        return false;
    }

    update_reg(device, 4, UINT32_C(12), (uint32_t)value << 2);

    return true;
}

bool rv32_adxl345_set_rate(rv32_adxl345_t device, uint8_t value)
{
    if (!rv32_adxl345_valid(device) || value > 15u) {
        return false;
    }

    update_reg(device, 4, UINT32_C(3840), (uint32_t)value << 8);

    return true;
}

bool rv32_adxl345_set_period(rv32_adxl345_t device, uint32_t value)
{
    if (!rv32_adxl345_valid(device) || value > 16777215u || value == 0) {
        return false;
    }

    update_reg(device, 5, UINT32_C(16777215), (uint32_t)value << 0);

    return true;
}

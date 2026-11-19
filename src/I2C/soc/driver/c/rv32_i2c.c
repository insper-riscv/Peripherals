/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_i2c.h"
#include "rv32_mmio.h"
#include <rv32_i2c_platform.h>

static const uintptr_t instance_bases[] = RV32_I2C_BASES;
static const size_t instance_count = RV32_I2C_INSTANCE_COUNT;

bool rv32_i2c_valid(rv32_i2c_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 23;
}

size_t rv32_i2c_instance_count(void)
{
    return instance_count;
}

rv32_i2c_t rv32_i2c_new(size_t instance)
{
    rv32_i2c_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_i2c_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_i2c_t device, size_t word)
{
    return rv32_i2c_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_i2c_t device, size_t word, uint32_t value)
{
    if (rv32_i2c_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_i2c_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_i2c_enable(rv32_i2c_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_i2c_done_interrupt(rv32_i2c_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_i2c_error_interrupt(rv32_i2c_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_i2c_abort(rv32_i2c_t device)
{
    write_reg(device, 0, (read_reg(device, 0) & UINT32_C(7)) | (UINT32_C(1) << 3));
}

bool rv32_i2c_busy(rv32_i2c_t device)
{
    return (read_reg(device, 5) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_i2c_bus_active(rv32_i2c_t device)
{
    return (read_reg(device, 5) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_i2c_done(rv32_i2c_t device)
{
    return (read_reg(device, 5) & (UINT32_C(1) << 2)) != 0;
}

bool rv32_i2c_nack(rv32_i2c_t device)
{
    return (read_reg(device, 5) & (UINT32_C(1) << 3)) != 0;
}

bool rv32_i2c_arbitration_lost(rv32_i2c_t device)
{
    return (read_reg(device, 5) & (UINT32_C(1) << 4)) != 0;
}

bool rv32_i2c_rejected(rv32_i2c_t device)
{
    return (read_reg(device, 5) & (UINT32_C(1) << 5)) != 0;
}

void rv32_i2c_clear_events(rv32_i2c_t device)
{
    write_reg(device, 5, UINT32_C(60));
}

bool rv32_i2c_set_divider(rv32_i2c_t device, uint16_t divider)
{
    if (divider < 2 || !rv32_i2c_valid(device)) {
        return false;
    }

    write_reg(device, 1, divider);

    return true;
}

bool rv32_i2c_command(rv32_i2c_t device, uint8_t actions, uint8_t value)
{
    if (!rv32_i2c_valid(device) || (read_reg(device, 0) & 1u) == 0 ||
        rv32_i2c_busy(device) || (actions & 0x0Fu) == 0 || (actions & 0xE0u) != 0 ||
        (actions & 0x0Cu) == 0x0Cu ||
        ((actions & 1u) == 0 && !rv32_i2c_bus_active(device))) {
        return false;
    }

    write_reg(device, 5, 60);
    write_reg(device, 3, value);
    write_reg(device, 2, actions);

    return true;
}

bool rv32_i2c_start_write(rv32_i2c_t device, uint8_t value)
{
    return rv32_i2c_command(device, 9, value);
}

bool rv32_i2c_write_byte(rv32_i2c_t device, uint8_t value)
{
    return rv32_i2c_command(device, 8, value);
}

bool rv32_i2c_write_stop(rv32_i2c_t device, uint8_t value)
{
    return rv32_i2c_command(device, 10, value);
}

bool rv32_i2c_read_ack(rv32_i2c_t device)
{
    return rv32_i2c_command(device, 4, 0);
}

bool rv32_i2c_read_stop(rv32_i2c_t device)
{
    return rv32_i2c_command(device, 22, 0);
}

bool rv32_i2c_stop(rv32_i2c_t device)
{
    return rv32_i2c_command(device, 2, 0);
}

uint8_t rv32_i2c_received_byte(rv32_i2c_t device)
{
    return (uint8_t)read_reg(device, 4);
}

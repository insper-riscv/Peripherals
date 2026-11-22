/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_ir.h"
#include "rv32_mmio.h"
#include <rv32_ir_platform.h>

static const uintptr_t instance_bases[] = RV32_IR_BASES;
static const size_t instance_count = RV32_IR_INSTANCE_COUNT;

bool rv32_ir_valid(rv32_ir_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 19;
}

size_t rv32_ir_instance_count(void)
{
    return instance_count;
}

rv32_ir_t rv32_ir_new(size_t instance)
{
    rv32_ir_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_ir_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_ir_t device, size_t word)
{
    return rv32_ir_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_ir_t device, size_t word, uint32_t value)
{
    if (rv32_ir_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_ir_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_ir_enable(rv32_ir_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_ir_frame_interrupt(rv32_ir_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_ir_error_interrupt(rv32_ir_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_ir_extended_addresses(rv32_ir_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_ir_raw_interrupt(rv32_ir_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

void rv32_ir_flush(rv32_ir_t device)
{
    write_reg(device, 0, (read_reg(device, 0) & UINT32_C(31)) | (UINT32_C(1) << 5));
}

bool rv32_ir_ready(rv32_ir_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

void rv32_ir_clear_events(rv32_ir_t device)
{
    write_reg(device, 1, UINT32_C(44));
}

bool rv32_ir_try_read(rv32_ir_t device, uint32_t *value)
{
    if (value == NULL || (read_reg(device, 1) & UINT32_C(1)) == 0) {
        return false;
    }

    *value = (uint32_t)read_reg(device, 2);

    return true;
}

uint32_t rv32_ir_raw_mark_cycles(rv32_ir_t device)
{
    return (uint32_t)read_reg(device, 3);
}

uint32_t rv32_ir_raw_space_cycles(rv32_ir_t device)
{
    return (uint32_t)read_reg(device, 4);
}

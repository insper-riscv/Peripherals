/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_mouse.h"
#include "rv32_mmio.h"
#include <rv32_mouse_platform.h>

static const uintptr_t instance_bases[] = RV32_MOUSE_BASES;
static const size_t instance_count = RV32_MOUSE_INSTANCE_COUNT;

bool rv32_mouse_valid(rv32_mouse_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 19;
}

size_t rv32_mouse_instance_count(void)
{
    return instance_count;
}

rv32_mouse_t rv32_mouse_new(size_t instance)
{
    rv32_mouse_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_mouse_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_mouse_t device, size_t word)
{
    return rv32_mouse_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_mouse_t device, size_t word, uint32_t value)
{
    if (rv32_mouse_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_mouse_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

uint32_t rv32_mouse_read_status_clear(rv32_mouse_t device)
{
    return (uint32_t)read_reg(device, 0);
}

int32_t rv32_mouse_take_dx(rv32_mouse_t device)
{
    return (int32_t)read_reg(device, 1);
}

int32_t rv32_mouse_take_dy(rv32_mouse_t device)
{
    return (int32_t)read_reg(device, 2);
}

uint8_t rv32_mouse_buttons(rv32_mouse_t device)
{
    return (uint8_t)(read_reg(device, 3) & UINT32_C(7));
}

void rv32_mouse_enable_interrupt(rv32_mouse_t device, bool enabled)
{
    update_reg(device, 4, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_mouse_reinitialize(rv32_mouse_t device)
{
    write_reg(device, 4, (read_reg(device, 4) & UINT32_C(1)) | (UINT32_C(1) << 1));
}

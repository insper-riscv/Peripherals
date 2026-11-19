/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_wifi.h"
#include "rv32_mmio.h"
#include <rv32_wifi_platform.h>

static const uintptr_t instance_bases[] = RV32_WIFI_BASES;
static const size_t instance_count = RV32_WIFI_INSTANCE_COUNT;

bool rv32_wifi_valid(rv32_wifi_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 79;
}

size_t rv32_wifi_instance_count(void)
{
    return instance_count;
}

rv32_wifi_t rv32_wifi_new(size_t instance)
{
    rv32_wifi_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_wifi_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_wifi_t device, size_t word)
{
    return rv32_wifi_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_wifi_t device, size_t word, uint32_t value)
{
    if (rv32_wifi_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_wifi_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_wifi_run(rv32_wifi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_wifi_bootloader_mode(rv32_wifi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_wifi_rise_interrupt(rv32_wifi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_wifi_fall_interrupt(rv32_wifi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

bool rv32_wifi_acknowledge(rv32_wifi_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_wifi_resetting(rv32_wifi_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 3)) != 0;
}

void rv32_wifi_clear_events(rv32_wifi_t device)
{
    write_reg(device, 1, UINT32_C(6));
}

void rv32_wifi_reset_pulse(rv32_wifi_t device)
{
    write_reg(device, 2, UINT32_C(1));
}

bool rv32_wifi_spi_busy(rv32_wifi_t device)
{
    return (read_reg(device, 10) & (UINT32_C(1) << 3)) != 0;
}

bool rv32_wifi_spi_try_read(rv32_wifi_t device, uint8_t *value)
{
    if (value == NULL || (read_reg(device, 10) & UINT32_C(1)) == 0) {
        return false;
    }

    *value = (uint8_t)read_reg(device, 9);

    return true;
}

bool rv32_wifi_spi_try_write(rv32_wifi_t device, uint8_t value)
{
    if (!rv32_wifi_valid(device) || (read_reg(device, 10) & UINT32_C(2)) == 0) {
        return false;
    }

    write_reg(device, 8, (uint32_t)value);

    return true;
}

void rv32_wifi_spi_set_divider(rv32_wifi_t device, uint16_t value)
{
    write_reg(device, 12, value);
}

bool rv32_wifi_spi_select(rv32_wifi_t device, bool selected)
{
    if (!rv32_wifi_valid(device) || rv32_wifi_spi_busy(device)) {
        return false;
    }

    update_reg(device, 11, 1, selected ? 1u : 0u);

    return true;
}

bool rv32_wifi_uart_try_read(rv32_wifi_t device, uint8_t *value)
{
    if (value == NULL || (read_reg(device, 18) & UINT32_C(1)) == 0) {
        return false;
    }

    *value = (uint8_t)read_reg(device, 17);

    return true;
}

bool rv32_wifi_uart_try_write(rv32_wifi_t device, uint8_t value)
{
    if (!rv32_wifi_valid(device) || (read_reg(device, 18) & UINT32_C(2)) == 0) {
        return false;
    }

    write_reg(device, 16, (uint32_t)value);

    return true;
}

void rv32_wifi_spi_clear_events(rv32_wifi_t device)
{
    write_reg(device, 10, UINT32_C(224));
}

void rv32_wifi_uart_clear_errors(rv32_wifi_t device)
{
    write_reg(device, 18, UINT32_C(12));
}

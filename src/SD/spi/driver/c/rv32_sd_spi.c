/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_sd_spi.h"
#include "rv32_mmio.h"
#include <rv32_sd_spi_platform.h>

static const uintptr_t instance_bases[] = RV32_SD_SPI_BASES;
static const size_t instance_count = RV32_SD_SPI_INSTANCE_COUNT;

bool rv32_sd_spi_valid(rv32_sd_spi_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 19;
}

size_t rv32_sd_spi_instance_count(void)
{
    return instance_count;
}

rv32_sd_spi_t rv32_sd_spi_new(size_t instance)
{
    rv32_sd_spi_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_sd_spi_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_sd_spi_t device, size_t word)
{
    return rv32_sd_spi_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_sd_spi_t device, size_t word, uint32_t value)
{
    if (rv32_sd_spi_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_sd_spi_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

bool rv32_sd_spi_busy(rv32_sd_spi_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 3)) != 0;
}

bool rv32_sd_spi_tx_ready(rv32_sd_spi_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_sd_spi_rx_ready(rv32_sd_spi_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 0)) != 0;
}

uint8_t rv32_sd_spi_receive_level(rv32_sd_spi_t device)
{
    return (uint8_t)((read_reg(device, 2) >> 8) & UINT32_C(255));
}

uint8_t rv32_sd_spi_transmit_level(rv32_sd_spi_t device)
{
    return (uint8_t)((read_reg(device, 2) >> 16) & UINT32_C(255));
}

bool rv32_sd_spi_try_read(rv32_sd_spi_t device, uint8_t *value)
{
    if (value == NULL || (read_reg(device, 2) & UINT32_C(1)) == 0) {
        return false;
    }

    *value = (uint8_t)read_reg(device, 1);

    return true;
}

bool rv32_sd_spi_try_write(rv32_sd_spi_t device, uint8_t value)
{
    if (!rv32_sd_spi_valid(device) || (read_reg(device, 2) & UINT32_C(2)) == 0) {
        return false;
    }

    write_reg(device, 0, (uint32_t)value);

    return true;
}

void rv32_sd_spi_clear_events(rv32_sd_spi_t device)
{
    write_reg(device, 2, UINT32_C(224));
}

void rv32_sd_spi_set_divider(rv32_sd_spi_t device, uint16_t value)
{
    write_reg(device, 4, value);
}

void rv32_sd_spi_receive_interrupt(rv32_sd_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_sd_spi_empty_interrupt(rv32_sd_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_sd_spi_done_interrupt(rv32_sd_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_sd_spi_error_interrupt(rv32_sd_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

bool rv32_sd_spi_select(rv32_sd_spi_t device, bool enabled)
{
    if (!rv32_sd_spi_valid(device) || rv32_sd_spi_busy(device)) {
        return false;
    }

    update_reg(device, 3, 1, enabled ? 1u : 0u);

    return true;
}

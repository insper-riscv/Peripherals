/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_spi.h"
#include "rv32_mmio.h"
#include <rv32_spi_platform.h>

static const uintptr_t instance_bases[] = RV32_SPI_BASES;
static const size_t instance_count = RV32_SPI_INSTANCE_COUNT;
static const uint32_t select_count_values[] = RV32_SPI_SELECT_COUNT;
static const uint32_t word_bits_values[] = RV32_SPI_WORD_BITS;

bool rv32_spi_valid(rv32_spi_t device)
{
    return device.base != 0 && device.base % 4 == 0 &&
           device.base <= UINTPTR_MAX - 23 &&
           (device.select_count > 0 && device.select_count <= 64 &&
            device.word_bits > 0 && device.word_bits <= 32);
}

size_t rv32_spi_instance_count(void)
{
    return instance_count;
}

rv32_spi_t rv32_spi_new(size_t instance)
{
    rv32_spi_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
        device.select_count = select_count_values[instance];
        device.word_bits = word_bits_values[instance];
    }

    if (!rv32_spi_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_spi_t device, size_t word)
{
    return rv32_spi_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_spi_t device, size_t word, uint32_t value)
{
    if (rv32_spi_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_spi_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

bool rv32_spi_busy(rv32_spi_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 3)) != 0;
}

bool rv32_spi_tx_ready(rv32_spi_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_spi_rx_ready(rv32_spi_t device)
{
    return (read_reg(device, 2) & (UINT32_C(1) << 0)) != 0;
}

uint8_t rv32_spi_receive_level(rv32_spi_t device)
{
    return (uint8_t)((read_reg(device, 2) >> 8) & UINT32_C(255));
}

uint8_t rv32_spi_transmit_level(rv32_spi_t device)
{
    return (uint8_t)((read_reg(device, 2) >> 16) & UINT32_C(255));
}

bool rv32_spi_try_read(rv32_spi_t device, uint32_t *value)
{
    if (value == NULL || (read_reg(device, 2) & UINT32_C(1)) == 0) {
        return false;
    }

    *value = (uint32_t)read_reg(device, 1);

    return true;
}

bool rv32_spi_try_write(rv32_spi_t device, uint32_t value)
{
    if (!rv32_spi_valid(device) || (read_reg(device, 2) & UINT32_C(2)) == 0) {
        return false;
    }

    write_reg(device, 0, (uint32_t)value);

    return true;
}

bool rv32_spi_try_listen(rv32_spi_t device, uint32_t value)
{
    if (!rv32_spi_valid(device) || (read_reg(device, 2) & UINT32_C(2)) == 0) {
        return false;
    }

    write_reg(device, 5, (uint32_t)value);

    return true;
}

void rv32_spi_clear_events(rv32_spi_t device)
{
    write_reg(device, 2, UINT32_C(224));
}

void rv32_spi_set_divider(rv32_spi_t device, uint16_t value)
{
    write_reg(device, 4, value);
}

void rv32_spi_receive_interrupt(rv32_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_spi_empty_interrupt(rv32_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_spi_done_interrupt(rv32_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_spi_error_interrupt(rv32_spi_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

bool rv32_spi_configure(rv32_spi_t device, uint8_t mode, uint8_t bits, bool lsb_first)
{
    if (!rv32_spi_valid(device) || mode > 3 || bits == 0 || bits > device.word_bits ||
        rv32_spi_busy(device)) {
        return false;
    }

    uint32_t value = ((uint32_t)(mode >> 1) << 5) | ((uint32_t)(mode & 1u) << 6) |
                     ((uint32_t)lsb_first << 7) | ((uint32_t)bits << 8);

    update_reg(device, 3, UINT32_C(0x3FE0), value);

    return true;
}

bool rv32_spi_select(rv32_spi_t device, size_t index, bool asserted)
{
    if (!rv32_spi_valid(device) || index >= device.select_count ||
        rv32_spi_busy(device)) {
        return false;
    }

    update_reg(device, 3, UINT32_C(0x3F0001),
               ((uint32_t)index << 16) | (uint32_t)asserted);

    return true;
}

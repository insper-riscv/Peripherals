/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_adc.h"
#include "rv32_mmio.h"
#include <rv32_adc_platform.h>

static const uintptr_t instance_bases[] = RV32_ADC_BASES;
static const size_t instance_count = RV32_ADC_INSTANCE_COUNT;
static const uint32_t backend_values[] = RV32_ADC_BACKEND;
static const uint32_t channels_values[] = RV32_ADC_CHANNELS;

bool rv32_adc_valid(rv32_adc_t device)
{
    return device.base != 0 && device.base % 4 == 0 &&
           device.base <= UINTPTR_MAX - 43 &&
           (device.backend <= 1 && device.channels > 0 &&
            device.channels <= (device.backend == 1 ? 18u : 8u) &&
            device.base <= UINTPTR_MAX - (device.backend == 1 ? 103u : 43u));
}

size_t rv32_adc_instance_count(void)
{
    return instance_count;
}

rv32_adc_t rv32_adc_new(size_t instance)
{
    rv32_adc_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
        device.backend = backend_values[instance];
        device.channels = channels_values[instance];
    }

    if (!rv32_adc_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_adc_t device, size_t word)
{
    return rv32_adc_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_adc_t device, size_t word, uint32_t value)
{
    if (rv32_adc_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_adc_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

size_t rv32_adc_channel_count(rv32_adc_t device)
{
    return rv32_adc_valid(device) ? device.channels : 0;
}

bool rv32_adc_busy(rv32_adc_t device)
{
    return (read_reg(device, device.backend == 1 ? 3 : 9) & 1u) != 0;
}

bool rv32_adc_done(rv32_adc_t device)
{
    return (read_reg(device, device.backend == 1 ? 3 : 9) & 2u) != 0;
}

void rv32_adc_continuous(rv32_adc_t device, bool enabled)
{
    update_reg(device, device.backend == 1 ? 0 : 8, device.backend == 1 ? 3 : 1,
               enabled ? (device.backend == 1 ? 3 : 1) : 0);
}

void rv32_adc_enable_interrupt(rv32_adc_t device, bool enabled)
{
    uint32_t bit = device.backend == 1 ? 4u : 2u;

    update_reg(device, device.backend == 1 ? 0 : 8, bit, enabled ? bit : 0);
}

bool rv32_adc_start(rv32_adc_t device)
{
    if (!rv32_adc_valid(device) || rv32_adc_busy(device)) {
        return false;
    }

    size_t control = device.backend == 1 ? 0u : 8u;
    uint32_t value = read_reg(device, control);

    write_reg(device, control, device.backend == 1 ? value | 9u : value | 4u);

    return true;
}

void rv32_adc_clear_events(rv32_adc_t device)
{
    write_reg(device, device.backend == 1 ? 3 : 9, device.backend == 1 ? 6 : 2);
}

uint32_t rv32_adc_read_channel(rv32_adc_t device, size_t index)
{
    if (!rv32_adc_valid(device) || index >= device.channels) {
        return 0;
    }

    uint32_t value = read_reg(device, device.backend == 1 ? 8u + index : index);

    if (device.backend == 0 && (read_reg(device, 9) & 4u) != 0) {
        value |= 1u << 12;
    }

    return value & 0x3FFFu;
}

bool rv32_adc_set_mask(rv32_adc_t device, uint32_t mask)
{
    if (!rv32_adc_valid(device) || device.backend != 1 || mask > 0x3FFFFu ||
        rv32_adc_busy(device)) {
        return false;
    }

    write_reg(device, 1, mask);

    return true;
}

bool rv32_adc_set_period(rv32_adc_t device, uint32_t cycles)
{
    if (!rv32_adc_valid(device) || device.backend != 1 || cycles == 0 ||
        rv32_adc_busy(device)) {
        return false;
    }

    write_reg(device, 2, cycles);

    return true;
}

bool rv32_adc_set_serial_divider(rv32_adc_t device, uint16_t divider)
{
    if (!rv32_adc_valid(device) || device.backend != 0 || rv32_adc_busy(device)) {
        return false;
    }

    write_reg(device, 10, divider);

    return true;
}

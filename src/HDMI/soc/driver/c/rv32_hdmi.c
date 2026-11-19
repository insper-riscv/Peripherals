/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_hdmi.h"
#include "rv32_mmio.h"
#include <rv32_hdmi_platform.h>

static const uintptr_t instance_bases[] = RV32_HDMI_BASES;
static const size_t instance_count = RV32_HDMI_INSTANCE_COUNT;
static const uint32_t framebuffer_offset_values[] = RV32_HDMI_FRAMEBUFFER_OFFSET;
static const uint32_t window_bytes_values[] = RV32_HDMI_WINDOW_BYTES;

bool rv32_hdmi_valid(rv32_hdmi_t device)
{
    return device.base != 0 && device.base % 4 == 0 &&
           device.base <= UINTPTR_MAX - 59 &&
           (device.framebuffer_offset >= 2048 &&
            device.window_bytes > device.framebuffer_offset &&
            device.base <= UINTPTR_MAX - device.window_bytes);
}

size_t rv32_hdmi_instance_count(void)
{
    return instance_count;
}

rv32_hdmi_t rv32_hdmi_new(size_t instance)
{
    rv32_hdmi_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
        device.framebuffer_offset = framebuffer_offset_values[instance];
        device.window_bytes = window_bytes_values[instance];
    }

    if (!rv32_hdmi_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_hdmi_t device, size_t word)
{
    return rv32_hdmi_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_hdmi_t device, size_t word, uint32_t value)
{
    if (rv32_hdmi_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_hdmi_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_hdmi_enable(rv32_hdmi_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

bool rv32_hdmi_vertical_sync(rv32_hdmi_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_hdmi_vertical_blank(rv32_hdmi_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 1)) != 0;
}

uint32_t rv32_hdmi_frame_count(rv32_hdmi_t device)
{
    return (uint32_t)read_reg(device, 2);
}

uint16_t rv32_hdmi_width(rv32_hdmi_t device)
{
    return (uint16_t)(read_reg(device, 3) & UINT32_C(65535));
}

uint16_t rv32_hdmi_height(rv32_hdmi_t device)
{
    return (uint16_t)((read_reg(device, 3) >> 16) & UINT32_C(65535));
}

uint8_t rv32_hdmi_pixel_bits(rv32_hdmi_t device)
{
    return (uint8_t)(read_reg(device, 4) & UINT32_C(255));
}

uint8_t rv32_hdmi_channel_bits(rv32_hdmi_t device)
{
    return (uint8_t)((read_reg(device, 4) >> 16) & UINT32_C(255));
}

bool rv32_hdmi_indexed(rv32_hdmi_t device)
{
    return (read_reg(device, 4) & (UINT32_C(1) << 24)) != 0;
}

size_t rv32_hdmi_word_count(rv32_hdmi_t device)
{
    uint32_t bits = rv32_hdmi_pixel_bits(device);
    uint32_t width = rv32_hdmi_width(device);
    uint32_t height = rv32_hdmi_height(device);

    if ((bits != 8 && bits != 16 && bits != 32) || width == 0 || height == 0 ||
        !rv32_hdmi_valid(device)) {
        return 0;
    }

    uint64_t count = (((uint64_t)width * bits + 31u) / 32u) * height;
    size_t capacity = (device.window_bytes - device.framebuffer_offset) / 4u;

    return count <= capacity ? (size_t)count : 0;
}

bool rv32_hdmi_write_word(rv32_hdmi_t device, size_t index, uint32_t value)
{
    if (!rv32_hdmi_valid(device) || index >= rv32_hdmi_word_count(device)) {
        return false;
    }

    rv32_mmio_write32(device.base + device.framebuffer_offset + 4u * index, value);

    return true;
}

bool rv32_hdmi_palette_write(rv32_hdmi_t device, uint8_t index, uint8_t red,
                             uint8_t green, uint8_t blue)
{
    uint8_t bits = rv32_hdmi_channel_bits(device);

    if (!rv32_hdmi_valid(device) || !rv32_hdmi_indexed(device) || bits == 0 ||
        bits > 10) {
        return false;
    }

    uint32_t maximum = (UINT32_C(1) << bits) - 1u;
    uint32_t r = (uint32_t)red * maximum / 255u;
    uint32_t g = (uint32_t)green * maximum / 255u;
    uint32_t b = (uint32_t)blue * maximum / 255u;

    write_reg(device, 256u + index, (r << (2u * bits)) | (g << bits) | b);

    return true;
}

uint32_t rv32_hdmi_mode(rv32_hdmi_t device)
{
    return (uint32_t)read_reg(device, 8);
}

uint32_t rv32_hdmi_pixel_clock_khz(rv32_hdmi_t device)
{
    return (uint32_t)read_reg(device, 14);
}

bool rv32_hdmi_transmitter_interrupt(rv32_hdmi_t device)
{
    return (read_reg(device, 9) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_hdmi_initializing(rv32_hdmi_t device)
{
    return (read_reg(device, 9) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_hdmi_initialized(rv32_hdmi_t device)
{
    return (read_reg(device, 9) & (UINT32_C(1) << 2)) != 0;
}

bool rv32_hdmi_initialization_nack(rv32_hdmi_t device)
{
    return (read_reg(device, 9) & (UINT32_C(1) << 3)) != 0;
}

bool rv32_hdmi_has_initialization(rv32_hdmi_t device)
{
    return (read_reg(device, 9) & (UINT32_C(1) << 4)) != 0;
}

void rv32_hdmi_frame_interrupt(rv32_hdmi_t device, bool enabled)
{
    update_reg(device, 10, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_hdmi_transmitter_irq_enable(rv32_hdmi_t device, bool enabled)
{
    update_reg(device, 10, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_hdmi_clear_events(rv32_hdmi_t device)
{
    write_reg(device, 11, UINT32_C(3));
}

bool rv32_hdmi_restart_initialization(rv32_hdmi_t device)
{
    if (!rv32_hdmi_valid(device) || !rv32_hdmi_has_initialization(device) ||
        rv32_hdmi_initializing(device)) {
        return false;
    }

    write_reg(device, 12, 1);

    return true;
}

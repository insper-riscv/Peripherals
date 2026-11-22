/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_video.h"
#include "rv32_mmio.h"
#include <rv32_video_platform.h>

static const uintptr_t instance_bases[] = RV32_VIDEO_BASES;
static const size_t instance_count = RV32_VIDEO_INSTANCE_COUNT;
static const uint32_t framebuffer_offset_values[] = RV32_VIDEO_FRAMEBUFFER_OFFSET;
static const uint32_t window_bytes_values[] = RV32_VIDEO_WINDOW_BYTES;

bool rv32_video_valid(rv32_video_t device)
{
    return device.base != 0 && device.base % 4 == 0 &&
           device.base <= UINTPTR_MAX - 19 &&
           (device.framebuffer_offset >= 2048 &&
            device.window_bytes > device.framebuffer_offset &&
            device.base <= UINTPTR_MAX - device.window_bytes);
}

size_t rv32_video_instance_count(void)
{
    return instance_count;
}

rv32_video_t rv32_video_new(size_t instance)
{
    rv32_video_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
        device.framebuffer_offset = framebuffer_offset_values[instance];
        device.window_bytes = window_bytes_values[instance];
    }

    if (!rv32_video_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_video_t device, size_t word)
{
    return rv32_video_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_video_t device, size_t word, uint32_t value)
{
    if (rv32_video_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_video_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_video_enable(rv32_video_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

bool rv32_video_vertical_sync(rv32_video_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_video_vertical_blank(rv32_video_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 1)) != 0;
}

uint32_t rv32_video_frame_count(rv32_video_t device)
{
    return (uint32_t)read_reg(device, 2);
}

uint16_t rv32_video_width(rv32_video_t device)
{
    return (uint16_t)(read_reg(device, 3) & UINT32_C(65535));
}

uint16_t rv32_video_height(rv32_video_t device)
{
    return (uint16_t)((read_reg(device, 3) >> 16) & UINT32_C(65535));
}

uint8_t rv32_video_pixel_bits(rv32_video_t device)
{
    return (uint8_t)(read_reg(device, 4) & UINT32_C(255));
}

uint8_t rv32_video_channel_bits(rv32_video_t device)
{
    return (uint8_t)((read_reg(device, 4) >> 16) & UINT32_C(255));
}

bool rv32_video_indexed(rv32_video_t device)
{
    return (read_reg(device, 4) & (UINT32_C(1) << 24)) != 0;
}

size_t rv32_video_word_count(rv32_video_t device)
{
    uint32_t bits = rv32_video_pixel_bits(device);
    uint32_t width = rv32_video_width(device);
    uint32_t height = rv32_video_height(device);

    if ((bits != 8 && bits != 16 && bits != 32) || width == 0 || height == 0 ||
        !rv32_video_valid(device)) {
        return 0;
    }

    uint64_t count = (((uint64_t)width * bits + 31u) / 32u) * height;
    size_t capacity = (device.window_bytes - device.framebuffer_offset) / 4u;

    return count <= capacity ? (size_t)count : 0;
}

bool rv32_video_write_word(rv32_video_t device, size_t index, uint32_t value)
{
    if (!rv32_video_valid(device) || index >= rv32_video_word_count(device)) {
        return false;
    }

    rv32_mmio_write32(device.base + device.framebuffer_offset + 4u * index, value);

    return true;
}

bool rv32_video_palette_write(rv32_video_t device, uint8_t index, uint8_t red,
                              uint8_t green, uint8_t blue)
{
    uint8_t bits = rv32_video_channel_bits(device);

    if (!rv32_video_valid(device) || !rv32_video_indexed(device) || bits == 0 ||
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

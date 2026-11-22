/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_VIDEO_H
#define RV32_VIDEO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_video_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
    uint32_t framebuffer_offset;
    uint32_t window_bytes;
} rv32_video_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_video_t rv32_video_new(size_t instance);
bool rv32_video_valid(rv32_video_t device);
size_t rv32_video_instance_count(void);

/* Enable the framebuffer display; mode timing comes from the hardware profile. */
void rv32_video_enable(rv32_video_t device, bool enabled);

/* Current synchronized vertical-sync level. */
bool rv32_video_vertical_sync(rv32_video_t device);

/* Current synchronized vertical-blank interval. */
bool rv32_video_vertical_blank(rv32_video_t device);

/* Frame counter increments at the start of vertical blanking. */
uint32_t rv32_video_frame_count(rv32_video_t device);

/* Immutable framebuffer width. */
uint16_t rv32_video_width(rv32_video_t device);

/* Immutable framebuffer height. */
uint16_t rv32_video_height(rv32_video_t device);

/* Framebuffer storage bits per pixel. */
uint8_t rv32_video_pixel_bits(rv32_video_t device);

/* Stored bits per color channel. */
uint8_t rv32_video_channel_bits(rv32_video_t device);

/* Whether this hardware provides an indexed palette. */
bool rv32_video_indexed(rv32_video_t device);

/* Frame capacity checked against both immutable geometry and the platform window. */
size_t rv32_video_word_count(rv32_video_t device);

/* Write one numbered framebuffer word; never read back write-only framebuffer memory.
 */
bool rv32_video_write_word(rv32_video_t device, size_t index, uint32_t value);

/* Write a palette entry using eight-bit RGB components scaled to the hardware channel
 * width. */
bool rv32_video_palette_write(rv32_video_t device, uint8_t index, uint8_t red,
                              uint8_t green, uint8_t blue);

#endif

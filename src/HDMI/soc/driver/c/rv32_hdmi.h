/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_HDMI_H
#define RV32_HDMI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_hdmi_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
    uint32_t framebuffer_offset;
    uint32_t window_bytes;
} rv32_hdmi_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_hdmi_t rv32_hdmi_new(size_t instance);
bool rv32_hdmi_valid(rv32_hdmi_t device);
size_t rv32_hdmi_instance_count(void);

/* Enable the framebuffer display; mode timing comes from the hardware profile. */
void rv32_hdmi_enable(rv32_hdmi_t device, bool enabled);

/* Current synchronized vertical-sync level. */
bool rv32_hdmi_vertical_sync(rv32_hdmi_t device);

/* Current synchronized vertical-blank interval. */
bool rv32_hdmi_vertical_blank(rv32_hdmi_t device);

/* Frame counter increments at the start of vertical blanking. */
uint32_t rv32_hdmi_frame_count(rv32_hdmi_t device);

/* Immutable framebuffer width. */
uint16_t rv32_hdmi_width(rv32_hdmi_t device);

/* Immutable framebuffer height. */
uint16_t rv32_hdmi_height(rv32_hdmi_t device);

/* Framebuffer storage bits per pixel. */
uint8_t rv32_hdmi_pixel_bits(rv32_hdmi_t device);

/* Stored bits per color channel. */
uint8_t rv32_hdmi_channel_bits(rv32_hdmi_t device);

/* Whether this hardware provides an indexed palette. */
bool rv32_hdmi_indexed(rv32_hdmi_t device);

/* Frame capacity checked against both immutable geometry and the platform window. */
size_t rv32_hdmi_word_count(rv32_hdmi_t device);

/* Write one numbered framebuffer word; never read back write-only framebuffer memory.
 */
bool rv32_hdmi_write_word(rv32_hdmi_t device, size_t index, uint32_t value);

/* Write a palette entry using eight-bit RGB components scaled to the hardware channel
 * width. */
bool rv32_hdmi_palette_write(rv32_hdmi_t device, uint8_t index, uint8_t red,
                             uint8_t green, uint8_t blue);

/* Read the hardware video mode and sync-polarity information. */
uint32_t rv32_hdmi_mode(rv32_hdmi_t device);

/* Read the declared mode clock; this is not a measured FPGA clock. */
uint32_t rv32_hdmi_pixel_clock_khz(rv32_hdmi_t device);

/* External transmitter interrupt, or HPD for direct TMDS. */
bool rv32_hdmi_transmitter_interrupt(rv32_hdmi_t device);

/* Whether the transmitter initialization sequencer is active. */
bool rv32_hdmi_initializing(rv32_hdmi_t device);

/* Whether the initialization table completed. */
bool rv32_hdmi_initialized(rv32_hdmi_t device);

/* Whether a transmitter table write was not acknowledged. */
bool rv32_hdmi_initialization_nack(rv32_hdmi_t device);

/* Whether this hardware includes a transmitter initialization sequencer. */
bool rv32_hdmi_has_initialization(rv32_hdmi_t device);

/* Enable end-of-frame interrupts. */
void rv32_hdmi_frame_interrupt(rv32_hdmi_t device, bool enabled);

/* Enable external interrupt or hot-plug edge interrupts. */
void rv32_hdmi_transmitter_irq_enable(rv32_hdmi_t device, bool enabled);

/* Clear only frame and transmitter edge interrupt events. */
void rv32_hdmi_clear_events(rv32_hdmi_t device);

/* Restart the platform-provided table; direct TMDS has no external transmitter to
 * initialize. */
bool rv32_hdmi_restart_initialization(rv32_hdmi_t device);

#endif

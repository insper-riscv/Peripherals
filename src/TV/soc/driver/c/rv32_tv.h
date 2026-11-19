/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_TV_H
#define RV32_TV_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_tv_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_tv_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_tv_t rv32_tv_new(size_t instance);
bool rv32_tv_valid(rv32_tv_t device);
size_t rv32_tv_instance_count(void);

/* Release the external receiver reset and enable its clock domain. */
void rv32_tv_enable(rv32_tv_t device, bool enabled);

/* Enable frame-ready interrupts. */
void rv32_tv_frame_interrupt(rv32_tv_t device, bool enabled);

/* Enable receiver-error interrupts. */
void rv32_tv_error_interrupt(rv32_tv_t device, bool enabled);

/* Whether a capture is in progress. */
bool rv32_tv_busy(rv32_tv_t device);

/* Whether a completed frame is available. */
bool rv32_tv_ready(rv32_tv_t device);

/* Whether a capture error is pending. */
bool rv32_tv_has_error(rv32_tv_t device);

/* Acknowledge frame-ready and error flags with W1C writes. */
void rv32_tv_clear_events(rv32_tv_t device);

/* Number of completed frames. */
uint32_t rv32_tv_frame_count(rv32_tv_t device);

/* Frame width (TV pixels or MIPI bytes per line). */
uint16_t rv32_tv_width(rv32_tv_t device);

/* Frame height in lines. */
uint16_t rv32_tv_height(rv32_tv_t device);

/* Request one capture; disabled/busy receiver state can block it. */
bool rv32_tv_start(rv32_tv_t device);

/* Read the immutable frame-memory capacity in 32-bit words. */
size_t rv32_tv_word_count(rv32_tv_t device);

/* Read a bounded frame range while capture is idle; no invented settle delay. */
bool rv32_tv_read_words(rv32_tv_t device, size_t first, uint32_t *words, size_t count);

/* Set nonzero X/Y decimation factors while idle. */
bool rv32_tv_set_decimation(rv32_tv_t device, uint8_t x, uint8_t y);

#endif

/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_MIPI_H
#define RV32_MIPI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_mipi_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_mipi_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_mipi_t rv32_mipi_new(size_t instance);
bool rv32_mipi_valid(rv32_mipi_t device);
size_t rv32_mipi_instance_count(void);

/* Release the external receiver reset and enable its clock domain. */
void rv32_mipi_enable(rv32_mipi_t device, bool enabled);

/* Enable frame-ready interrupts. */
void rv32_mipi_frame_interrupt(rv32_mipi_t device, bool enabled);

/* Enable receiver-error interrupts. */
void rv32_mipi_error_interrupt(rv32_mipi_t device, bool enabled);

/* Whether a capture is in progress. */
bool rv32_mipi_busy(rv32_mipi_t device);

/* Whether a completed frame is available. */
bool rv32_mipi_ready(rv32_mipi_t device);

/* Whether a capture error is pending. */
bool rv32_mipi_has_error(rv32_mipi_t device);

/* Acknowledge frame-ready and error flags with W1C writes. */
void rv32_mipi_clear_events(rv32_mipi_t device);

/* Number of completed frames. */
uint32_t rv32_mipi_frame_count(rv32_mipi_t device);

/* Frame width (TV pixels or MIPI bytes per line). */
uint16_t rv32_mipi_width(rv32_mipi_t device);

/* Frame height in lines. */
uint16_t rv32_mipi_height(rv32_mipi_t device);

/* Request one capture; disabled/busy receiver state can block it. */
bool rv32_mipi_start(rv32_mipi_t device);

/* Read the immutable frame-memory capacity in 32-bit words. */
size_t rv32_mipi_word_count(rv32_mipi_t device);

/* Read a bounded frame range while capture is idle; no invented settle delay. */
bool rv32_mipi_read_words(rv32_mipi_t device, size_t first, uint32_t *words,
                          size_t count);

/* Choose a validated long-packet data type and a nonzero line step while idle. */
bool rv32_mipi_configure(rv32_mipi_t device, uint8_t data_type, uint8_t line_step);

/* Clear saturating ECC/CRC/drop counters with a zero write. */
void rv32_mipi_clear_error_counts(rv32_mipi_t device);

#endif

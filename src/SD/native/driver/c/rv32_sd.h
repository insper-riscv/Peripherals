/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_SD_H
#define RV32_SD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_sd_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_sd_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_sd_t rv32_sd_new(size_t instance);
bool rv32_sd_valid(rv32_sd_t device);
size_t rv32_sd_instance_count(void);

/* Read the current command/data engine state. */
bool rv32_sd_command_busy(rv32_sd_t device);

/* Read the current command/data engine state. */
bool rv32_sd_data_busy(rv32_sd_t device);

/* Read the current command/data engine state. */
bool rv32_sd_command_done(rv32_sd_t device);

/* Read the current command/data engine state. */
bool rv32_sd_data_done(rv32_sd_t device);

/* Read the current command/data engine state. */
bool rv32_sd_card_busy(rv32_sd_t device);

/* Read sticky command and data error flags. */
uint32_t rv32_sd_errors(rv32_sd_t device);

/* Clear only CMD_DONE and DATA_DONE flags (W1C). */
void rv32_sd_clear_events(rv32_sd_t device);

/* Clear only defined command/data error flags (W1C). */
void rv32_sd_clear_errors(rv32_sd_t device);

/* Configure this SD controller option; card negotiation is separate. */
void rv32_sd_clock_enable(rv32_sd_t device, bool enabled);

/* Configure this SD controller option; card negotiation is separate. */
void rv32_sd_wide_bus(rv32_sd_t device, bool enabled);

/* Configure this SD controller option; card negotiation is separate. */
void rv32_sd_command_interrupt(rv32_sd_t device, bool enabled);

/* Configure this SD controller option; card negotiation is separate. */
void rv32_sd_data_interrupt(rv32_sd_t device, bool enabled);

/* Configure this SD controller option; card negotiation is separate. */
void rv32_sd_error_interrupt(rv32_sd_t device, bool enabled);

/* Abort the command/data engine and release the lines. */
void rv32_sd_abort(rv32_sd_t device);

/* Set the SD clock divider for the current negotiation stage. */
void rv32_sd_set_divider(rv32_sd_t device, uint16_t value);

/* Set a validated hardware wait limit in SD clocks. */
bool rv32_sd_set_timeout(rv32_sd_t device, uint32_t clocks);

/* Submit one typed command; no filesystem/card-protocol assumptions are hidden. */
bool rv32_sd_command(rv32_sd_t device, uint8_t index, uint32_t argument,
                     uint8_t response, bool wait_busy, uint8_t data_direction);

/* Read this word of the last response. */
uint32_t rv32_sd_response0(rv32_sd_t device);

/* Read this word of the last response. */
uint32_t rv32_sd_response1(rv32_sd_t device);

/* Read this word of the last response. */
uint32_t rv32_sd_response2(rv32_sd_t device);

/* Read this word of the last response. */
uint32_t rv32_sd_response3(rv32_sd_t device);

/* Access a bounded range of the 128-word block buffer while the engine is idle. */
bool rv32_sd_read_buffer(rv32_sd_t device, size_t first, uint32_t *words, size_t count);

/* Access a bounded range of the 128-word block buffer while the engine is idle. */
bool rv32_sd_write_buffer(rv32_sd_t device, size_t first, const uint32_t *words,
                          size_t count);

#endif

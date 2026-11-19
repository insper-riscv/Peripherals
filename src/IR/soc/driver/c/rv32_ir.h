/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_IR_H
#define RV32_IR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_ir_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_ir_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_ir_t rv32_ir_new(size_t instance);
bool rv32_ir_valid(rv32_ir_t device);
size_t rv32_ir_instance_count(void);

/* Enable reception without flushing pending frames. */
void rv32_ir_enable(rv32_ir_t device, bool enabled);

/* Enable frame-available interrupts. */
void rv32_ir_frame_interrupt(rv32_ir_t device, bool enabled);

/* Enable malformed-frame and overflow interrupts. */
void rv32_ir_error_interrupt(rv32_ir_t device, bool enabled);

/* Accept extended 16-bit NEC addresses. */
void rv32_ir_extended_addresses(rv32_ir_t device, bool enabled);

/* Enable raw timing measurement interrupts. */
void rv32_ir_raw_interrupt(rv32_ir_t device, bool enabled);

/* Discard queued frames without altering enables. */
void rv32_ir_flush(rv32_ir_t device);

/* Whether a complete NEC frame is queued. */
bool rv32_ir_ready(rv32_ir_t device);

/* Clear frame error, overflow and raw-new flags (W1C). */
void rv32_ir_clear_events(rv32_ir_t device);

/* Pop one packed NEC frame; None means the FIFO is empty. */
bool rv32_ir_try_read(rv32_ir_t device, uint32_t *value);

/* Duration of the most recent infrared mark. */
uint32_t rv32_ir_raw_mark_cycles(rv32_ir_t device);

/* Duration of the most recent infrared space. */
uint32_t rv32_ir_raw_space_cycles(rv32_ir_t device);

#endif

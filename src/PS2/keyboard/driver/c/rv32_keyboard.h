/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_KEYBOARD_H
#define RV32_KEYBOARD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_keyboard_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_keyboard_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_keyboard_t rv32_keyboard_new(size_t instance);
bool rv32_keyboard_valid(rv32_keyboard_t device);
size_t rv32_keyboard_instance_count(void);

/* Pop one set-2 scan-code byte; None means no queued byte. */
bool rv32_keyboard_try_read(rv32_keyboard_t device, uint8_t *value);

/* Send a keyboard command only when the transmitter is ready. */
bool rv32_keyboard_try_command(rv32_keyboard_t device, uint8_t value);

/* Queued scan-code bytes. */
uint8_t rv32_keyboard_queue_level(rv32_keyboard_t device);

/* Whether a scan-code byte is available. */
bool rv32_keyboard_ready(rv32_keyboard_t device);

/* Enable scan-code receive interrupts. */
void rv32_keyboard_receive_interrupt(rv32_keyboard_t device, bool enabled);

/* Enable framing and overflow interrupts. */
void rv32_keyboard_error_interrupt(rv32_keyboard_t device, bool enabled);

/* Clear only receive overflow, receive error and dropped command. */
void rv32_keyboard_clear_errors(rv32_keyboard_t device);

#endif

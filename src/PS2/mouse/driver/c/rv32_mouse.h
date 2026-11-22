/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_MOUSE_H
#define RV32_MOUSE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_mouse_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_mouse_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_mouse_t rv32_mouse_new(size_t instance);
bool rv32_mouse_valid(rv32_mouse_t device);
size_t rv32_mouse_instance_count(void);

/* Read mouse status once; clears NEW, OVERFLOW and ERROR flags. */
uint32_t rv32_mouse_read_status_clear(rv32_mouse_t device);

/* Consume the accumulated signed X displacement. */
int32_t rv32_mouse_take_dx(rv32_mouse_t device);

/* Consume the accumulated signed Y displacement. */
int32_t rv32_mouse_take_dy(rv32_mouse_t device);

/* Read left/right/middle button bits without clearing motion. */
uint8_t rv32_mouse_buttons(rv32_mouse_t device);

/* Enable new-packet interrupts; reading status clears the cause. */
void rv32_mouse_enable_interrupt(rv32_mouse_t device, bool enabled);

/* Restart initialization while preserving the interrupt enable. */
void rv32_mouse_reinitialize(rv32_mouse_t device);

#endif

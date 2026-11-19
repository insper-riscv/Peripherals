/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_LCD_H
#define RV32_LCD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_lcd_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_lcd_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_lcd_t rv32_lcd_new(size_t instance);
bool rv32_lcd_valid(rv32_lcd_t device);
size_t rv32_lcd_instance_count(void);

/* Whether initialization or a queued LCD operation is active. */
bool rv32_lcd_busy(rv32_lcd_t device);

/* Whether the hardware initialization is active. */
bool rv32_lcd_initializing(rv32_lcd_t device);

/* Queued commands and data bytes. */
uint8_t rv32_lcd_queue_level(rv32_lcd_t device);

/* Enable queue-empty interrupts. */
void rv32_lcd_empty_interrupt(rv32_lcd_t device, bool enabled);

/* Use the LCD busy line when this backend provides it. */
void rv32_lcd_busy_polling(rv32_lcd_t device, bool enabled);

/* Control the LCD power output. */
void rv32_lcd_power(rv32_lcd_t device, bool enabled);

/* Control the LCD backlight output. */
void rv32_lcd_backlight(rv32_lcd_t device, bool enabled);

/* Clear only dropped-write and timeout flags (W1C). */
void rv32_lcd_clear_errors(rv32_lcd_t device);

/* Queue a controller command without waiting. */
bool rv32_lcd_try_command(rv32_lcd_t device, uint8_t value);

/* Queue one character without waiting. */
bool rv32_lcd_try_write(rv32_lcd_t device, uint8_t value);

/* Queue clear-display; hardware supplies the required execution delay. */
bool rv32_lcd_clear(rv32_lcd_t device);

/* Queue a position validated for the 16-by-2 display. */
bool rv32_lcd_cursor(rv32_lcd_t device, size_t row, size_t column);

#endif

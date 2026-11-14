/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_DISPLAY_H
#define RV32_DISPLAY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uintptr_t base;
    size_t digit_count;
} rv32_display_t;

rv32_display_t rv32_display_new(uintptr_t base, size_t digit_count);

/* Bytes of the register file of one group of the display. */
#define RV32_DISPLAY_GROUP_BYTES 64U

/* Handle for group `group` of a display whose first group starts at `base`;
 * digit_count is the number of digits of the group.
 */
rv32_display_t rv32_display_group_new(uintptr_t base, size_t group,
                                      size_t digit_count);
bool rv32_display_valid(rv32_display_t display);
/* Digit zero is the least-significant nibble; values are 0..15.
 * Digit update uses RMW and must be serialized against other writers/host.
 */
bool rv32_display_write_digit(rv32_display_t display, size_t digit, uint8_t value);
bool rv32_display_read_digit(rv32_display_t display, size_t digit, uint8_t *value);
void rv32_display_write(rv32_display_t display, uint32_t value);
uint32_t rv32_display_read(rv32_display_t display);

/* Generated platform constructor: no application addresses or widths. */
rv32_display_t rv32_display_platform_new(void);

#endif

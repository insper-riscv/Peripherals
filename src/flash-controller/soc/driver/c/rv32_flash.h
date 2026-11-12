/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_FLASH_H
#define RV32_FLASH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uintptr_t base;
    size_t page_bytes;
} rv32_flash_t;

typedef enum {
    RV32_FLASH_ERASE_SECTOR = 2,
    RV32_FLASH_PROGRAM_PAGE = 3,
    RV32_FLASH_PROTECT_SECTOR = 4,
    RV32_FLASH_UNPROTECT_SECTOR = 5
} rv32_flash_command_t;

rv32_flash_t rv32_flash_new(uintptr_t base, size_t page_bytes);
bool rv32_flash_valid(rv32_flash_t flash);
bool rv32_flash_busy(rv32_flash_t flash);
bool rv32_flash_refused(rv32_flash_t flash);
/* Index is a word within a page, not a byte address. Busy writes are rejected.
 * Fill every word before programming; unwritten words retain old buffer data.
 * Use UINT32_MAX for words that must remain unchanged in a partial page.
 */
bool rv32_flash_buffer_word(rv32_flash_t flash, size_t word, uint32_t value);
/* Nonblocking: sends write-enable and command; true means submitted, NOT done.
 * ADDR is a FLASH byte address. Caller serializes all flash commands.
 * Poll busy/refused or use IRQ; execute erase/program code outside that FLASH.
 */
bool rv32_flash_submit(rv32_flash_t flash, rv32_flash_command_t command,
                       uint32_t byte_address);
void rv32_flash_irq_configure(rv32_flash_t flash, bool done, bool refused);
uint32_t rv32_flash_irq_pending(rv32_flash_t flash);
/* W1C, unlike GPIO/TIMER. Each bool selects one event to acknowledge. */
void rv32_flash_irq_acknowledge(rv32_flash_t flash, bool done, bool refused);

#endif

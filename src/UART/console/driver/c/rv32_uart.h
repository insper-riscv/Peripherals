/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_UART_H
#define RV32_UART_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    RV32_UART_SERIAL,
    RV32_UART_JTAG
} rv32_uart_backend_t;

typedef struct {
    uintptr_t base;
    rv32_uart_backend_t backend;
    size_t tx_capacity;
} rv32_uart_t;

/* Backend and TX queue capacity must match the instantiated hardware.
 * Neither can be inferred from the MMIO window size or the slot name.
 */
rv32_uart_t rv32_uart_new(uintptr_t base, rv32_uart_backend_t backend,
                          size_t tx_capacity);
bool rv32_uart_valid(rv32_uart_t uart);
/* Nonblocking operations, one serialized producer/consumer per instance.
 * Readiness polling reads STATUS: on JTAG this also ACKNOWLEDGES dropped TX.
 * Serial error bits are sticky until clear_errors. No hidden waits/delays.
 */
bool rv32_uart_try_write(rv32_uart_t uart, uint8_t byte);
bool rv32_uart_try_read(rv32_uart_t uart, uint8_t *byte);
/* Returns bytes sent, using a total status-poll budget (not microseconds). */
size_t rv32_uart_write(rv32_uart_t uart, const uint8_t *data, size_t length,
                       size_t poll_budget);
/* JTAG: empty host queue. Serial: queue empty AND last stop bit sent. */
bool rv32_uart_tx_idle(rv32_uart_t uart);
void rv32_uart_irq_configure(rv32_uart_t uart, bool receive, bool transmit_empty,
                             bool errors);
/* JTAG read clears the dropped flag. Serial read has no such side effect. */
uint32_t rv32_uart_status_read(rv32_uart_t uart);
/* Serial clears both sticky errors (W1C); JTAG acknowledges by status read. */
void rv32_uart_clear_errors(rv32_uart_t uart);

typedef enum {
    RV32_UART_DEFAULT_INSTANCE,
    RV32_UART_SERIAL_INSTANCE,
    RV32_UART_JTAG_INSTANCE
} rv32_uart_instance_t;

/* Generated platform constructor: no application addresses or widths. */
rv32_uart_t rv32_uart_platform_new(rv32_uart_instance_t instance);

#endif

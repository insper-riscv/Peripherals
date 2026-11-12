/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_uart.h"

static volatile uint32_t *uart_reg(rv32_uart_t uart, uintptr_t offset)
{
    return (volatile uint32_t *)(uart.base + offset);
}

rv32_uart_t rv32_uart_new(uintptr_t base, rv32_uart_backend_t backend,
                          size_t tx_capacity)
{
    rv32_uart_t uart = {0};

    if (base != 0 && base % 4 == 0 && base <= UINTPTR_MAX - 12 &&
        (backend == RV32_UART_SERIAL || backend == RV32_UART_JTAG) && tx_capacity > 0 &&
        tx_capacity <= 255) {
        uart.base = base;
        uart.backend = backend;
        uart.tx_capacity = tx_capacity;
    }

    return uart;
}

bool rv32_uart_valid(rv32_uart_t uart)
{
    return uart.base != 0;
}

uint32_t rv32_uart_status_read(rv32_uart_t uart)
{
    return rv32_uart_valid(uart) ? *uart_reg(uart, 0x08) : 0;
}

bool rv32_uart_try_write(rv32_uart_t uart, uint8_t byte)
{
    if (!rv32_uart_valid(uart)) {
        return false;
    }

    uint32_t status = rv32_uart_status_read(uart);
    bool ready =
        uart.backend == RV32_UART_JTAG ? (status & 0xff) != 0 : (status & 2) != 0;

    if (!ready) {
        return false;
    }

    *uart_reg(uart, 0x00) = byte;

    return true;
}

bool rv32_uart_try_read(rv32_uart_t uart, uint8_t *byte)
{
    if (!rv32_uart_valid(uart) || byte == NULL) {
        return false;
    }

    if (uart.backend == RV32_UART_SERIAL && (rv32_uart_status_read(uart) & 1) == 0) {
        return false;
    }

    uint32_t value = *uart_reg(uart, 0x04);

    if (uart.backend == RV32_UART_JTAG && (value & 0x100) == 0) {
        return false;
    }

    *byte = (uint8_t)value;

    return true;
}

size_t rv32_uart_write(rv32_uart_t uart, const uint8_t *data, size_t length,
                       size_t poll_budget)
{
    if (!rv32_uart_valid(uart) || data == NULL) {
        return 0;
    }

    size_t sent = 0;

    for (size_t poll = 0; poll < poll_budget && sent < length; ++poll) {
        if (rv32_uart_try_write(uart, data[sent])) {
            ++sent;
        }
    }

    return sent;
}

bool rv32_uart_tx_idle(rv32_uart_t uart)
{
    if (!rv32_uart_valid(uart)) {
        return false;
    }

    uint32_t status = rv32_uart_status_read(uart);

    return uart.backend == RV32_UART_JTAG ? (status & 0xff) == uart.tx_capacity
                                          : (status & 0x40) != 0;
}

void rv32_uart_irq_configure(rv32_uart_t uart, bool receive, bool transmit_empty,
                             bool errors)
{
    if (rv32_uart_valid(uart)) {
        *uart_reg(uart, 0x0c) =
            (receive ? 1u : 0u) | (transmit_empty ? 2u : 0u) | (errors ? 4u : 0u);
    }
}

void rv32_uart_clear_errors(rv32_uart_t uart)
{
    if (!rv32_uart_valid(uart)) {
        return;
    }

    if (uart.backend == RV32_UART_SERIAL) {
        *uart_reg(uart, 0x08) = 0x0c;
    } else {
        (void)rv32_uart_status_read(uart);
    }
}

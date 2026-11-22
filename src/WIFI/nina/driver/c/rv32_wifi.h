/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_WIFI_H
#define RV32_WIFI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_wifi_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_wifi_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_wifi_t rv32_wifi_new(size_t instance);
bool rv32_wifi_valid(rv32_wifi_t device);
size_t rv32_wifi_instance_count(void);

/* Release or hold module reset; firmware startup is asynchronous. */
void rv32_wifi_run(rv32_wifi_t device, bool enabled);

/* Drive GPIO0 low for the external firmware bootloader. */
void rv32_wifi_bootloader_mode(rv32_wifi_t device, bool enabled);

/* Enable rising ACK edge interrupts. */
void rv32_wifi_rise_interrupt(rv32_wifi_t device, bool enabled);

/* Enable falling ACK edge interrupts. */
void rv32_wifi_fall_interrupt(rv32_wifi_t device, bool enabled);

/* Read the synchronized module ACK line. */
bool rv32_wifi_acknowledge(rv32_wifi_t device);

/* Whether a timed module reset pulse is active. */
bool rv32_wifi_resetting(rv32_wifi_t device);

/* Clear ACK rising/falling edge flags with W1C writes. */
void rv32_wifi_clear_events(rv32_wifi_t device);

/* Request the hardware-timed reset pulse; no software delay is invented. */
void rv32_wifi_reset_pulse(rv32_wifi_t device);

/* Whether the SPI transport still has pending work. */
bool rv32_wifi_spi_busy(rv32_wifi_t device);

/* Pop one SPI transport byte. */
bool rv32_wifi_spi_try_read(rv32_wifi_t device, uint8_t *value);

/* Queue one SPI transport byte. */
bool rv32_wifi_spi_try_write(rv32_wifi_t device, uint8_t value);

/* Set the SPI half-clock divider. */
void rv32_wifi_spi_set_divider(rv32_wifi_t device, uint16_t value);

/* Change chip select only while the SPI transport is idle. */
bool rv32_wifi_spi_select(rv32_wifi_t device, bool selected);

/* Pop one UART transport byte. */
bool rv32_wifi_uart_try_read(rv32_wifi_t device, uint8_t *value);

/* Queue one UART transport byte. */
bool rv32_wifi_uart_try_write(rv32_wifi_t device, uint8_t value);

/* Clear the SPI transport sticky events (W1C). */
void rv32_wifi_spi_clear_events(rv32_wifi_t device);

/* Clear UART receive-overflow and transmit-drop flags (W1C). */
void rv32_wifi_uart_clear_errors(rv32_wifi_t device);

#endif

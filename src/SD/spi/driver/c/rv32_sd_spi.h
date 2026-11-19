/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_SD_SPI_H
#define RV32_SD_SPI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_sd_spi_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_sd_spi_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_sd_spi_t rv32_sd_spi_new(size_t instance);
bool rv32_sd_spi_valid(rv32_sd_spi_t device);
size_t rv32_sd_spi_instance_count(void);

/* Whether queued or active transfers are still pending. */
bool rv32_sd_spi_busy(rv32_sd_spi_t device);

/* Whether the transmit queue accepts another word. */
bool rv32_sd_spi_tx_ready(rv32_sd_spi_t device);

/* Whether the receive queue contains data. */
bool rv32_sd_spi_rx_ready(rv32_sd_spi_t device);

/* Receive queue occupancy. */
uint8_t rv32_sd_spi_receive_level(rv32_sd_spi_t device);

/* Transmit queue occupancy. */
uint8_t rv32_sd_spi_transmit_level(rv32_sd_spi_t device);

/* Pop one received word, or return no data. */
bool rv32_sd_spi_try_read(rv32_sd_spi_t device, uint8_t *value);

/* Queue one word without waiting. */
bool rv32_sd_spi_try_write(rv32_sd_spi_t device, uint8_t value);

/* Clear only DONE, RX_OVERRUN and TX_DROPPED (W1C). */
void rv32_sd_spi_clear_events(rv32_sd_spi_t device);

/* Set the hardware half-clock divider. */
void rv32_sd_spi_set_divider(rv32_sd_spi_t device, uint16_t value);

/* Enable this interrupt source; CPU interrupt routing is separate. */
void rv32_sd_spi_receive_interrupt(rv32_sd_spi_t device, bool enabled);

/* Enable this interrupt source; CPU interrupt routing is separate. */
void rv32_sd_spi_empty_interrupt(rv32_sd_spi_t device, bool enabled);

/* Enable this interrupt source; CPU interrupt routing is separate. */
void rv32_sd_spi_done_interrupt(rv32_sd_spi_t device, bool enabled);

/* Enable this interrupt source; CPU interrupt routing is separate. */
void rv32_sd_spi_error_interrupt(rv32_sd_spi_t device, bool enabled);

/* Assert the SD chip-select line; wait for idle before changing it. */
bool rv32_sd_spi_select(rv32_sd_spi_t device, bool enabled);

#endif

/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_ETH_H
#define RV32_ETH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_eth_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
    uint32_t tx_words;
    uint32_t rx_words;
} rv32_eth_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_eth_t rv32_eth_new(size_t instance);
bool rv32_eth_valid(rv32_eth_t device);
size_t rv32_eth_instance_count(void);

/* Control this MAC option while serializing configuration changes. */
void rv32_eth_enable_receive(rv32_eth_t device, bool enabled);

/* Control this MAC option while serializing configuration changes. */
void rv32_eth_promiscuous(rv32_eth_t device, bool enabled);

/* Control this MAC option while serializing configuration changes. */
void rv32_eth_broadcast(rv32_eth_t device, bool enabled);

/* Control this MAC option while serializing configuration changes. */
void rv32_eth_multicast(rv32_eth_t device, bool enabled);

/* Control this MAC option while serializing configuration changes. */
void rv32_eth_accept_errors(rv32_eth_t device, bool enabled);

/* Control this MAC option while serializing configuration changes. */
void rv32_eth_hold_phy_reset(rv32_eth_t device, bool enabled);

/* Request a MAC reset; hardware clears registers and queues. */
void rv32_eth_reset(rv32_eth_t device);

/* Read the current hardware state without clearing events. */
bool rv32_eth_tx_busy(rv32_eth_t device);

/* Read the current hardware state without clearing events. */
bool rv32_eth_rx_ready(rv32_eth_t device);

/* Read the current hardware state without clearing events. */
bool rv32_eth_mdio_busy(rv32_eth_t device);

/* Read the current hardware state without clearing events. */
bool rv32_eth_phy_interrupt(rv32_eth_t device);

/* Read the current hardware state without clearing events. */
bool rv32_eth_mdio_no_ack(rv32_eth_t device);

/* Acknowledge RX/TX/error/MDIO events; PHY level is not W1C. */
void rv32_eth_clear_events(rv32_eth_t device);

/* Enable this Ethernet interrupt source. */
void rv32_eth_receive_interrupt(rv32_eth_t device, bool enabled);

/* Enable this Ethernet interrupt source. */
void rv32_eth_transmit_interrupt(rv32_eth_t device, bool enabled);

/* Enable this Ethernet interrupt source. */
void rv32_eth_error_interrupt(rv32_eth_t device, bool enabled);

/* Enable this Ethernet interrupt source. */
void rv32_eth_mdio_interrupt(rv32_eth_t device, bool enabled);

/* Enable this Ethernet interrupt source. */
void rv32_eth_phy_irq_enable(rv32_eth_t device, bool enabled);

/* Read this hardware frame counter without clearing it. */
uint32_t rv32_eth_transmitted_frames(rv32_eth_t device);

/* Read this hardware frame counter without clearing it. */
uint32_t rv32_eth_received_frames(rv32_eth_t device);

/* Read this hardware frame counter without clearing it. */
uint32_t rv32_eth_crc_errors(rv32_eth_t device);

/* Read this hardware frame counter without clearing it. */
uint32_t rv32_eth_phy_errors(rv32_eth_t device);

/* Read this hardware frame counter without clearing it. */
uint32_t rv32_eth_dropped_frames(rv32_eth_t device);

/* Read this hardware frame counter without clearing it. */
uint32_t rv32_eth_filtered_frames(rv32_eth_t device);

/* Length of the ready frame, excluding FCS. */
uint32_t rv32_eth_receive_length(rv32_eth_t device);

/* Result of the last completed MDIO read. */
uint16_t rv32_eth_mdio_data(rv32_eth_t device);

/* Set the six octets in wire order, without host-endian casts. */
void rv32_eth_set_mac(rv32_eth_t device, const uint8_t address[6]);

/* Queue one frame; hardware supplies padding/FCS and does not wait for completion. */
bool rv32_eth_send(rv32_eth_t device, const uint8_t *frame, size_t length);

/* Copy and release a ready frame; a short destination leaves it pending. */
bool rv32_eth_receive(rv32_eth_t device, uint8_t *frame, size_t capacity,
                      size_t *length);

/* Start one Clause-22 MDIO transaction without polling indefinitely. */
bool rv32_eth_mdio_start(rv32_eth_t device, uint8_t phy, uint8_t reg, bool writing,
                         uint16_t value);

#endif

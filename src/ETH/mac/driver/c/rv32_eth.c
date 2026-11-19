/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_eth.h"
#include "rv32_mmio.h"
#include <rv32_eth_platform.h>

static const uintptr_t instance_bases[] = RV32_ETH_BASES;
static const size_t instance_count = RV32_ETH_INSTANCE_COUNT;
static const uint32_t tx_words_values[] = RV32_ETH_TX_WORDS;
static const uint32_t rx_words_values[] = RV32_ETH_RX_WORDS;

bool rv32_eth_valid(rv32_eth_t device)
{
    return device.base != 0 && device.base % 4 == 0 &&
           device.base <= UINTPTR_MAX - 87 &&
           (device.tx_words > 0 && device.tx_words <= 1048576 && device.rx_words > 0 &&
            device.rx_words <= 1048576);
}

size_t rv32_eth_instance_count(void)
{
    return instance_count;
}

rv32_eth_t rv32_eth_new(size_t instance)
{
    rv32_eth_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
        device.tx_words = tx_words_values[instance];
        device.rx_words = rx_words_values[instance];
    }

    if (!rv32_eth_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_eth_t device, size_t word)
{
    return rv32_eth_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_eth_t device, size_t word, uint32_t value)
{
    if (rv32_eth_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_eth_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_eth_enable_receive(rv32_eth_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_eth_promiscuous(rv32_eth_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_eth_broadcast(rv32_eth_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_eth_multicast(rv32_eth_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_eth_accept_errors(rv32_eth_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

void rv32_eth_hold_phy_reset(rv32_eth_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(64), enabled ? UINT32_C(64) : 0);
}

void rv32_eth_reset(rv32_eth_t device)
{
    write_reg(device, 0, (read_reg(device, 0) & UINT32_C(95)) | (UINT32_C(1) << 5));
}

bool rv32_eth_tx_busy(rv32_eth_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_eth_rx_ready(rv32_eth_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_eth_mdio_busy(rv32_eth_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 2)) != 0;
}

bool rv32_eth_phy_interrupt(rv32_eth_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 3)) != 0;
}

bool rv32_eth_mdio_no_ack(rv32_eth_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 4)) != 0;
}

void rv32_eth_clear_events(rv32_eth_t device)
{
    write_reg(device, 2, UINT32_C(15));
}

void rv32_eth_receive_interrupt(rv32_eth_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_eth_transmit_interrupt(rv32_eth_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_eth_error_interrupt(rv32_eth_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_eth_mdio_interrupt(rv32_eth_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_eth_phy_irq_enable(rv32_eth_t device, bool enabled)
{
    update_reg(device, 3, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

uint32_t rv32_eth_transmitted_frames(rv32_eth_t device)
{
    return (uint32_t)read_reg(device, 16);
}

uint32_t rv32_eth_received_frames(rv32_eth_t device)
{
    return (uint32_t)read_reg(device, 17);
}

uint32_t rv32_eth_crc_errors(rv32_eth_t device)
{
    return (uint32_t)read_reg(device, 18);
}

uint32_t rv32_eth_phy_errors(rv32_eth_t device)
{
    return (uint32_t)read_reg(device, 19);
}

uint32_t rv32_eth_dropped_frames(rv32_eth_t device)
{
    return (uint32_t)read_reg(device, 20);
}

uint32_t rv32_eth_filtered_frames(rv32_eth_t device)
{
    return (uint32_t)read_reg(device, 21);
}

uint32_t rv32_eth_receive_length(rv32_eth_t device)
{
    return (uint32_t)read_reg(device, 9);
}

uint16_t rv32_eth_mdio_data(rv32_eth_t device)
{
    return (uint16_t)(read_reg(device, 13) & UINT32_C(65535));
}

void rv32_eth_set_mac(rv32_eth_t device, const uint8_t address[6])
{
    if (address == NULL) {
        return;
    }

    write_reg(device, 4,
              (uint32_t)address[0] | ((uint32_t)address[1] << 8) |
                  ((uint32_t)address[2] << 16) | ((uint32_t)address[3] << 24));
    write_reg(device, 5, (uint32_t)address[4] | ((uint32_t)address[5] << 8));
}

bool rv32_eth_send(rv32_eth_t device, const uint8_t *frame, size_t length)
{
    if (!rv32_eth_valid(device) || frame == NULL || length == 0 ||
        length > (size_t)device.tx_words * 4u || rv32_eth_tx_busy(device)) {
        return false;
    }

    write_reg(device, 7, 2);

    for (size_t offset = 0; offset < length; offset += 4) {
        uint32_t word = 0;

        for (size_t byte = 0; byte < 4 && offset + byte < length; byte++) {
            word |= (uint32_t)frame[offset + byte] << (8u * byte);
        }

        write_reg(device, 8, word);
    }

    write_reg(device, 6, (uint32_t)length);
    write_reg(device, 7, 1);

    return true;
}

bool rv32_eth_receive(rv32_eth_t device, uint8_t *frame, size_t capacity,
                      size_t *length)
{
    if (!rv32_eth_valid(device) || frame == NULL || length == NULL ||
        !rv32_eth_rx_ready(device)) {
        return false;
    }

    size_t size = read_reg(device, 9);

    if (size > capacity || size > (size_t)device.rx_words * 4u) {
        return false;
    }

    write_reg(device, 11, 2);

    for (size_t offset = 0; offset < size; offset += 4) {
        uint32_t word = read_reg(device, 10);

        for (size_t byte = 0; byte < 4 && offset + byte < size; byte++) {
            frame[offset + byte] = (uint8_t)(word >> (8u * byte));
        }
    }

    *length = size;
    write_reg(device, 11, 1);

    return true;
}

bool rv32_eth_mdio_start(rv32_eth_t device, uint8_t phy, uint8_t reg, bool writing,
                         uint16_t value)
{
    if (!rv32_eth_valid(device) || phy > 31 || reg > 31 || rv32_eth_mdio_busy(device)) {
        return false;
    }

    write_reg(device, 13, value);
    write_reg(device, 12,
              (uint32_t)reg | ((uint32_t)phy << 5) | ((uint32_t)writing << 10));

    return true;
}

/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_I2C_H
#define RV32_I2C_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_i2c_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_i2c_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_i2c_t rv32_i2c_new(size_t instance);
bool rv32_i2c_valid(rv32_i2c_t device);
size_t rv32_i2c_instance_count(void);

/* Enable the I2C controller. */
void rv32_i2c_enable(rv32_i2c_t device, bool enabled);

/* Enable command completion interrupts. */
void rv32_i2c_done_interrupt(rv32_i2c_t device, bool enabled);

/* Enable NACK/arbitration/rejection interrupts. */
void rv32_i2c_error_interrupt(rv32_i2c_t device, bool enabled);

/* Abort and release the bus; preserve interrupt enables. */
void rv32_i2c_abort(rv32_i2c_t device);

/* Whether a command is executing. */
bool rv32_i2c_busy(rv32_i2c_t device);

/* Whether a transaction remains open. */
bool rv32_i2c_bus_active(rv32_i2c_t device);

/* Whether the last command completed. */
bool rv32_i2c_done(rv32_i2c_t device);

/* Whether the slave failed to acknowledge. */
bool rv32_i2c_nack(rv32_i2c_t device);

/* Whether arbitration was lost. */
bool rv32_i2c_arbitration_lost(rv32_i2c_t device);

/* Whether hardware rejected a command. */
bool rv32_i2c_rejected(rv32_i2c_t device);

/* Clear only sticky completion/error flags (W1C). */
void rv32_i2c_clear_events(rv32_i2c_t device);

/* Configure a validated I2C clock divider. */
bool rv32_i2c_set_divider(rv32_i2c_t device, uint16_t divider);

/* Submit one valid bus action without waiting. */
bool rv32_i2c_command(rv32_i2c_t device, uint8_t actions, uint8_t value);

/* Queue this I2C bus action; disabled/busy/closed-bus state can block it. */
bool rv32_i2c_start_write(rv32_i2c_t device, uint8_t value);

/* Queue this I2C bus action; disabled/busy/closed-bus state can block it. */
bool rv32_i2c_write_byte(rv32_i2c_t device, uint8_t value);

/* Queue this I2C bus action; disabled/busy/closed-bus state can block it. */
bool rv32_i2c_write_stop(rv32_i2c_t device, uint8_t value);

/* Queue this I2C bus action; disabled/busy/closed-bus state can block it. */
bool rv32_i2c_read_ack(rv32_i2c_t device);

/* Queue this I2C bus action; disabled/busy/closed-bus state can block it. */
bool rv32_i2c_read_stop(rv32_i2c_t device);

/* Queue this I2C bus action; disabled/busy/closed-bus state can block it. */
bool rv32_i2c_stop(rv32_i2c_t device);

/* Read the byte from the last completed read command. */
uint8_t rv32_i2c_received_byte(rv32_i2c_t device);

#endif

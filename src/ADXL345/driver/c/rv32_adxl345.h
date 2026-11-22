/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_ADXL345_H
#define RV32_ADXL345_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_adxl345_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_adxl345_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_adxl345_t rv32_adxl345_new(size_t instance);
bool rv32_adxl345_valid(rv32_adxl345_t device);
size_t rv32_adxl345_instance_count(void);

/* Read the signed raw axis sample; scaling depends on range/resolution. */
int32_t rv32_adxl345_x(rv32_adxl345_t device);

/* Read the signed raw axis sample; scaling depends on range/resolution. */
int32_t rv32_adxl345_y(rv32_adxl345_t device);

/* Read the signed raw axis sample; scaling depends on range/resolution. */
int32_t rv32_adxl345_z(rv32_adxl345_t device);

/* Whether a transaction is active or pending. */
bool rv32_adxl345_busy(rv32_adxl345_t device);

/* Whether a new sample arrived since acknowledgement. */
bool rv32_adxl345_sample_ready(rv32_adxl345_t device);

/* Whether any sample has arrived since reset. */
bool rv32_adxl345_valid_sample(rv32_adxl345_t device);

/* Whether device configuration has completed. */
bool rv32_adxl345_configured(rv32_adxl345_t device);

/* Clear SAMPLE and I2C NACK/arbitration flags without read-modify-write. */
void rv32_adxl345_clear_events(rv32_adxl345_t device);

/* Enable automatic device configuration and sampling. */
void rv32_adxl345_enable(rv32_adxl345_t device, bool enabled);

/* Enable sample-available interrupts. */
void rv32_adxl345_enable_interrupt(rv32_adxl345_t device, bool enabled);

/* Select full-resolution operation on the next configuration. */
void rv32_adxl345_full_resolution(rv32_adxl345_t device, bool enabled);

/* Use the external data-ready line instead of periodic sampling. */
void rv32_adxl345_interrupt_triggered(rv32_adxl345_t device, bool enabled);

/* Read the identifier returned by the chip. */
uint8_t rv32_adxl345_device_id(rv32_adxl345_t device);

/* Set the serial clock divider; I2C hardware clamps values below two. */
void rv32_adxl345_set_divider(rv32_adxl345_t device, uint16_t value);

/* Apply a validated accelerometer configuration value. */
bool rv32_adxl345_set_range(rv32_adxl345_t device, uint8_t value);

/* Apply a validated accelerometer configuration value. */
bool rv32_adxl345_set_rate(rv32_adxl345_t device, uint8_t value);

/* Apply a validated accelerometer configuration value. */
bool rv32_adxl345_set_period(rv32_adxl345_t device, uint32_t value);

#endif

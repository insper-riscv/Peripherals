/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_ADC_H
#define RV32_ADC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_adc_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
    uint32_t backend;
    uint32_t channels;
} rv32_adc_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_adc_t rv32_adc_new(size_t instance);
bool rv32_adc_valid(rv32_adc_t device);
size_t rv32_adc_instance_count(void);

/* Number of channels of this converter backend. */
size_t rv32_adc_channel_count(rv32_adc_t device);

/* Whether a conversion sweep is active. */
bool rv32_adc_busy(rv32_adc_t device);

/* Whether a sweep completed since acknowledgement. */
bool rv32_adc_done(rv32_adc_t device);

/* Enable or stop continuous sweeps; an active conversion completes normally. */
void rv32_adc_continuous(rv32_adc_t device, bool enabled);

/* Enable the backend-specific sweep-done interrupt. */
void rv32_adc_enable_interrupt(rv32_adc_t device, bool enabled);

/* Start one sweep without waiting; busy hardware can block the request. */
bool rv32_adc_start(rv32_adc_t device);

/* Acknowledge only backend-defined W1C completion/error flags. */
void rv32_adc_clear_events(rv32_adc_t device);

/* Read a numbered channel; MAX10 VALID/OVERRUN are consumed by this read. */
uint32_t rv32_adc_read_channel(rv32_adc_t device, size_t index);

/* Select MAX10 scan channels while idle; external converters always scan all eight. */
bool rv32_adc_set_mask(rv32_adc_t device, uint32_t mask);

/* Set the MAX10 continuous-scan period while idle. */
bool rv32_adc_set_period(rv32_adc_t device, uint32_t cycles);

/* Set the external ADC serial divider while idle; unavailable on MAX10. */
bool rv32_adc_set_serial_divider(rv32_adc_t device, uint16_t divider);

#endif

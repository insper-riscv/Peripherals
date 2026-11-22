/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RV32_AUDIO_H
#define RV32_AUDIO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Construct with rv32_audio_new; fields are driver implementation state. */
typedef struct {
    uintptr_t base;
} rv32_audio_t;

/* Instance is a zero-based platform instance, never an MMIO address.
 * Construction performs no MMIO and does not reset or enable hardware. */
rv32_audio_t rv32_audio_new(size_t instance);
bool rv32_audio_valid(rv32_audio_t device);
size_t rv32_audio_instance_count(void);

/* Enable this audio function; codec setup and clock policy remain explicit. */
void rv32_audio_playback(rv32_audio_t device, bool enabled);

/* Enable this audio function; codec setup and clock policy remain explicit. */
void rv32_audio_recording(rv32_audio_t device, bool enabled);

/* Enable this audio function; codec setup and clock policy remain explicit. */
void rv32_audio_transmit_interrupt(rv32_audio_t device, bool enabled);

/* Enable this audio function; codec setup and clock policy remain explicit. */
void rv32_audio_receive_interrupt(rv32_audio_t device, bool enabled);

/* Enable this audio function; codec setup and clock policy remain explicit. */
void rv32_audio_error_interrupt(rv32_audio_t device, bool enabled);

/* Enable this audio function; codec setup and clock policy remain explicit. */
void rv32_audio_clocks(rv32_audio_t device, bool enabled);

/* Enable this audio function; codec setup and clock policy remain explicit. */
void rv32_audio_tone(rv32_audio_t device, bool enabled);

/* Whether the playback queue can accept a sample. */
bool rv32_audio_tx_ready(rv32_audio_t device);

/* Whether the recording queue contains a sample. */
bool rv32_audio_rx_ready(rv32_audio_t device);

/* Queue one signed sample; left and right alternate. */
bool rv32_audio_try_write(rv32_audio_t device, int32_t value);

/* Pop one sign-extended sample from the recording queue. */
bool rv32_audio_try_read(rv32_audio_t device, int32_t *value);

/* Clear only playback underflow, recording overflow and dropped write. */
void rv32_audio_clear_errors(rv32_audio_t device);

/* Read hardware-reported playback capacity. */
uint16_t rv32_audio_playback_depth(rv32_audio_t device);

/* Read hardware-reported recording capacity. */
uint16_t rv32_audio_recording_depth(rv32_audio_t device);

/* Configure the master-clock accumulator with clocks disabled. */
void rv32_audio_set_xck_step(rv32_audio_t device, uint32_t value);

/* Configure the master-clock accumulator with clocks disabled. */
void rv32_audio_set_xck_modulus(rv32_audio_t device, uint32_t value);

/* Configure this audio parameter with playback/clocks stopped. */
void rv32_audio_set_bit_divider(rv32_audio_t device, uint16_t value);

/* Configure this audio parameter with playback/clocks stopped. */
void rv32_audio_set_slot_bits(rv32_audio_t device, uint16_t value);

/* Configure this audio parameter with playback/clocks stopped. */
void rv32_audio_set_tone_half_period(rv32_audio_t device, uint16_t value);

/* Configure this audio parameter with playback/clocks stopped. */
void rv32_audio_set_tone_amplitude(rv32_audio_t device, uint16_t value);

/* Select a typed sample width; hardware state changes should be serialized. */
bool rv32_audio_set_sample_width(rv32_audio_t device, uint8_t code);

#endif

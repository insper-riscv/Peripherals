/* SPDX-License-Identifier: Apache-2.0 */
#include "rv32_audio.h"
#include "rv32_mmio.h"
#include <rv32_audio_platform.h>

static const uintptr_t instance_bases[] = RV32_AUDIO_BASES;
static const size_t instance_count = RV32_AUDIO_INSTANCE_COUNT;

bool rv32_audio_valid(rv32_audio_t device)
{
    return device.base != 0 && device.base % 4 == 0 && device.base <= UINTPTR_MAX - 55;
}

size_t rv32_audio_instance_count(void)
{
    return instance_count;
}

rv32_audio_t rv32_audio_new(size_t instance)
{
    rv32_audio_t device = {0};

    if (instance < instance_count) {
        device.base = instance_bases[instance];
    }

    if (!rv32_audio_valid(device)) {
        device.base = 0;
    }

    return device;
}

static uint32_t read_reg(rv32_audio_t device, size_t word)
{
    return rv32_audio_valid(device) ? rv32_mmio_read32(device.base + word * 4u) : 0;
}

static void write_reg(rv32_audio_t device, size_t word, uint32_t value)
{
    if (rv32_audio_valid(device)) {
        rv32_mmio_write32(device.base + word * 4u, value);
    }
}

static void update_reg(rv32_audio_t device, size_t word, uint32_t mask, uint32_t value)
{
    write_reg(device, word, (read_reg(device, word) & ~mask) | (value & mask));
}

void rv32_audio_playback(rv32_audio_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(1), enabled ? UINT32_C(1) : 0);
}

void rv32_audio_recording(rv32_audio_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(2), enabled ? UINT32_C(2) : 0);
}

void rv32_audio_transmit_interrupt(rv32_audio_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(4), enabled ? UINT32_C(4) : 0);
}

void rv32_audio_receive_interrupt(rv32_audio_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(8), enabled ? UINT32_C(8) : 0);
}

void rv32_audio_error_interrupt(rv32_audio_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(16), enabled ? UINT32_C(16) : 0);
}

void rv32_audio_clocks(rv32_audio_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(32), enabled ? UINT32_C(32) : 0);
}

void rv32_audio_tone(rv32_audio_t device, bool enabled)
{
    update_reg(device, 0, UINT32_C(64), enabled ? UINT32_C(64) : 0);
}

bool rv32_audio_tx_ready(rv32_audio_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 0)) != 0;
}

bool rv32_audio_rx_ready(rv32_audio_t device)
{
    return (read_reg(device, 1) & (UINT32_C(1) << 1)) != 0;
}

bool rv32_audio_try_write(rv32_audio_t device, int32_t value)
{
    if (!rv32_audio_valid(device) || (read_reg(device, 1) & UINT32_C(1)) == 0) {
        return false;
    }

    write_reg(device, 3, (uint32_t)value);

    return true;
}

bool rv32_audio_try_read(rv32_audio_t device, int32_t *value)
{
    if (value == NULL || (read_reg(device, 1) & UINT32_C(2)) == 0) {
        return false;
    }

    *value = (int32_t)read_reg(device, 4);

    return true;
}

void rv32_audio_clear_errors(rv32_audio_t device)
{
    write_reg(device, 1, UINT32_C(112));
}

uint16_t rv32_audio_playback_depth(rv32_audio_t device)
{
    return (uint16_t)(read_reg(device, 12) & UINT32_C(65535));
}

uint16_t rv32_audio_recording_depth(rv32_audio_t device)
{
    return (uint16_t)((read_reg(device, 12) >> 16) & UINT32_C(65535));
}

void rv32_audio_set_xck_step(rv32_audio_t device, uint32_t value)
{
    write_reg(device, 6, value);
}

void rv32_audio_set_xck_modulus(rv32_audio_t device, uint32_t value)
{
    write_reg(device, 7, value);
}

void rv32_audio_set_bit_divider(rv32_audio_t device, uint16_t value)
{
    write_reg(device, 8, value);
}

void rv32_audio_set_slot_bits(rv32_audio_t device, uint16_t value)
{
    write_reg(device, 9, value);
}

void rv32_audio_set_tone_half_period(rv32_audio_t device, uint16_t value)
{
    write_reg(device, 10, value);
}

void rv32_audio_set_tone_amplitude(rv32_audio_t device, uint16_t value)
{
    write_reg(device, 11, value);
}

bool rv32_audio_set_sample_width(rv32_audio_t device, uint8_t code)
{
    if (code > 2 || !rv32_audio_valid(device)) {
        return false;
    }

    update_reg(device, 0, 0x300, (uint32_t)code << 8);

    return true;
}

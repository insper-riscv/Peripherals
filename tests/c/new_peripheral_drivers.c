/* SPDX-License-Identifier: Apache-2.0
 * Independent bus-side models for FIFO/read-clear/W1C/pointer behavior.
 * RTL entity tests separately verify the real devices and pin protocols. */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "rv32_spi.h"
#include "rv32_sd_spi.h"
#include "rv32_i2c.h"
#include "rv32_ir.h"
#include "rv32_lcd.h"
#include "rv32_keyboard.h"
#include "rv32_mouse.h"
#include "rv32_audio.h"
#include "rv32_adxl345.h"
#include "rv32_adc.h"
#include "rv32_eth.h"
#include "rv32_tv.h"
#include "rv32_mipi.h"
#include "rv32_sd.h"
#include "rv32_video.h"
#include "rv32_hdmi.h"
#include "rv32_wifi.h"

enum {
    SLOT_SPI = 0,
    SLOT_SD_SPI = 1,
    SLOT_I2C = 2,
    SLOT_IR = 3,
    SLOT_LCD = 4,
    SLOT_KEYBOARD = 5,
    SLOT_MOUSE = 6,
    SLOT_AUDIO = 7,
    SLOT_ADXL345 = 8,
    SLOT_ADC = 9,
    SLOT_ETH = 10,
    SLOT_TV = 11,
    SLOT_MIPI = 12,
    SLOT_SD = 13,
    SLOT_VIDEO = 14,
    SLOT_HDMI = 15,
    SLOT_WIFI = 16,
    SLOT_MAX10 = 17,
    SLOT_COUNT = 18,
    WORDS = 65536
};

static uint32_t registers[SLOT_COUNT][WORDS];
static uint32_t sd_buffer[128];
static uint32_t eth_sent[8];
static uint32_t eth_received[2] = {0x04030201u, 0x08070605u};
static size_t eth_sent_count;
static size_t eth_received_index;
static size_t reads;
static size_t writes;
static uintptr_t last_address;
static uint32_t last_value;

static size_t slot_of(uintptr_t address)
{
    assert(address >= 0x10000000u);

    size_t slot = (address - 0x10000000u) / 0x100000u;

    assert(slot < SLOT_COUNT);

    return slot;
}

static size_t word_of(uintptr_t address)
{
    assert(address % 4u == 0);

    size_t word = (address & 0xFFFFFu) / 4u;

    assert(word < WORDS);

    return word;
}

uint32_t rv32_mmio_read32(uintptr_t address);
void rv32_mmio_write32(uintptr_t address, uint32_t value);
void rv32_mmio_write8(uintptr_t address, uint8_t value);
void rv32_mmio_write16(uintptr_t address, uint16_t value);

uint32_t rv32_mmio_read32(uintptr_t address)
{
    size_t slot = slot_of(address);
    size_t word = word_of(address);
    uint32_t value = registers[slot][word];

    reads++;

    if (slot == SLOT_VIDEO || slot == SLOT_HDMI) {
        assert(word < 512); /* Framebuffers and palettes are write-only. */
    }

    if (slot == SLOT_MOUSE && word < 3) {
        registers[slot][word] = word == 0 ? value & ~7u : 0;
    }

    if (slot == SLOT_MAX10 && word >= 8 && word < 26) {
        registers[slot][word] &= ~0x3000u;
    }

    if ((slot == SLOT_KEYBOARD && word == 0) || (slot == SLOT_IR && word == 2)) {
        registers[slot][1] &= ~1u;
    }

    if ((slot == SLOT_SPI || slot == SLOT_SD_SPI) && word == 1) {
        registers[slot][2] &= ~1u;
    }

    if (slot == SLOT_ETH && word == 10) {
        assert(eth_received_index < 2);
        value = eth_received[eth_received_index++];
    }

    if (slot == SLOT_SD && word == 11) {
        value = sd_buffer[registers[slot][12]];
        registers[slot][12] = (registers[slot][12] + 1u) & 127u;
    }

    if ((slot == SLOT_TV && word == 7) || (slot == SLOT_MIPI && word == 6)) {
        size_t pointer = slot == SLOT_TV ? 6u : 5u;

        value = 0x11000000u | registers[slot][pointer];
        registers[slot][pointer]++;
    }

    return value;
}

void rv32_mmio_write32(uintptr_t address, uint32_t value)
{
    size_t slot = slot_of(address);
    size_t word = word_of(address);

    writes++;
    last_address = address;
    last_value = value;

    if ((slot == SLOT_SPI || slot == SLOT_SD_SPI) && word == 2) {
        registers[slot][word] &= ~(value & 0xE0u);
    } else if (slot == SLOT_IR && word == 1) {
        registers[slot][word] &= ~(value & 0x2Cu);
    } else if (slot == SLOT_I2C && word == 5) {
        registers[slot][word] &= ~(value & 0x3Cu);
    } else if ((slot == SLOT_ADC && word == 9) || (slot == SLOT_MAX10 && word == 3)) {
        registers[slot][word] &= ~(value & (slot == SLOT_ADC ? 2u : 6u));
    } else if (slot == SLOT_SD && word == 11) {
        sd_buffer[registers[slot][12]] = value;
        registers[slot][12] = (registers[slot][12] + 1u) & 127u;
    } else {
        registers[slot][word] = value;
    }

    if (slot == SLOT_ETH && word == 8) {
        assert(eth_sent_count < 8);
        eth_sent[eth_sent_count++] = value;
    }

    if (slot == SLOT_ETH && word == 11) {
        if (value == 2) {
            eth_received_index = 0;
        } else if (value == 1) {
            registers[slot][1] &= ~2u;
        }
    }
}

void rv32_mmio_write8(uintptr_t address, uint8_t value)
{
    (void)address;
    (void)value;
    assert(false); /* These APIs never invent partial writes. */
}

void rv32_mmio_write16(uintptr_t address, uint16_t value)
{
    (void)address;
    (void)value;
    assert(false);
}

static void constructors(void)
{
    assert(rv32_spi_valid(rv32_spi_new(0)));
    assert(!rv32_spi_valid(rv32_spi_new(SIZE_MAX)));
    assert(rv32_sd_spi_valid(rv32_sd_spi_new(0)));
    assert(!rv32_sd_spi_valid(rv32_sd_spi_new(SIZE_MAX)));
    assert(rv32_i2c_valid(rv32_i2c_new(0)));
    assert(!rv32_i2c_valid(rv32_i2c_new(SIZE_MAX)));
    assert(rv32_ir_valid(rv32_ir_new(0)));
    assert(!rv32_ir_valid(rv32_ir_new(SIZE_MAX)));
    assert(rv32_lcd_valid(rv32_lcd_new(0)));
    assert(!rv32_lcd_valid(rv32_lcd_new(SIZE_MAX)));
    assert(rv32_keyboard_valid(rv32_keyboard_new(0)));
    assert(!rv32_keyboard_valid(rv32_keyboard_new(SIZE_MAX)));
    assert(rv32_mouse_valid(rv32_mouse_new(0)));
    assert(!rv32_mouse_valid(rv32_mouse_new(SIZE_MAX)));
    assert(rv32_audio_valid(rv32_audio_new(0)));
    assert(!rv32_audio_valid(rv32_audio_new(SIZE_MAX)));
    assert(rv32_adxl345_valid(rv32_adxl345_new(0)));
    assert(!rv32_adxl345_valid(rv32_adxl345_new(SIZE_MAX)));
    assert(rv32_adc_valid(rv32_adc_new(0)));
    assert(!rv32_adc_valid(rv32_adc_new(SIZE_MAX)));
    assert(rv32_eth_valid(rv32_eth_new(0)));
    assert(!rv32_eth_valid(rv32_eth_new(SIZE_MAX)));
    assert(rv32_tv_valid(rv32_tv_new(0)));
    assert(!rv32_tv_valid(rv32_tv_new(SIZE_MAX)));
    assert(rv32_mipi_valid(rv32_mipi_new(0)));
    assert(!rv32_mipi_valid(rv32_mipi_new(SIZE_MAX)));
    assert(rv32_sd_valid(rv32_sd_new(0)));
    assert(!rv32_sd_valid(rv32_sd_new(SIZE_MAX)));
    assert(rv32_video_valid(rv32_video_new(0)));
    assert(!rv32_video_valid(rv32_video_new(SIZE_MAX)));
    assert(rv32_hdmi_valid(rv32_hdmi_new(0)));
    assert(!rv32_hdmi_valid(rv32_hdmi_new(SIZE_MAX)));
    assert(rv32_wifi_valid(rv32_wifi_new(0)));
    assert(!rv32_wifi_valid(rv32_wifi_new(SIZE_MAX)));
    assert(reads == 0 && writes == 0);
}

static void serial_queues(void)
{
    rv32_spi_t spi = rv32_spi_new(0);
    uint32_t value = 99;

    assert(!rv32_spi_try_write(spi, 123));
    assert(!rv32_spi_try_read(spi, &value));
    assert(value == 99);
    registers[SLOT_SPI][2] = 3;
    assert(rv32_spi_try_write(spi, 0x12345678));
    assert(last_address == spi.base && last_value == 0x12345678);
    registers[SLOT_SPI][1] = 0xDEADBEEF;
    assert(rv32_spi_try_read(spi, &value));
    assert(value == 0xDEADBEEF);
    assert(!rv32_spi_try_read(spi, &value));
    assert(!rv32_spi_configure(spi, 4, 8, false));
    assert(!rv32_spi_configure(spi, 0, 0, false));
    assert(rv32_spi_configure(spi, 3, 12, true));
    assert(registers[SLOT_SPI][3] == 0xCE0);
    assert(!rv32_spi_select(spi, 2, true));
    assert(rv32_spi_select(spi, 1, true));
    assert(registers[SLOT_SPI][3] == 0x10CE1);
    registers[SLOT_SPI][2] = 0xE3;
    rv32_spi_clear_events(spi);
    assert(registers[SLOT_SPI][2] == 3);

    rv32_keyboard_t keyboard = rv32_keyboard_new(0);
    uint8_t byte = 0;

    registers[SLOT_KEYBOARD][0] = 0xF0;
    registers[SLOT_KEYBOARD][1] = 1;
    assert(rv32_keyboard_try_read(keyboard, &byte) && byte == 0xF0);
    assert(!rv32_keyboard_try_read(keyboard, &byte));
    assert(!rv32_keyboard_try_command(keyboard, 0xED));
    registers[SLOT_KEYBOARD][1] = 2;
    assert(rv32_keyboard_try_command(keyboard, 0xED));
    assert(last_value == 0xED);

    rv32_sd_spi_t sd_spi = rv32_sd_spi_new(0);

    registers[SLOT_SD_SPI][2] = 2;
    assert(rv32_sd_spi_try_write(sd_spi, 0xFF));
    assert(last_value == 0xFF);
}

static void i2c_commands(void)
{
    rv32_i2c_t i2c = rv32_i2c_new(0);

    assert(!rv32_i2c_start_write(i2c, 0xA0));
    rv32_i2c_enable(i2c, true);
    assert(!rv32_i2c_command(i2c, 13, 0)); /* READ and WRITE together. */
    assert(!rv32_i2c_write_byte(i2c, 1)); /* No open transaction. */
    assert(!rv32_i2c_set_divider(i2c, 1));
    assert(rv32_i2c_set_divider(i2c, 99));
    assert(rv32_i2c_start_write(i2c, 0xA0));
    assert(registers[SLOT_I2C][2] == 9);
    assert(registers[SLOT_I2C][3] == 0xA0);
    registers[SLOT_I2C][5] = 3;
    assert(!rv32_i2c_write_stop(i2c, 7));
    registers[SLOT_I2C][5] = 2;
    assert(rv32_i2c_read_stop(i2c));
    assert(registers[SLOT_I2C][2] == 22);
    registers[SLOT_I2C][5] = 63;
    rv32_i2c_clear_events(i2c);
    assert(registers[SLOT_I2C][5] == 3);
}

static void samples_and_events(void)
{
    rv32_adc_t external = rv32_adc_new(0);
    rv32_adc_t max10 = rv32_adc_new(1);

    assert(rv32_adc_channel_count(external) == 8);
    assert(rv32_adc_channel_count(max10) == 18);
    registers[SLOT_ADC][7] = 0xABC;
    registers[SLOT_ADC][9] = 4;
    assert(rv32_adc_read_channel(external, 7) == 0x1ABC);
    assert(rv32_adc_read_channel(external, 8) == 0);
    registers[SLOT_MAX10][25] = 0x3123;
    assert(rv32_adc_read_channel(max10, 17) == 0x3123);
    assert(rv32_adc_read_channel(max10, 17) == 0x123);
    assert(!rv32_adc_set_mask(external, 1));
    assert(rv32_adc_set_mask(max10, 1u << 17));
    assert(registers[SLOT_MAX10][1] == (1u << 17));
    assert(!rv32_adc_set_mask(max10, 1u << 18));
    assert(rv32_adc_start(max10));
    assert((registers[SLOT_MAX10][0] & 9u) == 9u);

    rv32_ir_t ir = rv32_ir_new(0);
    uint32_t frame = 0;

    registers[SLOT_IR][1] = 1;
    registers[SLOT_IR][2] = 0x035A1234;
    assert(rv32_ir_try_read(ir, &frame) && frame == 0x035A1234);
    assert(!rv32_ir_try_read(ir, &frame));

    rv32_mouse_t mouse = rv32_mouse_new(0);

    registers[SLOT_MOUSE][0] = 15;
    assert(rv32_mouse_read_status_clear(mouse) == 15);
    assert(rv32_mouse_read_status_clear(mouse) == 8);
    registers[SLOT_MOUSE][1] = (uint32_t)-123;
    assert(rv32_mouse_take_dx(mouse) == -123);
    assert(rv32_mouse_take_dx(mouse) == 0);

    rv32_adxl345_t accelerometer = rv32_adxl345_new(0);

    registers[SLOT_ADXL345][0] = (uint32_t)-256;
    assert(rv32_adxl345_x(accelerometer) == -256);
    assert(!rv32_adxl345_set_range(accelerometer, 4));
    assert(rv32_adxl345_set_range(accelerometer, 3));
    assert((registers[SLOT_ADXL345][4] & 12u) == 12u);
}

static void frame_and_block_buffers(void)
{
    rv32_sd_t sd = rv32_sd_new(0);
    uint32_t words[2] = {0x12345678, 0};

    assert(rv32_sd_write_buffer(sd, 127, words, 1));
    assert(sd_buffer[127] == words[0]);
    assert(!rv32_sd_write_buffer(sd, 127, words, 2));
    words[0] = 0;
    assert(rv32_sd_read_buffer(sd, 127, words, 1));
    assert(words[0] == 0x12345678);
    assert(!rv32_sd_command(sd, 64, 0, 1, false, 0));
    assert(rv32_sd_command(sd, 17, 0x234, 1, true, 1));
    assert(registers[SLOT_SD][0] == 0x234);
    assert(registers[SLOT_SD][1] == (17u | 64u | 256u | 512u));

    rv32_tv_t tv = rv32_tv_new(0);
    rv32_mipi_t mipi = rv32_mipi_new(0);

    registers[SLOT_TV][5] = (2u << 16) | 4u;
    registers[SLOT_MIPI][4] = (2u << 16) | 8u;
    assert(rv32_tv_word_count(tv) == 4);
    assert(rv32_mipi_word_count(mipi) == 4);
    assert(rv32_tv_read_words(tv, 1, words, 2));
    assert(words[0] == 0x11000001 && words[1] == 0x11000002);
    assert(!rv32_tv_read_words(tv, 3, words, 2));
    assert(rv32_mipi_read_words(mipi, 1, words, 2));
    assert(words[0] == 0x11000001 && words[1] == 0x11000002);
    registers[SLOT_MIPI][1] = 1;
    assert(!rv32_mipi_read_words(mipi, 0, words, 1));
    assert(!rv32_mipi_configure(mipi, 0x2A, 1));
}

static void framebuffer_and_output(void)
{
    rv32_video_t video = rv32_video_new(0);
    rv32_hdmi_t hdmi = rv32_hdmi_new(0);

    registers[SLOT_VIDEO][3] = (2u << 16) | 4u;
    registers[SLOT_VIDEO][4] = (1u << 24) | (8u << 16) | 8u;
    registers[SLOT_HDMI][3] = registers[SLOT_VIDEO][3];
    registers[SLOT_HDMI][4] = registers[SLOT_VIDEO][4];
    assert(rv32_video_word_count(video) == 2);
    assert(rv32_video_write_word(video, 1, 0x04030201));
    assert(registers[SLOT_VIDEO][513] == 0x04030201);
    assert(!rv32_video_write_word(video, 2, 0));
    assert(rv32_video_palette_write(video, 3, 255, 0, 0));
    assert(registers[SLOT_VIDEO][259] == 0xFF0000);
    assert(rv32_hdmi_write_word(hdmi, 0, 0x01010101));
    assert(!rv32_hdmi_restart_initialization(hdmi));
    registers[SLOT_HDMI][9] = 16;
    assert(rv32_hdmi_restart_initialization(hdmi));
    assert(registers[SLOT_HDMI][12] == 1);

    rv32_lcd_t lcd = rv32_lcd_new(0);

    registers[SLOT_LCD][2] = 2;
    assert(!rv32_lcd_try_write(lcd, 'A'));
    registers[SLOT_LCD][2] = 0;
    assert(rv32_lcd_cursor(lcd, 1, 15));
    assert(registers[SLOT_LCD][0] == 0xCF);
    assert(!rv32_lcd_cursor(lcd, 2, 0));

    rv32_audio_t audio = rv32_audio_new(0);
    int32_t sample = 0;

    assert(!rv32_audio_try_write(audio, -1));
    assert(!rv32_audio_try_read(audio, &sample));
    registers[SLOT_AUDIO][1] = 3;
    registers[SLOT_AUDIO][4] = (uint32_t)-1234;
    assert(rv32_audio_try_read(audio, &sample) && sample == -1234);
    assert(rv32_audio_try_write(audio, -1));
    assert(registers[SLOT_AUDIO][3] == UINT32_MAX);

    rv32_wifi_t wifi = rv32_wifi_new(0);
    uint8_t byte = 0;

    registers[SLOT_WIFI][18] = 3;
    registers[SLOT_WIFI][17] = 0xFA;
    assert(rv32_wifi_uart_try_read(wifi, &byte) && byte == 0xFA);
    assert(rv32_wifi_uart_try_write(wifi, 0xA5));
    assert(registers[SLOT_WIFI][16] == 0xA5);
}

static void ethernet_frames(void)
{
    rv32_eth_t eth = rv32_eth_new(0);
    const uint8_t mac[6] = {2, 3, 4, 5, 6, 7};
    const uint8_t send[5] = {1, 2, 3, 4, 5};
    uint8_t received[5] = {0};
    size_t length = 0;

    rv32_eth_set_mac(eth, mac);
    assert(registers[SLOT_ETH][4] == 0x05040302);
    assert(registers[SLOT_ETH][5] == 0x0706);
    assert(!rv32_eth_send(eth, send, 0));
    registers[SLOT_ETH][1] = 1;
    assert(!rv32_eth_send(eth, send, 5));
    registers[SLOT_ETH][1] = 0;
    assert(rv32_eth_send(eth, send, 5));
    assert(eth_sent_count == 2);
    assert(eth_sent[0] == 0x04030201 && eth_sent[1] == 5);
    registers[SLOT_ETH][1] = 2;
    registers[SLOT_ETH][9] = 5;
    assert(!rv32_eth_receive(eth, received, 4, &length));
    assert(eth_received_index == 0 && length == 0);
    assert(rv32_eth_receive(eth, received, 5, &length));
    assert(length == 5 && memcmp(received, send, 5) == 0);
    assert(!rv32_eth_rx_ready(eth));
    assert(!rv32_eth_mdio_start(eth, 32, 0, false, 0));
    assert(rv32_eth_mdio_start(eth, 16, 3, true, 0x1234));
    assert(registers[SLOT_ETH][12] == (3u | (16u << 5) | (1u << 10)));
}

int main(void)
{
    constructors();
    serial_queues();
    i2c_commands();
    samples_and_events();
    frame_and_block_buffers();
    framebuffer_and_output();
    ethernet_frames();
    puts("new peripheral driver bus contracts: PASS");

    return 0;
}

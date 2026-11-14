/* SPDX-License-Identifier: Apache-2.0
 * RAM-backed MMIO tests. Device side effects require the separate RTL tests.
 */
#include "rv32_clint.h"
#include "rv32_display.h"
#include "rv32_flash.h"
#include "rv32_plic.h"
#include "rv32_timer.h"
#include "rv32_uart.h"

#include <assert.h>

static void test_timer(void)
{
    volatile uint32_t words[8] = {0};
    rv32_timer_t timer = rv32_timer_new((uintptr_t)words);

    assert(rv32_timer_valid(timer));
    assert(!rv32_timer_valid(rv32_timer_new(3)));
    assert(!rv32_timer_valid(rv32_timer_new(UINTPTR_MAX - 3)));
    rv32_timer_one_shot(timer, true);
    rv32_timer_irq_enable(timer, true);
    rv32_timer_pwm_enable(timer, true);
    rv32_timer_start(timer);
    assert(words[0] == 15);
    rv32_timer_stop(timer);
    assert(words[0] == 14);

    rv32_timer_set_top(timer, 100);
    rv32_timer_set_duty(timer, 25);
    assert(rv32_timer_set_divider(timer, 10));
    assert(words[3] == 100);
    assert(words[4] == 25);
    assert(words[7] == 9);
    assert(!rv32_timer_set_divider(timer, 0));

    rv32_timer_load(timer, 7);
    assert(rv32_timer_count(timer) == 7);
    rv32_timer_reset(timer);
    assert(words[2] == 0);
    words[5] = 1;
    words[6] = 1;
    assert(rv32_timer_overflow_read_clear(timer));
    assert(words[5] == 1);
    assert(rv32_timer_pwm_read(timer));
}

static void test_clint(void)
{
    static volatile uint32_t words[0xc000 / 4];
    rv32_clint_t clint = rv32_clint_new((uintptr_t)words);

    assert(rv32_clint_valid(clint));
    assert(!rv32_clint_valid(rv32_clint_new(0)));
    words[0xbff8 / 4] = 0x12345678;
    words[0xbffc / 4] = 0xabcdef01;
    assert(rv32_clint_time(clint) == UINT64_C(0xabcdef0112345678));

    rv32_clint_set_deadline(clint, UINT64_C(0x12345678abcdef01));
    assert(words[0x4000 / 4] == 0xabcdef01);
    assert(words[0x4004 / 4] == 0x12345678);

    rv32_clint_software_irq(clint, true);
    assert(rv32_clint_software_irq_pending(clint));
    rv32_clint_software_irq(clint, false);
    assert(!rv32_clint_software_irq_pending(clint));
}

static void test_plic(void)
{
    static volatile uint32_t words[0x200008 / 4];
    rv32_plic_t plic = rv32_plic_new((uintptr_t)words, 1023, 32);
    rv32_plic_t narrow = rv32_plic_new((uintptr_t)words, 6, 3);

    assert(rv32_plic_valid(plic));
    assert(!rv32_plic_valid(rv32_plic_new((uintptr_t)words, 1024, 3)));
    assert(!rv32_plic_valid(rv32_plic_new((uintptr_t)words, 6, 0)));
    assert(!rv32_plic_valid(rv32_plic_new((uintptr_t)words, 6, 33)));
    assert(!rv32_plic_set_priority(narrow, 0, 1));
    assert(!rv32_plic_set_priority(narrow, 7, 1));
    assert(!rv32_plic_set_priority(narrow, 1, 8));
    assert(!rv32_plic_set_threshold(narrow, 8));
    assert(rv32_plic_set_priority(plic, 1023, UINT32_MAX));
    assert(words[1023] == UINT32_MAX);
    assert(rv32_plic_set_threshold(plic, 7));
    assert(words[0x200000 / 4] == 7);

    assert(rv32_plic_enable(plic, 31, true));
    assert(rv32_plic_enable(plic, 32, true));
    assert(rv32_plic_enable(plic, 1023, true));
    assert(words[0x2000 / 4] == 0x80000000);
    assert(words[0x2000 / 4 + 1] == 1);
    assert(words[0x2000 / 4 + 31] == 0x80000000);
    assert(rv32_plic_enable(plic, 32, false));
    assert(words[0x2000 / 4 + 1] == 0);

    words[0x1000 / 4 + 31] = 0x80000000;
    assert(rv32_plic_pending(plic, 1023));
    words[0x200004 / 4] = 6;
    assert(rv32_plic_claim(plic) == 6);
    assert(rv32_plic_complete(plic, 6));
    assert(words[0x200004 / 4] == 6);
    assert(!rv32_plic_complete(plic, 0));
}

static void test_uart(void)
{
    volatile uint32_t words[4] = {0};
    rv32_uart_t serial = rv32_uart_new((uintptr_t)words, RV32_UART_SERIAL, 16);
    rv32_uart_t jtag = rv32_uart_new((uintptr_t)words, RV32_UART_JTAG, 8);
    uint8_t byte = 0;
    const uint8_t message[] = {'A', 'B', 'C'};

    assert(rv32_uart_valid(serial));
    assert(!rv32_uart_valid(rv32_uart_new(0, RV32_UART_JTAG, 64)));
    assert(!rv32_uart_valid(rv32_uart_new((uintptr_t)words, RV32_UART_JTAG, 0)));
    assert(
        !rv32_uart_valid(rv32_uart_new((uintptr_t)words, (rv32_uart_backend_t)9, 8)));
    assert(!rv32_uart_try_write(serial, 'A'));
    assert(words[0] == 0);
    assert(!rv32_uart_try_read(serial, &byte));

    words[2] = 3;
    words[1] = 'Z';
    assert(rv32_uart_try_write(serial, 'A'));
    assert(words[0] == 'A');
    assert(rv32_uart_try_read(serial, &byte));
    assert(byte == 'Z');
    assert(!rv32_uart_try_read(serial, NULL));
    assert(rv32_uart_write(serial, message, 3, 2) == 2);
    assert(words[0] == 'B');

    words[2] = 0;
    assert(rv32_uart_write(serial, message, 3, 5) == 0);
    assert(rv32_uart_write(serial, message, 3, 0) == 0);
    words[2] = 0x40;
    assert(rv32_uart_tx_idle(serial));
    rv32_uart_clear_errors(serial);
    assert(words[2] == 0x0c);

    words[2] = 1;
    assert(rv32_uart_try_write(jtag, 'J'));
    words[1] = 0x15a;
    assert(rv32_uart_try_read(jtag, &byte));
    assert(byte == 'Z');
    words[1] = 0x5a;
    assert(!rv32_uart_try_read(jtag, &byte));
    words[2] = 8;
    assert(rv32_uart_tx_idle(jtag));
    words[2] = 7;
    assert(!rv32_uart_tx_idle(jtag));
    rv32_uart_irq_configure(jtag, true, false, true);
    assert(words[3] == 5);
}

static void test_display(void)
{
    volatile uint32_t word = 0;
    rv32_display_t display = rv32_display_new((uintptr_t)&word, 8);
    rv32_display_t narrow = rv32_display_new((uintptr_t)&word, 3);
    uint8_t digit = 0;

    assert(!rv32_display_valid(rv32_display_new((uintptr_t)&word, 9)));
    assert(!rv32_display_valid(rv32_display_new((uintptr_t)&word, 0)));
    {
        volatile uint32_t block[32] = {0};
        rv32_display_t group1 = rv32_display_group_new((uintptr_t)block, 1, 4);

        assert(rv32_display_valid(group1));
        rv32_display_write(group1, 0xabcd);
        assert(block[16] == 0xabcd);
        assert(block[0] == 0);
        assert(!rv32_display_valid(rv32_display_group_new(0, 1, 4)));
        assert(!rv32_display_valid(
            rv32_display_group_new(UINTPTR_MAX - 64, 2, 4)));
    }
    rv32_display_write(display, 0x12345678);
    assert(rv32_display_write_digit(display, 7, 15));
    assert(word == 0xf2345678);
    assert(rv32_display_read_digit(display, 0, &digit));
    assert(digit == 8);
    assert(!rv32_display_write_digit(display, 8, 1));
    assert(!rv32_display_write_digit(display, 0, 16));
    assert(!rv32_display_read_digit(display, 0, NULL));
    rv32_display_write(narrow, UINT32_MAX);
    assert(word == 0xfff);
}

static void test_flash(void)
{
    volatile uint32_t words[7] = {0};
    rv32_flash_t flash = rv32_flash_new((uintptr_t)words, 256);

    assert(rv32_flash_valid(flash));
    assert(!rv32_flash_valid(rv32_flash_new((uintptr_t)words, 4)));
    assert(!rv32_flash_valid(rv32_flash_new((uintptr_t)words, 12)));
    assert(rv32_flash_buffer_word(flash, 63, UINT32_MAX));
    assert(words[3] == 63);
    assert(words[4] == UINT32_MAX);
    assert(!rv32_flash_buffer_word(flash, 64, 0));
    assert(!rv32_flash_buffer_word(flash, SIZE_MAX, 0));

    words[2] = 1;
    assert(rv32_flash_busy(flash));
    assert(!rv32_flash_buffer_word(flash, 0, 0));
    assert(!rv32_flash_submit(flash, RV32_FLASH_ERASE_SECTOR, 0));
    words[2] = 0;
    assert(!rv32_flash_submit(flash, (rv32_flash_command_t)1, 0));
    assert(rv32_flash_submit(flash, RV32_FLASH_PROGRAM_PAGE, 0x1234));
    assert(words[0] == 3);
    assert(words[1] == 0x1234);

    words[2] = 4;
    assert(rv32_flash_refused(flash));
    rv32_flash_irq_configure(flash, true, true);
    assert(words[5] == 3);
    words[6] = 3;
    assert(rv32_flash_irq_pending(flash) == 3);
    assert(words[6] == 3);
    rv32_flash_irq_acknowledge(flash, true, false);
    assert(words[6] == 1);
}

int main(void)
{
    test_timer();
    test_clint();
    test_plic();
    test_uart();
    test_display();
    test_flash();

    return 0;
}

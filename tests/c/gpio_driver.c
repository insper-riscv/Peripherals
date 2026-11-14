/* SPDX-License-Identifier: Apache-2.0
 * MMIO em RAM valida endereços, índices e máscaras. RAM não emula efeitos
 * como SET/CLEAR/TOGGLE ou read-to-clear; esses efeitos são testados no RTL.
 */
#include "rv32_gpio.h"

#include <assert.h>
#include <stdint.h>

static void test_register_compatibility(rv32_gpio_t gpio, volatile uint32_t *words)
{
    rv32_gpio_direction(gpio, 0xa5);
    assert(words[0] == 0xa5);
    assert(rv32_gpio_get_direction(gpio) == 0xa5);

    rv32_gpio_write(gpio, 0x81234567);
    assert(words[1] == 0x81234567);
    assert(rv32_gpio_read_output(gpio) == 0x81234567);

    rv32_gpio_set(gpio, 0x80);
    rv32_gpio_clear(gpio, 0x40);
    rv32_gpio_toggle(gpio, 0x20);
    assert(words[2] == 0x80);
    assert(words[3] == 0x40);
    assert(words[4] == 0x20);

    words[9] = 0x55;
    assert(rv32_gpio_read(gpio) == 0x55);

    rv32_gpio_irq_configure(gpio, 5, 1, 4, 4);
    assert(words[5] == 5);
    assert(words[6] == 1);
    assert(words[7] == 4);
    assert(words[10] == 4);

    words[8] = 5;
    assert(rv32_gpio_irq_read_clear(gpio) == 5);
    assert(words[8] == 5);
}

static void test_pin_access(rv32_gpio_t gpio, volatile uint32_t *words)
{
    words[0] = 2;
    assert(rv32_gpio_pin_direction(gpio, 0, RV32_GPIO_OUTPUT_PIN));
    assert(words[0] == 3);
    assert(rv32_gpio_pin_direction(gpio, 1, RV32_GPIO_INPUT));
    assert(words[0] == 1);

    for (size_t pin = 0; pin < 32; ++pin) {
        uint32_t bit = UINT32_C(1) << pin;
        bool high = false;

        assert(rv32_gpio_pin_write(gpio, pin, true));
        assert(words[2] == bit);
        assert(rv32_gpio_pin_write(gpio, pin, false));
        assert(words[3] == bit);
        assert(rv32_gpio_pin_toggle(gpio, pin));
        assert(words[4] == bit);

        words[9] = bit;
        assert(rv32_gpio_pin_read(gpio, pin, &high));
        assert(high);
        assert(rv32_gpio_irq_contains(bit, pin));
    }

    assert(!rv32_gpio_pin_write(gpio, 32, true));
    assert(!rv32_gpio_pin_toggle(gpio, SIZE_MAX));
    assert(!rv32_gpio_pin_read(gpio, 0, NULL));
    assert(!rv32_gpio_pin_direction(gpio, 0, (rv32_gpio_direction_t)99));
    assert(!rv32_gpio_irq_contains(UINT32_MAX, 32));
}

static void test_pin_interrupts(rv32_gpio_t gpio, volatile uint32_t *words)
{
    rv32_gpio_irq_configure(gpio, 2, 2, 2, 2);

    assert(rv32_gpio_pin_irq_configure(gpio, 0, RV32_GPIO_IRQ_BOTH_EDGES));
    assert(words[5] == 3);
    assert(words[6] == 3);
    assert(words[7] == 3);
    assert(words[10] == 2);

    assert(rv32_gpio_pin_irq_configure(gpio, 0, RV32_GPIO_IRQ_HIGH_LEVEL));
    assert(words[6] == 3);
    assert(words[7] == 2);
    assert(words[10] == 3);

    assert(rv32_gpio_pin_irq_configure(gpio, 0, RV32_GPIO_IRQ_LOW_LEVEL));
    assert(words[6] == 2);
    assert(words[7] == 3);

    assert(rv32_gpio_pin_irq_configure(gpio, 0, RV32_GPIO_IRQ_DISABLED));
    assert(words[5] == 2);
    assert(words[6] == 2);
    assert(words[7] == 2);
    assert(words[10] == 2);

    assert(!rv32_gpio_pin_irq_configure(gpio, 0, (rv32_gpio_irq_mode_t)99));
}

int main(void)
{
    volatile uint32_t words[11] = {0};
    rv32_gpio_t gpio = rv32_gpio_new((uintptr_t)words, 32);
    rv32_gpio_t narrow = rv32_gpio_new((uintptr_t)words, 4);
    rv32_gpio_t invalid = rv32_gpio_new(0, 4);

    /* Source-tree placeholders never dereference address zero. */
    assert(!rv32_gpio_valid(rv32_gpio_platform_new(RV32_GPIO_DEFAULT_INSTANCE)));
    assert(!rv32_gpio_valid(rv32_gpio_platform_new(RV32_GPIO_SWITCHES_INSTANCE)));
    assert(!rv32_gpio_valid(rv32_gpio_platform_new(RV32_GPIO_KEYS_INSTANCE)));
    assert(!rv32_gpio_valid(rv32_gpio_platform_new((rv32_gpio_instance_t)99)));

    assert(rv32_gpio_valid(gpio));
    assert(!rv32_gpio_valid(invalid));
    assert(rv32_gpio_get_direction(invalid) == 0);
    assert(rv32_gpio_read_output(invalid) == 0);
    assert(!rv32_gpio_pin_write(narrow, 4, true));
    assert(!rv32_gpio_pin_write(invalid, 0, true));
    assert(!rv32_gpio_valid(rv32_gpio_new((uintptr_t)words + 1, 4)));
    assert(!rv32_gpio_valid(rv32_gpio_new((uintptr_t)words, 0)));
    assert(!rv32_gpio_valid(rv32_gpio_new((uintptr_t)words, 33)));
    assert(!rv32_gpio_valid(rv32_gpio_new(UINTPTR_MAX - 3, 4)));

    {
        volatile uint32_t block[32] = {0};
        rv32_gpio_t group1 = rv32_gpio_group_new((uintptr_t)block, 1, 4);

        assert(rv32_gpio_valid(group1));
        assert(rv32_gpio_pin_direction(group1, 2, RV32_GPIO_OUTPUT_PIN));
        assert(block[16] == 4);
        assert(block[0] == 0);
        assert(!rv32_gpio_valid(rv32_gpio_group_new(0, 1, 4)));
        assert(!rv32_gpio_valid(rv32_gpio_group_new(UINTPTR_MAX - 64, 2, 4)));
    }

    test_register_compatibility(gpio, words);
    test_pin_access(gpio, words);
    test_pin_interrupts(gpio, words);

    return 0;
}

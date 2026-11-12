/* SPDX-License-Identifier: Apache-2.0
 * Acessos voláteis de 32 bits aos registradores do GPIO.
 */
#include "rv32_gpio.h"
#include <rv32_gpio_platform.h>

/* Deslocamentos em bytes. O decodificador RTL recebe endereços de palavra. */
enum {
    RV32_GPIO_DIRECTION = 0x00,
    RV32_GPIO_OUTPUT = 0x04,
    RV32_GPIO_SET = 0x08,
    RV32_GPIO_CLEAR = 0x0c,
    RV32_GPIO_TOGGLE = 0x10,
    RV32_GPIO_IRQ_ENABLE = 0x14,
    RV32_GPIO_IRQ_RISING = 0x18,
    RV32_GPIO_IRQ_FALLING = 0x1c,
    RV32_GPIO_IRQ_STATUS = 0x20,
    RV32_GPIO_PINS = 0x24,
    RV32_GPIO_IRQ_LEVEL = 0x28
};

static volatile uint32_t *reg_at(rv32_gpio_t gpio, uintptr_t offset)
{
    return (volatile uint32_t *)(gpio.base + offset);
}

void rv32_gpio_direction(rv32_gpio_t gpio, uint32_t outputs)
{
    if (rv32_gpio_valid(gpio)) {
        *reg_at(gpio, RV32_GPIO_DIRECTION) = outputs;
    }
}

uint32_t rv32_gpio_get_direction(rv32_gpio_t gpio)
{
    return *reg_at(gpio, RV32_GPIO_DIRECTION);
}

void rv32_gpio_write(rv32_gpio_t gpio, uint32_t value)
{
    if (rv32_gpio_valid(gpio)) {
        *reg_at(gpio, RV32_GPIO_OUTPUT) = value;
    }
}

uint32_t rv32_gpio_read_output(rv32_gpio_t gpio)
{
    return *reg_at(gpio, RV32_GPIO_OUTPUT);
}

void rv32_gpio_set(rv32_gpio_t gpio, uint32_t mask)
{
    if (rv32_gpio_valid(gpio)) {
        *reg_at(gpio, RV32_GPIO_SET) = mask;
    }
}

void rv32_gpio_clear(rv32_gpio_t gpio, uint32_t mask)
{
    if (rv32_gpio_valid(gpio)) {
        *reg_at(gpio, RV32_GPIO_CLEAR) = mask;
    }
}

void rv32_gpio_toggle(rv32_gpio_t gpio, uint32_t mask)
{
    if (rv32_gpio_valid(gpio)) {
        *reg_at(gpio, RV32_GPIO_TOGGLE) = mask;
    }
}

uint32_t rv32_gpio_read(rv32_gpio_t gpio)
{
    return *reg_at(gpio, RV32_GPIO_PINS);
}

void rv32_gpio_irq_enable(rv32_gpio_t gpio, uint32_t mask)
{
    if (rv32_gpio_valid(gpio)) {
        *reg_at(gpio, RV32_GPIO_IRQ_ENABLE) = mask;
    }
}

void rv32_gpio_irq_configure(rv32_gpio_t gpio, uint32_t enabled, uint32_t rising,
                             uint32_t falling, uint32_t level)
{
    if (!rv32_gpio_valid(gpio)) {
        return;
    }

    rv32_gpio_irq_enable(gpio, 0);
    *reg_at(gpio, RV32_GPIO_IRQ_RISING) = rising;
    *reg_at(gpio, RV32_GPIO_IRQ_FALLING) = falling;
    *reg_at(gpio, RV32_GPIO_IRQ_LEVEL) = level;
    rv32_gpio_irq_enable(gpio, enabled);
}

uint32_t rv32_gpio_irq_read_clear(rv32_gpio_t gpio)
{
    return *reg_at(gpio, RV32_GPIO_IRQ_STATUS);
}

rv32_gpio_t rv32_gpio_new(uintptr_t base, size_t pin_count)
{
    rv32_gpio_t gpio = {0};

    if (base != 0 && base % 4 == 0 && base <= UINTPTR_MAX - 40 && pin_count > 0 &&
        pin_count <= 32) {
        gpio.base = base;
        gpio.pin_count = pin_count;
    }

    return gpio;
}

bool rv32_gpio_valid(rv32_gpio_t gpio)
{
    return gpio.base != 0 && gpio.pin_count > 0 && gpio.pin_count <= 32;
}

static bool valid_pin(rv32_gpio_t gpio, size_t pin)
{
    return rv32_gpio_valid(gpio) && pin < gpio.pin_count;
}

bool rv32_gpio_pin_direction(rv32_gpio_t gpio, size_t pin,
                             rv32_gpio_direction_t direction)
{
    if (!valid_pin(gpio, pin) ||
        (direction != RV32_GPIO_INPUT && direction != RV32_GPIO_OUTPUT_PIN)) {
        return false;
    }

    uint32_t mask = UINT32_C(1) << pin;
    uint32_t value = rv32_gpio_get_direction(gpio);

    value = direction == RV32_GPIO_OUTPUT_PIN ? value | mask : value & ~mask;
    rv32_gpio_direction(gpio, value);

    return true;
}

bool rv32_gpio_pin_write(rv32_gpio_t gpio, size_t pin, bool high)
{
    if (!valid_pin(gpio, pin)) {
        return false;
    }

    uint32_t mask = UINT32_C(1) << pin;

    if (high) {
        rv32_gpio_set(gpio, mask);
    } else {
        rv32_gpio_clear(gpio, mask);
    }

    return true;
}

bool rv32_gpio_pin_toggle(rv32_gpio_t gpio, size_t pin)
{
    if (!valid_pin(gpio, pin)) {
        return false;
    }

    rv32_gpio_toggle(gpio, UINT32_C(1) << pin);

    return true;
}

bool rv32_gpio_pin_read(rv32_gpio_t gpio, size_t pin, bool *high)
{
    if (!valid_pin(gpio, pin) || high == NULL) {
        return false;
    }

    *high = (rv32_gpio_read(gpio) & (UINT32_C(1) << pin)) != 0;

    return true;
}

bool rv32_gpio_irq_contains(uint32_t snapshot, size_t pin)
{
    return pin < 32 && (snapshot & (UINT32_C(1) << pin)) != 0;
}

bool rv32_gpio_pin_irq_configure(rv32_gpio_t gpio, size_t pin,
                                 rv32_gpio_irq_mode_t mode)
{
    if (!valid_pin(gpio, pin) || mode < RV32_GPIO_IRQ_DISABLED ||
        mode > RV32_GPIO_IRQ_LOW_LEVEL) {
        return false;
    }

    uint32_t bit = UINT32_C(1) << pin;
    uint32_t enabled = *reg_at(gpio, RV32_GPIO_IRQ_ENABLE) & ~bit;
    uint32_t rising = *reg_at(gpio, RV32_GPIO_IRQ_RISING) & ~bit;
    uint32_t falling = *reg_at(gpio, RV32_GPIO_IRQ_FALLING) & ~bit;
    uint32_t level = *reg_at(gpio, RV32_GPIO_IRQ_LEVEL) & ~bit;

    if (mode != RV32_GPIO_IRQ_DISABLED) {
        enabled |= bit;
    }

    if (mode == RV32_GPIO_IRQ_RISING_EDGE || mode == RV32_GPIO_IRQ_BOTH_EDGES ||
        mode == RV32_GPIO_IRQ_HIGH_LEVEL) {
        rising |= bit;
    }

    if (mode == RV32_GPIO_IRQ_FALLING_EDGE || mode == RV32_GPIO_IRQ_BOTH_EDGES ||
        mode == RV32_GPIO_IRQ_LOW_LEVEL) {
        falling |= bit;
    }

    if (mode == RV32_GPIO_IRQ_HIGH_LEVEL || mode == RV32_GPIO_IRQ_LOW_LEVEL) {
        level |= bit;
    }

    rv32_gpio_irq_enable(gpio, enabled & ~bit);
    *reg_at(gpio, RV32_GPIO_IRQ_RISING) = rising;
    *reg_at(gpio, RV32_GPIO_IRQ_FALLING) = falling;
    *reg_at(gpio, RV32_GPIO_IRQ_LEVEL) = level;
    rv32_gpio_irq_enable(gpio, enabled);

    return true;
}

rv32_gpio_t rv32_gpio_platform_new(rv32_gpio_instance_t instance)
{
    switch (instance) {
    case RV32_GPIO_DEFAULT_INSTANCE:
        return rv32_gpio_new(RV32_GPIO_DEFAULT_BASE, RV32_GPIO_DEFAULT_PIN_COUNT);
    case RV32_GPIO_SWITCHES_INSTANCE:
        return rv32_gpio_new(RV32_GPIO_SWITCHES_BASE, RV32_GPIO_SWITCHES_PIN_COUNT);
    case RV32_GPIO_KEYS_INSTANCE:
        return rv32_gpio_new(RV32_GPIO_KEYS_BASE, RV32_GPIO_KEYS_PIN_COUNT);
    default:
        return rv32_gpio_new(0, 0);
    }
}

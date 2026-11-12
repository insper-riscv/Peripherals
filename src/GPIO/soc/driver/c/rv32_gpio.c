/* SPDX-License-Identifier: Apache-2.0
 * Acessos voláteis de 32 bits aos registradores do GPIO.
 */
#include "rv32_gpio.h"

static volatile uint32_t *reg_at(rv32_gpio_t gpio, uintptr_t offset)
{
    return (volatile uint32_t *)(gpio.base + offset);
}

void rv32_gpio_direction(rv32_gpio_t gpio, uint32_t outputs)
{
    *reg_at(gpio, RV32_GPIO_DIRECTION) = outputs;
}

uint32_t rv32_gpio_get_direction(rv32_gpio_t gpio)
{
    return *reg_at(gpio, RV32_GPIO_DIRECTION);
}

void rv32_gpio_write(rv32_gpio_t gpio, uint32_t value)
{
    *reg_at(gpio, RV32_GPIO_OUTPUT) = value;
}

uint32_t rv32_gpio_read_output(rv32_gpio_t gpio)
{
    return *reg_at(gpio, RV32_GPIO_OUTPUT);
}

void rv32_gpio_set(rv32_gpio_t gpio, uint32_t mask)
{
    *reg_at(gpio, RV32_GPIO_SET) = mask;
}

void rv32_gpio_clear(rv32_gpio_t gpio, uint32_t mask)
{
    *reg_at(gpio, RV32_GPIO_CLEAR) = mask;
}

void rv32_gpio_toggle(rv32_gpio_t gpio, uint32_t mask)
{
    *reg_at(gpio, RV32_GPIO_TOGGLE) = mask;
}

uint32_t rv32_gpio_read(rv32_gpio_t gpio)
{
    return *reg_at(gpio, RV32_GPIO_PINS);
}

void rv32_gpio_irq_enable(rv32_gpio_t gpio, uint32_t mask)
{
    *reg_at(gpio, RV32_GPIO_IRQ_ENABLE) = mask;
}

void rv32_gpio_irq_configure(rv32_gpio_t gpio, uint32_t enabled,
                            uint32_t rising, uint32_t falling, uint32_t level)
{
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

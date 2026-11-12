/* SPDX-License-Identifier: Apache-2.0
 * Driver C23 do GPIO. Os endereços de instância vêm do mapa da plataforma.
 * Máscaras são valores lógicos; a polaridade física é aplicada pelo hardware.
 */
#ifndef RV32_GPIO_H
#define RV32_GPIO_H

#include <stdint.h>

typedef struct {
    uintptr_t base;
} rv32_gpio_t;

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

/* Substitui a direção de todos os pinos, com 1 para saída e 0 para entrada. */
void rv32_gpio_direction(rv32_gpio_t gpio, uint32_t outputs);
uint32_t rv32_gpio_get_direction(rv32_gpio_t gpio);
/* Substitui a palavra de saída; a direção não é alterada. */
void rv32_gpio_write(rv32_gpio_t gpio, uint32_t value);
uint32_t rv32_gpio_read_output(rv32_gpio_t gpio);
/* Operações de máscara em uma única escrita, sem leitura/modificação/escrita. */
void rv32_gpio_set(rv32_gpio_t gpio, uint32_t mask);
void rv32_gpio_clear(rv32_gpio_t gpio, uint32_t mask);
void rv32_gpio_toggle(rv32_gpio_t gpio, uint32_t mask);
/* Lê o valor sincronizado dos pinos, inclusive quando configurados como saída. */
uint32_t rv32_gpio_read(rv32_gpio_t gpio);
/* Configura as máscaras completas. Em level, rising indica alto e falling baixo.
 * Desabilita a máscara global durante a configuração e a restaura ao final.
 * Não limpa eventos pendentes; o chamador serializa configurações concorrentes.
 */
void rv32_gpio_irq_configure(rv32_gpio_t gpio, uint32_t enabled,
                            uint32_t rising, uint32_t falling, uint32_t level);
void rv32_gpio_irq_enable(rv32_gpio_t gpio, uint32_t mask);
/* Retorna e limpa TODOS os eventos pendentes dessa instância em uma leitura.
 * Não há leitura sem efeito colateral nem escrita W1C no RTL atual.
 * Uma condição de nível persistente pode levantar o status novamente.
 */
uint32_t rv32_gpio_irq_read_clear(rv32_gpio_t gpio);

#endif

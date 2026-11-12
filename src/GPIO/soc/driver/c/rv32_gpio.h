/* SPDX-License-Identifier: Apache-2.0
 * Driver C23 do GPIO. Os endereços de instância vêm do mapa da plataforma.
 * Máscaras são valores lógicos; a polaridade física é aplicada pelo hardware.
 */
#ifndef RV32_GPIO_H
#define RV32_GPIO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uintptr_t base;
    size_t pin_count;
} rv32_gpio_t;

/* Handles do not allocate memory or configure hardware.
 * Invalid/alignment/width arguments produce an invalid handle.
 * Use the actual number of implemented GPIO bits (not the MMIO window size).
 */
rv32_gpio_t rv32_gpio_new(uintptr_t base, size_t pin_count);
bool rv32_gpio_valid(rv32_gpio_t gpio);

typedef enum {
    RV32_GPIO_INPUT,
    RV32_GPIO_OUTPUT_PIN
} rv32_gpio_direction_t;

typedef enum {
    RV32_GPIO_IRQ_DISABLED,
    RV32_GPIO_IRQ_RISING_EDGE,
    RV32_GPIO_IRQ_FALLING_EDGE,
    RV32_GPIO_IRQ_BOTH_EDGES,
    RV32_GPIO_IRQ_HIGH_LEVEL,
    RV32_GPIO_IRQ_LOW_LEVEL
} rv32_gpio_irq_mode_t;

/* Pin indices are zero-based. Invalid arguments return false without MMIO.
 * Direction and IRQ configuration use read/modify/write: serialize callers.
 * Pin set/clear/toggle use the atomic hardware registers.
 */
bool rv32_gpio_pin_direction(rv32_gpio_t gpio, size_t pin,
                             rv32_gpio_direction_t direction);
bool rv32_gpio_pin_write(rv32_gpio_t gpio, size_t pin, bool high);
bool rv32_gpio_pin_toggle(rv32_gpio_t gpio, size_t pin);
bool rv32_gpio_pin_read(rv32_gpio_t gpio, size_t pin, bool *high);
bool rv32_gpio_pin_irq_configure(rv32_gpio_t gpio, size_t pin,
                                 rv32_gpio_irq_mode_t mode);
bool rv32_gpio_irq_contains(uint32_t snapshot, size_t pin);

/* Compatibility API for operations on whole register masks. */
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
void rv32_gpio_irq_configure(rv32_gpio_t gpio, uint32_t enabled, uint32_t rising,
                             uint32_t falling, uint32_t level);
void rv32_gpio_irq_enable(rv32_gpio_t gpio, uint32_t mask);
/* Retorna e limpa TODOS os eventos pendentes dessa instância em uma leitura.
 * Não há leitura sem efeito colateral nem escrita W1C no RTL atual.
 * Uma condição de nível persistente pode levantar o status novamente.
 */
uint32_t rv32_gpio_irq_read_clear(rv32_gpio_t gpio);

#endif

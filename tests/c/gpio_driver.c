/* Teste dos acessos do driver com MMIO em RAM. Os efeitos do hardware,
 * incluindo leitura que limpa IRQ, são exercitados nos testes RTL do GPIO.
 */
#include <assert.h>
#include <stdint.h>
#include "rv32_gpio.h"

int main(void)
{
    volatile uint32_t words[11] = {0};
    rv32_gpio_t gpio = {(uintptr_t)words};
    rv32_gpio_direction(gpio, 0xa5);
    assert(words[0] == 0xa5 && rv32_gpio_get_direction(gpio) == 0xa5);
    rv32_gpio_write(gpio, 0x81234567);
    assert(words[1] == 0x81234567 && rv32_gpio_read_output(gpio) == 0x81234567);
    rv32_gpio_set(gpio, 0x80);
    rv32_gpio_clear(gpio, 0x40);
    rv32_gpio_toggle(gpio, 0x20);
    assert(words[2] == 0x80 && words[3] == 0x40 && words[4] == 0x20);
    /* Ler os pinos deve usar outro registrador que a saída armazenada. */
    words[9] = 0x55;
    assert(rv32_gpio_read(gpio) == 0x55);
    rv32_gpio_irq_configure(gpio, 0x5, 0x1, 0x4, 0x4);
    assert(words[5] == 0x5 && words[6] == 0x1 && words[7] == 0x4 && words[10] == 0x4);
    words[8] = 0x5;
    assert(rv32_gpio_irq_read_clear(gpio) == 0x5);
    /* O driver não tenta limpar status por escrita; o RTL limpa na leitura. */
    assert(words[8] == 0x5);
    rv32_gpio_irq_enable(gpio, 0);
    assert(words[5] == 0);
    return 0;
}

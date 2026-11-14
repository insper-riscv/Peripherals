/*
 * Exemplo da UART serial com paridade e controle de fluxo por hardware.
 *
 * Configura 8E1 (paridade par, um bit de parada), liga o controle de fluxo
 * com o limiar de RTS em 8 bytes, envia uma linha e ecoa o que recebe,
 * contando os erros de linha. Serve a uma UART instanciada com
 * has_flow_control = true; sem o generic, UART_CONTROL_FLOW_ENABLE e o
 * limiar não existem (escritas ignoradas, leituras em zero) e o resto do
 * programa funciona igual.
 *
 * O endereço base vem da plataforma e é passado na compilação:
 *   riscv32-unknown-elf-gcc -std=c23 -O2 -DUART_BASE=0x... uart_flow.c
 *
 * Os registradores são de 32 bits, em endereços de palavra: TX_DATA 0,
 * RX_DATA 1, STATUS 2 e CONTROL 3.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifndef UART_BASE
#error "UART_BASE: endereço base da UART na plataforma (-DUART_BASE=0x...)"
#endif

/* Palavras de registrador. */
enum {
    UART_TX_DATA = 0,
    UART_RX_DATA = 1,
    UART_STATUS = 2,
    UART_CONTROL = 3,
};

/* Bits de STATUS. */
enum : uint32_t {
    UART_STATUS_RX_VALID = 1U << 0,
    UART_STATUS_TX_READY = 1U << 1,
    UART_STATUS_RX_OVERRUN = 1U << 2,
    UART_STATUS_TX_DROPPED = 1U << 3,
    UART_STATUS_TX_IDLE = 1U << 6,
    UART_STATUS_FRAME_ERROR = 1U << 7,
    UART_STATUS_PARITY_ERROR = 1U << 24,
    UART_STATUS_CTS_ACTIVE = 1U << 25,
    UART_STATUS_RTS_ACTIVE = 1U << 26,
};

/* Bits de CONTROL. */
enum : uint32_t {
    UART_CONTROL_PARITY_ENABLE = 1U << 3,
    UART_CONTROL_PARITY_ODD = 1U << 4,
    UART_CONTROL_STOP_BITS_2 = 1U << 5,
    UART_CONTROL_FLOW_ENABLE = 1U << 7,
    UART_CONTROL_RTS_THRESHOLD_SHIFT = 8,
};

/* Bits de erro de linha que o software limpa escrevendo um em STATUS. */
static constexpr uint32_t UART_LINE_ERRORS =
    UART_STATUS_FRAME_ERROR | UART_STATUS_PARITY_ERROR;

/* Limiar de RTS: RTS fica inativo com este número de bytes na fila de RX. */
static constexpr uint32_t RTS_THRESHOLD_BYTES = 8;

static volatile uint32_t *const uart = (volatile uint32_t *)UART_BASE;

/* Contadores dos erros de linha vistos desde o início. */
static uint32_t frame_errors;
static uint32_t parity_errors;

/* Configura 8E1 com controle de fluxo e limpa as flags de erro. */
static void uart_init(void)
{
    uart[UART_CONTROL] = UART_CONTROL_PARITY_ENABLE
        | UART_CONTROL_FLOW_ENABLE
        | (RTS_THRESHOLD_BYTES << UART_CONTROL_RTS_THRESHOLD_SHIFT);
    uart[UART_STATUS] = UART_LINE_ERRORS;
}

/* Enfileira um byte; com CTS inativo ele espera na fila de TX. */
static void uart_put(uint8_t byte)
{
    while ((uart[UART_STATUS] & UART_STATUS_TX_READY) == 0) {
    }
    uart[UART_TX_DATA] = byte;
}

/* Envia uma cadeia e espera o último bit sair pelo pino. */
static void uart_write(const char *text)
{
    for (const char *p = text; *p != '\0'; ++p) {
        uart_put((uint8_t)*p);
    }
    while ((uart[UART_STATUS] & UART_STATUS_TX_IDLE) == 0) {
    }
}

/* Lê um byte da fila de RX; devolve falso se ela está vazia. */
static bool uart_get(uint8_t *byte)
{
    uint32_t status = uart[UART_STATUS];

    if ((status & UART_STATUS_RX_VALID) == 0) {
        return false;
    }
    *byte = (uint8_t)uart[UART_RX_DATA];

    /* As flags são persistentes: conta e limpa. */
    if ((status & UART_STATUS_FRAME_ERROR) != 0) {
        ++frame_errors;
    }
    if ((status & UART_STATUS_PARITY_ERROR) != 0) {
        ++parity_errors;
    }
    uart[UART_STATUS] = status & UART_LINE_ERRORS;
    return true;
}

int main(void)
{
    uint8_t byte;

    uart_init();
    uart_write("uart 8E1 com RTS e CTS\r\n");

    for (;;) {
        if (uart_get(&byte)) {
            uart_put(byte);
        }
    }
}

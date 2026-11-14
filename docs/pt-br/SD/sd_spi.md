# Controlador de cartão SD no modo SPI

🌐 [Português](../../pt-br/SD/sd_spi.md) · [English](../../en/SD/sd_spi.md)

## 1. O que é

Periférico de barramento que conduz um cartão SD ou micro SD pelo modo SPI. O software enfileira bytes, o mestre SPI os troca com o cartão e cada byte transmitido devolve um byte recebido, também em fila. O periférico tem seleção de chip por registrador, divisor de clock configurável por parâmetro e por registrador, e uma interrupção de nível com quatro causas.

O periférico é composto por três blocos.

| Bloco | Função |
| :--- | :--- |
| `sd_spi_phy` | Mestre SPI de um byte no modo 0 (SCLK em repouso baixo, MOSI muda na borda de descida e o cartão amostra na de subida), com o divisor capturado no início de cada byte |
| `uart_fifo` | Fila síncrona de bytes, uma instância para a transmissão e outra para a recepção |
| `sd_spi` | Topo com o sincronizador da linha MISO, os registradores, as marcas persistentes e a interrupção |

## 2. Pinos e placas

Nenhum dos manuais lista a função de cada pino no modo SPI; o mapeamento é o da especificação do cartão SD, em que o comando vira MOSI, o dado 0 vira MISO e o dado 3 vira a seleção de chip. As duas placas ligam o conector ao FPGA em 3,3 V, sem pino de detecção de cartão (a DE2-115 tem apenas o de proteção contra escrita, `SD_WP_N`).

| Porta do periférico | Sentido | Função SPI | Pino da DE0-CV | Pino da DE2-115 |
| :--- | :--- | :--- | :--- | :--- |
| `o_sd_sclk` | saída | SCLK | `SD_CLK` (`PIN_H11`) | `SD_CLK` (`PIN_AE13`) |
| `o_sd_mosi` | saída | MOSI | `SD_CMD` (`PIN_B11`) | `SD_CMD` (`PIN_AD14`) |
| `i_sd_miso` | entrada | MISO | `SD_DATA0` (`PIN_K9`) | `SD_DAT[0]` (`PIN_AE14`) |
| `o_sd_cs_n` | saída | Seleção de chip, ativa em nível baixo | `SD_DATA3` (`PIN_C11`) | `SD_DAT[3]` (`PIN_AC14`) |
| nenhuma | n/a | Não usadas no modo SPI | `SD_DATA1` (`PIN_D12`), `SD_DATA2` (`PIN_E12`) | `SD_DAT[1]` (`PIN_AF13`), `SD_DAT[2]` (`PIN_AB14`), `SD_WP_N` (`PIN_AF14`) |

As linhas não usadas ficam como entradas no topo da plataforma.

## 3. Parâmetros e portas

| Parâmetro | Padrão | Significado |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Frequência do clock do módulo, em hertz |
| `init_sclk_hz` | 400000 | Frequência de SCLK depois do reset; a inicialização do cartão exige no máximo 400 kHz |
| `rx_fifo_depth` | 32 | Bytes na fila de recepção (no máximo 255) |
| `tx_fifo_depth` | 32 | Bytes na fila de transmissão (no máximo 255) |

O divisor de reset vale

$$ \text{DIVIDER}_{reset} = \left\lceil \frac{\text{clock\_hz}}{2 \cdot \text{init\_sclk\_hz}} \right\rceil - 1 $$

e a frequência de SCLK é

$$ f_{SCLK} = \frac{\text{clock\_hz}}{2 \cdot (\text{DIVIDER} + 1)} $$

O menor divisor aceito é 1, porque a linha MISO atravessa dois flip-flops de sincronização e é amostrada na borda de descida de SCLK.

As portas do barramento são `i_clk`, `i_rst` (síncrono, nível alto), `i_write`, `i_read`, `i_address` (3 bits, endereço de palavra), `i_data_in`, `o_data_out` e `o_irq`, mais as quatro portas de pino da seção 2. Os registradores têm 32 bits e a janela do bloco ocupa 5 palavras.

## 4. Registradores

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `TX_DATA` | W | n/a | Bits 7:0, byte enfileirado para transmissão; a escrita com a fila cheia é descartada e marca `TX_DROPPED` |
| 1 | `RX_DATA` | R | 0 | Bits 7:0, byte recebido mais antigo; a leitura o remove da fila e devolve zero com a fila vazia |
| 2 | `STATUS` | R/W1C | `0x6` | Estado e marcas persistentes (tabela abaixo) |
| 3 | `CONTROL` | R/W | 0 | Seleção de chip e habilitação das interrupções (tabela abaixo) |
| 4 | `DIVIDER` | R/W | seção 3 | Bits 15:0, divisor de clock de SCLK; vale a partir do próximo byte |

Bits de `STATUS`. Escrever 1 num bit W1C o limpa, e um evento novo no mesmo ciclo tem prioridade sobre a limpeza.

| Bit | Nome | Acesso | Significado |
| ---: | :--- | :--- | :--- |
| 0 | `RX_VALID` | R | Há pelo menos um byte na fila de recepção |
| 1 | `TX_READY` | R | A fila de transmissão tem espaço |
| 2 | `TX_EMPTY` | R | A fila de transmissão está vazia (o último byte pode ainda estar em andamento) |
| 3 | `BUSY` | R | Um byte está em andamento, acabou de terminar ou a fila de transmissão não está vazia |
| 4 | `RX_FULL` | R | A fila de recepção está cheia |
| 5 | `DONE` | W1C | Um byte terminou com a fila de transmissão vazia |
| 6 | `RX_OVERRUN` | W1C | Um byte recebido foi descartado porque a fila de recepção estava cheia |
| 7 | `TX_DROPPED` | W1C | Uma escrita em `TX_DATA` foi descartada porque a fila estava cheia |
| 15:8 | `RX_LEVEL` | R | Bytes na fila de recepção |
| 23:16 | `TX_LEVEL` | R | Bytes na fila de transmissão |

Bits de `CONTROL`.

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `CS_ASSERT` | Quando 1, a linha de seleção de chip fica em nível baixo |
| 1 | `RX_IRQ_ENABLE` | Interrupção enquanto a fila de recepção não está vazia |
| 2 | `TX_EMPTY_IRQ_ENABLE` | Interrupção enquanto a fila de transmissão está vazia |
| 3 | `DONE_IRQ_ENABLE` | Interrupção enquanto `DONE` vale 1 |
| 4 | `ERROR_IRQ_ENABLE` | Interrupção enquanto `RX_OVERRUN` ou `TX_DROPPED` vale 1 |

A saída `o_irq` é de nível e é a soma lógica das quatro causas habilitadas. As causas de fila param quando a condição some (leitura de `RX_DATA`, escrita em `TX_DATA`), e as demais param quando o software limpa a marca.

## 5. Uso pelo software

Cada byte escrito em `TX_DATA` gera um byte em `RX_DATA`, então o software lê um byte para cada byte que envia. Para apenas receber, envia-se `0xFF`. Mudar `CS_ASSERT` ou `DIVIDER` só é seguro com `BUSY` em zero, porque o byte em andamento ainda usa o valor anterior.

### 5.1. Sequência de inicialização

O cartão entra em modo SPI quando recebe o CMD0 com a seleção de chip em nível baixo, e a sequência abaixo é a da especificação para um cartão SDHC ou SDXC.

| Passo | Ação | Resposta esperada |
| ---: | :--- | :--- |
| 1 | Com `CS_ASSERT` em 0 e SCLK em no máximo 400 kHz, enviar 10 bytes `0xFF` (80 clocks, mais que os 74 exigidos) | n/a |
| 2 | Ligar `CS_ASSERT` e enviar CMD0 (`0x40 0x00000000`, CRC `0x95`) | R1 `0x01` (ocioso) |
| 3 | CMD8 (`0x48 0x000001AA`, CRC `0x87`) | R1 `0x01` seguido de 4 bytes, dos quais os 12 bits baixos valem `0x1AA` |
| 4 | Repetir CMD55 (`0x77 0x00000000`) e ACMD41 (`0x69 0x40000000`) até a resposta ser R1 `0x00` | R1 `0x01` enquanto inicializa, depois `0x00` |
| 5 | CMD58 (`0x7A 0x00000000`) | R1 `0x00` seguido do OCR de 4 bytes; o bit 30 (CCS) em 1 indica que o endereço é o número do setor |
| 6 | Aumentar a frequência escrevendo `DIVIDER` com `BUSY` em zero | n/a |

Todo comando é o byte `0x40 | índice`, o argumento de 32 bits com o byte mais significativo primeiro e o byte de CRC7 com o bit 0 em 1. Depois do CMD0 e do CMD8 o cartão ignora o CRC no modo SPI. A resposta R1 chega até 8 bytes depois do comando, e até lá o cartão devolve `0xFF`.

### 5.2. Leitura de um setor (CMD17)

1. Enviar CMD17 com o número do setor como argumento e esperar R1 `0x00`.
2. Enviar `0xFF` até receber o token `0xFE`.
3. Receber 512 bytes de dados e depois 2 bytes de CRC16 (polinômio $x^{16} + x^{12} + x^5 + 1$, valor inicial zero, byte mais significativo primeiro).

### 5.3. Escrita de um setor (CMD24)

1. Enviar CMD24 com o número do setor e esperar R1 `0x00`.
2. Enviar um byte `0xFF`, o token `0xFE`, os 512 bytes de dados e os 2 bytes de CRC16.
3. Receber o byte de resposta de dados; os 5 bits baixos valendo `0x05` indicam dado aceito.
4. Enviar `0xFF` enquanto o cartão devolver `0x00` (ocupado) e prosseguir quando devolver `0xFF`.

### 5.4. Exemplo em C

O exemplo inicializa o cartão e lê um setor, com C23 e polling. A constante `SD_BASE` recebe o endereço do bloco na plataforma.

```c
#include <stdbool.h>
#include <stdint.h>

/* Base do periférico, definida pela plataforma. */
#define SD_BASE ((volatile uint32_t *)0x40000000u)

enum { TX_DATA, RX_DATA, STATUS, CONTROL, DIVIDER };
enum { RX_VALID = 1u << 0, BUSY = 1u << 3 };
enum { CS_ASSERT = 1u << 0 };

#define SD_FAST_DIVIDER 1u /* SCLK = clock / 4 depois da inicialização. */

/* Troca um byte e devolve o byte recebido. */
static uint8_t spi_xfer(uint8_t value)
{
    SD_BASE[TX_DATA] = value;
    while ((SD_BASE[STATUS] & RX_VALID) == 0) {
    }
    return (uint8_t)SD_BASE[RX_DATA];
}

/* Envia um comando e devolve o R1, ou 0xFF se o cartão não responder. */
static uint8_t sd_command(uint8_t index, uint32_t argument, uint8_t crc)
{
    spi_xfer(0xFF);
    spi_xfer((uint8_t)(0x40u | index));
    for (int shift = 24; shift >= 0; shift -= 8) {
        spi_xfer((uint8_t)(argument >> shift));
    }
    spi_xfer(crc);
    uint8_t r1 = 0xFF;
    for (int attempt = 0; attempt < 8 && r1 == 0xFF; attempt++) {
        r1 = spi_xfer(0xFF);
    }
    return r1;
}

/* Inicializa um cartão SDHC no modo SPI. Devolve true em caso de sucesso. */
bool sd_init(void)
{
    SD_BASE[CONTROL] = 0; /* CS alto */
    for (int i = 0; i < 10; i++) { /* 80 clocks, mais que os 74 exigidos */
        spi_xfer(0xFF);
    }
    SD_BASE[CONTROL] = CS_ASSERT;

    if (sd_command(0, 0, 0x95) != 0x01) { /* CMD0 */
        return false;
    }
    if (sd_command(8, 0x1AA, 0x87) != 0x01) { /* CMD8 */
        return false;
    }
    uint32_t r7 = 0;
    for (int i = 0; i < 4; i++) {
        r7 = (r7 << 8) | spi_xfer(0xFF);
    }
    if ((r7 & 0xFFF) != 0x1AA) {
        return false;
    }

    uint8_t r1 = 0xFF;
    for (int attempt = 0; attempt < 100000 && r1 != 0x00; attempt++) {
        sd_command(55, 0, 0x65); /* CMD55 */
        r1 = sd_command(41, 0x40000000u, 0x77); /* ACMD41 com HCS */
    }
    if (r1 != 0x00) {
        return false;
    }

    if (sd_command(58, 0, 0xFD) != 0x00) { /* CMD58 */
        return false;
    }
    uint32_t ocr = 0;
    for (int i = 0; i < 4; i++) {
        ocr = (ocr << 8) | spi_xfer(0xFF);
    }
    if ((ocr & 0x40000000u) == 0) { /* CCS: o endereço é o número do setor */
        return false;
    }

    SD_BASE[DIVIDER] = SD_FAST_DIVIDER;
    return true;
}

/* Lê o setor de 512 bytes em buffer. Devolve true se o CRC16 conferir. */
bool sd_read_sector(uint32_t sector, uint8_t buffer[static 512])
{
    if (sd_command(17, sector, 0xFF) != 0x00) { /* CMD17 */
        return false;
    }
    uint8_t token = 0xFF;
    for (int attempt = 0; attempt < 100000 && token == 0xFF; attempt++) {
        token = spi_xfer(0xFF);
    }
    if (token != 0xFE) {
        return false;
    }
    uint16_t crc = 0;
    for (int i = 0; i < 512; i++) {
        buffer[i] = spi_xfer(0xFF);
        crc ^= (uint16_t)buffer[i] << 8;
        for (int bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000u) ? (uint16_t)((crc << 1) ^ 0x1021u)
                                  : (uint16_t)(crc << 1);
        }
    }
    uint16_t received = (uint16_t)(spi_xfer(0xFF) << 8);
    received |= spi_xfer(0xFF);
    spi_xfer(0xFF);
    return received == crc;
}

/* Termina o acesso: espera o mestre parar e solta o CS. */
void sd_release(void)
{
    while ((SD_BASE[STATUS] & BUSY) != 0) {
    }
    SD_BASE[CONTROL] = 0;
}
```

## 6. Verificação

O teste de entidade liga o periférico a um modelo de cartão SD no modo SPI que responde ao CMD0, CMD8, CMD55, ACMD41, CMD58, CMD17 e CMD24, confere o CRC7 dos comandos CMD0 e CMD8, o CRC16 do setor escrito e os 74 clocks iniciais com a seleção em nível alto. Os casos cobrem o reset, os registradores, o período de SCLK para dois divisores, a inicialização, a leitura e a escrita de setor, o estouro das filas e cada causa de interrupção. A prova formal verifica os registradores `CONTROL` e `DIVIDER`, a seleção de chip, a interrupção, as marcas persistentes, o reset e o byte de oito bordas de SCLK, com mutantes que ela precisa reprovar.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

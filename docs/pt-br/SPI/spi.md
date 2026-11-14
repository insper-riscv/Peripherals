# Mestre SPI genérico

🌐 [Português](../../pt-br/SPI/spi.md) · [English](../../en/SPI/spi.md)

## 1. O que é

Mestre SPI de uma palavra, com os quatro modos (CPOL e CPHA), palavras de 1 a 32 bits, bit mais significativo ou menos significativo primeiro, divisor de clock e solta do fio de dados para os escravos de três fios. Sobre ele há um periférico de barramento com filas de transmissão e recepção, de uma a 64 linhas de seleção de chip (uma ativa por vez) e interrupção. O cartão SD, o ADC128S022, o LTC2308 e o ADXL345 reaproveitam o mesmo mestre.

| Bloco | Função |
| :--- | :--- |
| `spi_master` | Mestre de uma palavra por pedido de início, sem filas e sem seleção de chip; é o bloco que os controladores de chip instanciam |
| `uart_fifo` | Fila síncrona, uma instância para a transmissão (palavra mais o bit de escuta) e outra para a recepção |
| `spi` | Topo mapeado em memória com o sincronizador de MISO, os registradores, as linhas de seleção de chip, as marcas persistentes e a interrupção |

## 2. Mestre de uma palavra (`spi_master`)

### 2.1. Modos

Com CPOL o nível de repouso de SCLK é escolhido, e com CPHA a fase. A borda leading é a que sai do repouso e a borda trailing é a que volta a ele.

| Modo | CPOL | CPHA | SCLK em repouso | MOSI muda na borda | O escravo amostra na borda | O mestre amostra na borda |
| ---: | ---: | ---: | :--- | :--- | :--- | :--- |
| 0 | 0 | 0 | baixo | trailing (descida) | leading (subida) | trailing (descida) |
| 1 | 0 | 1 | baixo | leading (subida) | trailing (descida) | trailing (descida) |
| 2 | 1 | 0 | alto | trailing (subida) | leading (descida) | trailing (subida) |
| 3 | 1 | 1 | alto | leading (descida) | trailing (subida) | trailing (subida) |

O primeiro bit já está em MOSI antes da primeira borda leading nos dois valores de CPHA. O mestre amostra MISO sempre na borda trailing, o instante mais tardio do bit antes da mudança seguinte do escravo, e por isso MISO deve chegar sincronizada com `i_clk` (o periférico `spi` e cada controlador de chip já a passam por dois flip-flops).

### 2.2. Palavra, ordem e tempo

Cada palavra começa com uma meia-espera em repouso, tem $n$ períodos completos de SCLK e termina na última borda trailing, que devolve SCLK ao nível de repouso. Com $d$ o divisor, o período de SCLK e as bordas valem

$$ T_{SCLK} = 2 \cdot (d + 1) \ \text{ciclos de } i\_clk, \qquad N_{bordas} = 2n $$

O modo, a largura $n$ (de 1 ao máximo do parâmetro `word_width`; um pedido fora da faixa vira o extremo mais próximo), a ordem dos bits e o divisor são capturados no pedido de início, e um pedido durante uma palavra é ignorado. A palavra recebida fica alinhada à direita em `o_rx_data` desde o pulso `o_done` até a palavra seguinte. Fora da palavra SCLK acompanha `i_cpol` e MOSI fica em nível alto, então o modo só deve mudar com a seleção de chip desativada. Com `i_tx_drive` em 0 a palavra só escuta, `o_mosi_oe` cai durante ela e continua em 0 até a palavra seguinte, para o fio de dados compartilhado dos escravos de três fios.

| Parâmetro | Padrão | Significado |
| :--- | ---: | :--- |
| `divider_width` | 16 | Largura do divisor, em bits |
| `word_width` | 32 | Largura máxima da palavra, de 1 a 32 |

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_cpol`, `i_cpha` | entrada | Modo SPI |
| `i_lsb_first` | entrada | Em 1 o bit menos significativo vai primeiro |
| `i_word_bits` | entrada | Bits da palavra, 6 bits |
| `i_divider` | entrada | Metade do período de SCLK menos um, em ciclos |
| `i_tx_drive` | entrada | Em 0 a palavra só escuta |
| `i_start`, `i_tx_data` | entrada | Pedido de início e palavra a enviar |
| `o_busy`, `o_done`, `o_rx_data` | saída | Palavra em andamento, pulso de fim e palavra recebida |
| `o_sclk`, `o_mosi`, `o_mosi_oe`, `i_miso` | saída e entrada | Pinos SPI, com a habilitação do driver de MOSI |

O divisor mínimo é 1 com CPHA 0. Com CPHA 1 o dado do escravo só aparece depois da borda leading e atravessa os dois flip-flops de sincronização, então o menor divisor é 2 com um escravo ideal, e o atraso do chip e da placa acrescenta ciclos. A relação entre SCLK e o clock fica então

$$ f_{SCLK} = \frac{f_{clk}}{2 \cdot (d + 1)} $$

## 3. Periférico de barramento (`spi`)

### 3.1. Parâmetros e portas

| Parâmetro | Padrão | Significado |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Frequência do clock do módulo, em hertz |
| `reset_sclk_hz` | 1000000 | Frequência de SCLK depois do reset, em hertz |
| `word_width` | 32 | Largura máxima da palavra, em bits |
| `cs_count` | 1 | Linhas de seleção de chip, de 1 a 64 |
| `rx_fifo_depth` | 16 | Palavras na fila de recepção (no máximo 255) |
| `tx_fifo_depth` | 16 | Palavras na fila de transmissão (no máximo 255) |

O divisor de reset é $\lceil clock\_hz / (2 \cdot reset\_sclk\_hz) \rceil - 1$. As portas do barramento são `i_clk`, `i_rst` (síncrono, nível alto), `i_write`, `i_read`, `i_address` (3 bits, endereço de palavra), `i_data_in`, `o_data_out` e `o_irq`, mais os pinos `o_sclk`, `o_mosi`, `o_mosi_oe`, `i_miso` e `o_cs_n` (uma linha por seleção, ativa em nível baixo). A janela do bloco ocupa 6 palavras.

### 3.2. Registradores

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `TX_DATA` | W | n/a | Palavra enfileirada para transmissão; com a fila cheia é descartada e marca `TX_DROPPED` |
| 1 | `RX_DATA` | R | 0 | Palavra recebida mais antiga, removida da fila pela leitura; devolve zero com a fila vazia |
| 2 | `STATUS` | R/W1C | `0x6` | Estado e marcas persistentes |
| 3 | `CONTROL` | R/W | `0x800` | Seleção de chip, interrupções, modo, ordem e largura |
| 4 | `DIVIDER` | R/W | seção 3.1 | Bits 15:0, divisor de clock; vale a partir da palavra seguinte |
| 5 | `TX_LISTEN` | W | n/a | Como `TX_DATA`, mas o mestre solta MOSI durante a palavra |

Bits de `STATUS`. Escrever 1 num bit W1C o limpa, e um evento novo no mesmo ciclo tem prioridade sobre a limpeza.

| Bit | Nome | Acesso | Significado |
| ---: | :--- | :--- | :--- |
| 0 | `RX_VALID` | R | Há pelo menos uma palavra na fila de recepção |
| 1 | `TX_READY` | R | A fila de transmissão tem espaço |
| 2 | `TX_EMPTY` | R | A fila de transmissão está vazia (a última palavra pode estar em andamento) |
| 3 | `BUSY` | R | Uma palavra está em andamento, acabou de terminar ou a fila de transmissão não está vazia |
| 4 | `RX_FULL` | R | A fila de recepção está cheia |
| 5 | `DONE` | W1C | Uma palavra terminou com a fila de transmissão vazia |
| 6 | `RX_OVERRUN` | W1C | Uma palavra recebida foi descartada com a fila de recepção cheia |
| 7 | `TX_DROPPED` | W1C | Uma escrita foi descartada com a fila de transmissão cheia |
| 15:8 | `RX_LEVEL` | R | Palavras na fila de recepção |
| 23:16 | `TX_LEVEL` | R | Palavras na fila de transmissão |

Bits de `CONTROL`.

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `CS_ASSERT` | Em 1 a linha escolhida por `CS_SELECT` fica em nível baixo |
| 1 | `RX_IRQ_ENABLE` | Interrupção enquanto a fila de recepção não está vazia |
| 2 | `TX_EMPTY_IRQ_ENABLE` | Interrupção enquanto a fila de transmissão está vazia |
| 3 | `DONE_IRQ_ENABLE` | Interrupção enquanto `DONE` vale 1 |
| 4 | `ERROR_IRQ_ENABLE` | Interrupção enquanto `RX_OVERRUN` ou `TX_DROPPED` vale 1 |
| 5 | `CPOL` | Nível de repouso de SCLK |
| 6 | `CPHA` | Fase |
| 7 | `LSB_FIRST` | Em 1 o bit menos significativo vai primeiro |
| 13:8 | `WORD_BITS` | Bits da palavra, de 1 a `word_width` (reset 8) |
| 21:16 | `CS_SELECT` | Índice da linha de seleção de chip; um índice sem linha deixa todas em nível alto |

A saída `o_irq` é de nível e é a soma lógica das quatro causas habilitadas. As causas de fila param quando a condição some, e as demais param quando o software limpa a marca.

## 4. Uso pelo software

Cada palavra escrita em `TX_DATA` gera uma palavra em `RX_DATA`, então o software lê uma palavra para cada uma que envia. Para apenas receber, envia-se qualquer valor. Mudar `CS_ASSERT`, `CPOL` ou `DIVIDER` só é seguro com `BUSY` em zero. Para trocar de escravo, desliga-se `CS_ASSERT`, programa-se o modo e `CS_SELECT` do novo escravo e liga-se `CS_ASSERT` de novo.

O exemplo em C troca palavras de 12 bits com um escravo de modo 3 na linha 2, e lê com `TX_LISTEN` os bytes de um escravo de três fios.

```c
#include <stdint.h>

/* Base do periférico, definida pela plataforma. */
#define SPI_BASE ((volatile uint32_t *)0x40000000u)

enum { TX_DATA, RX_DATA, STATUS, CONTROL, DIVIDER, TX_LISTEN };
enum { RX_VALID = 1u << 0, BUSY = 1u << 3 };
enum {
    CS_ASSERT = 1u << 0,
    CPOL = 1u << 5,
    CPHA = 1u << 6,
    LSB_FIRST = 1u << 7,
};

#define WORD_BITS(n) ((uint32_t)(n) << 8)
#define CS_SELECT(i) ((uint32_t)(i) << 16)

/* Programa o modo 3, palavras de 12 bits, bit mais significativo primeiro. */
void spi_select_slave_2(void)
{
    while ((SPI_BASE[STATUS] & BUSY) != 0) {
    }
    SPI_BASE[CONTROL] = CPOL | CPHA | WORD_BITS(12) | CS_SELECT(2);
    SPI_BASE[DIVIDER] = 24; /* SCLK = clock / 50 */
    SPI_BASE[CONTROL] |= CS_ASSERT;
}

/* Espera uma palavra recebida e a devolve. */
static uint32_t spi_wait_rx(void)
{
    while ((SPI_BASE[STATUS] & RX_VALID) == 0) {
    }
    return SPI_BASE[RX_DATA];
}

/* Troca uma palavra e devolve a palavra recebida. */
uint32_t spi_xfer(uint32_t word)
{
    SPI_BASE[TX_DATA] = word;
    return spi_wait_rx();
}

/* Lê count bytes de um escravo de três fios depois do comando cmd. */
void spi_read_three_wire(uint8_t cmd, uint8_t *out, int count)
{
    SPI_BASE[CONTROL] = CPOL | CPHA | WORD_BITS(8) | CS_SELECT(2) | CS_ASSERT;
    (void)spi_xfer(cmd);
    for (int i = 0; i < count; i++) {
        SPI_BASE[TX_LISTEN] = 0;
        out[i] = (uint8_t)spi_wait_rx();
    }
    SPI_BASE[CONTROL] = 0;
}
```

## 5. Quem usa o mestre

O mestre não tem pino próprio, e cada controlador de chip leva os pinos da sua placa.

| Controlador | Documento | Modo SPI | Largura da palavra |
| :--- | :--- | :--- | ---: |
| `sd_spi` | [sd_spi.md](../SD/sd_spi.md) | 0 | 8 |
| `adc128s022` | [adc128s022.md](../ADC/adc128s022.md) | 3 | 16 |
| `ltc2308` | [ltc2308.md](../ADC/ltc2308.md) | 0 | 12 |
| `adxl345` | [adxl345.md](../ADXL345/adxl345.md) | 3 | 8 |

## 6. Verificação

O teste de entidade do `spi_master` liga o mestre a um escravo simulado nos quatro modos, em larguras de 1, 5, 8, 12, 16, 24 e 32 bits e nas duas ordens, e confere o que o escravo amostrou em MOSI, o que o mestre recebeu, o número de bordas, o período para três divisores, o nível de repouso, o pedido durante uma palavra, a palavra de escuta, a palavra seguida de outra e o limite da largura. O teste do periférico cobre o reset, os registradores, as filas, as três linhas de seleção, dois escravos de modos diferentes, a palavra de escuta, as marcas de erro e as causas de interrupção. A prova formal do `spi_master` cobre os quatro modos com palavras de até 4 bits e as duas ordens, bit a bit em MOSI e em MISO, e é a mesma que o `sd_spi` usa em modo 0.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

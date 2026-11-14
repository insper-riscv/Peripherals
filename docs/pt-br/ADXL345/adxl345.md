# Controlador do acelerômetro ADXL345 por SPI (DE0-Nano e DE10-Lite)

🌐 [Português](../../pt-br/ADXL345/adxl345.md) · [English](../../en/ADXL345/adxl345.md)

## 1. O que é

Controlador de barramento do acelerômetro de três eixos ADXL345 pelo SPI. Ao ser habilitado, configura o chip (taxa, faixa, resolução e interrupção de dado pronto) e depois lê, em intervalos fixos ou a cada aviso de dado pronto em INT1, os seis bytes dos eixos X, Y e Z. Cada eixo vira um registrador de 32 bits com o valor de 16 bits em complemento de dois estendido em sinal (13 bits úteis na faixa de 16 g com resolução plena). O chip também fala I2C, e esse acesso é por software com o mestre I2C do repositório, sem passar por este controlador.

| Bloco | Função |
| :--- | :--- |
| `spi_master` | Mestre SPI de uma palavra, aqui no modo 3 com palavras de 8 bits |
| `adxl345` | Sequenciador de configuração e de leitura em rajada, registradores dos eixos, temporização e interrupção |

## 2. Pinos e placas

### 2.1. DE0-Nano

O manual (seção 3.7, tabela 3-10) liga o ADXL345 às linhas I2C_SCLK e I2C_SDAT (compartilhadas com o EEPROM, que a tabela descreve como "EEPROM clock" e "EEPROM data"), a G_SENSOR_CS_N e a G_SENSOR_INT. O manual diz que o chip se acessa por SPI de 3 fios ou por I2C, então o SPI nesta placa é o de três fios, com o dado de ida e volta no mesmo pino.

| Porta do periférico | Função no SPI de três fios | Nome no manual | Pino do FPGA |
| :--- | :--- | :--- | :--- |
| `o_adxl_sclk` | SCLK | `I2C_SCLK` | `PIN_F2` |
| `o_adxl_mosi` e `o_adxl_mosi_oe` com `i_adxl_miso` | SDIO, bidirecional | `I2C_SDAT` | `PIN_F1` |
| `o_adxl_cs_n` | Seleção de chip | `G_SENSOR_CS_N` | `PIN_G5` |
| `i_adxl_int1` | Interrupção de dado pronto | `G_SENSOR_INT` | `PIN_M2` |

Todos em 3,3 V. O pino bidirecional é montado no topo da plataforma, com `o_adxl_mosi` quando `o_adxl_mosi_oe` vale 1 e em alta impedância caso contrário, e `i_adxl_miso` lê o próprio pino. O manual não diz o endereço I2C do chip nesta placa.

### 2.2. DE10-Lite

O manual (seção 3.10, tabela 3-13) lista os seis pinos. Com GSENSOR_CS_n em nível alto o chip fica em I2C, e em nível baixo em SPI. A seção 5.5 do manual usa o SPI de três fios e liga o bit SPI do registrador 0x31 (`DATA_FORMAT`) antes de ler. O manual descreve as saídas como 16 bits em complemento de dois.

| Porta do periférico | Função | Nome no manual | Pino do FPGA |
| :--- | :--- | :--- | :--- |
| `o_adxl_sclk` | SCLK (SPI de 3 e de 4 fios) | `GSENSOR_SCLK` | `PIN_AB15` |
| `o_adxl_mosi` | SDI no de 4 fios; SDIO no de 3 fios | `GSENSOR_SDI` | `PIN_V11` |
| `i_adxl_miso` | SDO no de 4 fios | `GSENSOR_SDO` | `PIN_V12` |
| `o_adxl_cs_n` | Seleção de chip | `GSENSOR_CS_n` | `PIN_AB16` |
| `i_adxl_int1` | Interrupção 1 | `GSENSOR_INT1` | `PIN_Y14` |
| nenhuma | Interrupção 2 | `GSENSOR_INT2` | `PIN_Y13` |

Todos em 3,3 V LVTTL. Em I2C o manual dá o endereço de 7 bits 0x1D com GSENSOR_SDO em nível alto e 0x53 com ele em nível baixo (0x3A e 0x3B, ou 0xA6 e 0xA7, com o bit de leitura ou escrita). Com o parâmetro `three_wire` em verdadeiro o controlador liga o bit SPI e a plataforma deve ligar `i_adxl_miso` ao pino SDI; em falso usa os quatro fios, e `i_adxl_miso` lê SDO.

## 3. Parâmetros e portas

| Parâmetro | Padrão | Significado |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Frequência do clock do módulo, em hertz |
| `sclk_hz` | 1000000 | Frequência de SCLK depois do reset, em hertz |
| `sample_hz` | 100 | Amostras por segundo depois do reset, quando o intervalo é por tempo |
| `cs_high_ns` | 300 | Intervalo mínimo com a seleção de chip em nível alto, em nanossegundos |
| `three_wire` | verdadeiro | Verdadeiro com o fio de dados compartilhado (liga o bit SPI de `DATA_FORMAT`) |

O divisor de reset é $\lceil clock\_hz / (2 \cdot sclk\_hz) \rceil - 1$, e o intervalo de reset entre amostras é $clock\_hz / sample\_hz$ ciclos. As portas do barramento são `i_clk`, `i_rst`, `i_write`, `i_address` (3 bits), `i_data_in`, `o_data_out` e `o_irq`, mais os pinos da seção 2 (`o_adxl_cs_n`, `o_adxl_sclk`, `o_adxl_mosi`, `o_adxl_mosi_oe`, `i_adxl_miso` e `i_adxl_int1`). A janela do bloco ocupa 8 palavras e não há efeito de leitura.

## 4. Sequência

Com `ENABLE` em 1, e depois de qualquer escrita em `CONTROL`, o controlador repete a configuração, e o chip só mede depois do último passo.

| Passo | Transação (comando, dado) | Efeito |
| ---: | :--- | :--- |
| 1 | leitura de `DEVID` (0x00) | O byte lido fica no registrador `DEVID` |
| 2 | escrita de `BW_RATE` (0x2C) | Código de taxa de `RATE` |
| 3 | escrita de `DATA_FORMAT` (0x31) | Bit SPI com `three_wire`, `FULL_RES` e `RANGE` |
| 4 | escrita de `INT_ENABLE` (0x2E) | 0x80, dado pronto (em INT1 por padrão) |
| 5 | escrita de `POWER_CTL` (0x2D) | 0x08, medição |
| 6 | leitura em rajada a partir de `DATAX0` (0x32), comando 0xF2 | Seis bytes, X, Y e Z, byte baixo primeiro |

A leitura em rajada repete a cada `PERIOD` ciclos ou, com `USE_INT1`, enquanto INT1 estiver em nível alto. Cada transação é uma palavra de comando e as palavras de dado, no modo 3 com a seleção de chip em nível baixo, e com o fio compartilhado o mestre solta o pino durante os seis bytes lidos.

### 4.1. Origem de cada parâmetro

A folha de dados do ADXL345 não está no repositório, então só o que o manual diz é confirmado.

| Item | Origem |
| :--- | :--- |
| Pinos, SPI de 3 fios ou I2C, saída de 16 bits em complemento de dois, CS alto igual a I2C, bit SPI no registrador 0x31, endereços I2C | Confirmado pelos manuais (DE0-Nano seção 3.7, DE10-Lite seções 3.10 e 5.5) |
| Modo 3, formato do comando (leitura, rajada, endereço de 6 bits) | Não confirmado; da folha de dados, de memória |
| Endereços 0x00, 0x2C, 0x2D, 0x2E, 0x31 e 0x32 a 0x37 e seus valores | Não confirmado; da folha de dados, de memória |
| `DEVID` igual a 0xE5 | Não confirmado; o controlador só guarda o byte lido |
| SCLK de até 5 MHz, intervalo mínimo com CS alto, resolução por faixa | Não confirmado; o controlador usa valores conservadores |

## 5. Registradores

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `X` | R | 0 | Eixo X, 16 bits em complemento de dois estendidos em sinal |
| 1 | `Y` | R | 0 | Eixo Y |
| 2 | `Z` | R | 0 | Eixo Z |
| 3 | `STATUS` | R/W1C | 0 | Estado e marca de amostra (tabela abaixo) |
| 4 | `CONTROL` | R/W | `0xA00` | Habilitação, interrupção, faixa, resolução, disparo e taxa |
| 5 | `PERIOD` | R/W | seção 3 | Bits 23:0, ciclos entre amostras sem `USE_INT1` |
| 6 | `DEVID` | R | 0 | Bits 7:0, último `DEVID` lido |
| 7 | `DIVIDER` | R/W | seção 3 | Bits 15:0, divisor de clock de SCLK |

| Bit de `STATUS` | Nome | Acesso | Significado |
| ---: | :--- | :--- | :--- |
| 0 | `BUSY` | R | Uma transação está em andamento ou pedida |
| 1 | `SAMPLE` | W1C | Uma amostra nova foi lida; um evento novo vence a limpeza |
| 2 | `VALID` | R | Já houve uma amostra desde o reset |
| 3 | `CONFIGURED` | R | A configuração terminou |

| Bit de `CONTROL` | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Liga a configuração e a leitura periódica |
| 1 | `IRQ_ENABLE` | Interrupção enquanto `SAMPLE` vale 1 |
| 3:2 | `RANGE` | Faixa, de 0 a 3 para 2, 4, 8 e 16 g |
| 4 | `FULL_RES` | Resolução plena |
| 5 | `USE_INT1` | A leitura espera INT1 em nível alto em vez do tempo |
| 11:8 | `RATE` | Código de taxa escrito em `BW_RATE` (reset 0xA) |

A saída `o_irq` é de nível e vale `SAMPLE` com `IRQ_ENABLE`. Uma escrita em `CONTROL` refaz a configuração, e uma escrita em `PERIOD` ou `DIVIDER` vale a partir da transação seguinte.

## 6. Uso pelo software

O exemplo em C habilita o controlador na faixa de 2 g com resolução plena, espera a primeira amostra e lê os três eixos. A conversão para g usa o fator de 256 LSB por g da faixa de 2 g em 10 bits, que a folha de dados do chip indica mas o manual não confirma; com resolução plena o fator é de cerca de 256 LSB por g em todas as faixas, também sem confirmação.

```c
#include <stdint.h>

/* Base do periférico, definida pela plataforma. */
#define ACC_BASE ((volatile uint32_t *)0x40002000u)

enum { X, Y, Z, STATUS, CONTROL, PERIOD, DEVID, DIVIDER };
enum { SAMPLE = 1u << 1, VALID = 1u << 2, CONFIGURED = 1u << 3 };
enum { ENABLE = 1u << 0, FULL_RES = 1u << 4 };

#define RANGE(n) ((uint32_t)(n) << 2)
#define RATE(n) ((uint32_t)(n) << 8)
#define LSB_PER_G 256

/* Liga o acelerômetro em 100 Hz e na faixa de 2 g com resolução plena. */
void acc_start(void)
{
    ACC_BASE[CONTROL] = ENABLE | FULL_RES | RANGE(0) | RATE(0xA);
    while ((ACC_BASE[STATUS] & VALID) == 0) {
    }
}

/* Lê um eixo em milésimos de g (0 = X, 1 = Y, 2 = Z). */
int32_t acc_milli_g(unsigned axis)
{
    return ((int32_t)ACC_BASE[X + axis] * 1000) / LSB_PER_G;
}

/* Espera uma amostra nova e a marca como lida. */
void acc_wait_sample(void)
{
    ACC_BASE[STATUS] = SAMPLE;
    while ((ACC_BASE[STATUS] & SAMPLE) == 0) {
    }
}
```

## 7. Verificação

O teste de entidade liga o controlador a um modelo do ADXL345 com arquivo de registradores, quadro de comando, rajada e pino INT1, e roda com o fio compartilhado e com os quatro fios. Os casos cobrem os pinos em repouso, a sequência de configuração com a faixa e a taxa pedidas, a leitura periódica com eixos negativos e positivos de 13 bits e 1 g no eixo Z, a leitura disparada por INT1, a interrupção e a reconfiguração por uma escrita em `CONTROL`. O modelo acusa o conflito no fio compartilhado quando o mestre ainda o dirige nos bytes lidos e repete as suposições da seção 4.1, marcadas no código. A prova formal verifica as cinco transações de configuração e a leitura em rajada em ordem, com comandos, dados, número de bytes, driver de MOSI e intervalo de seleção de chip, e mutantes que ela precisa reprovar. A leitura de 1 g no eixo Z com a placa parada depende de um teste de bancada.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

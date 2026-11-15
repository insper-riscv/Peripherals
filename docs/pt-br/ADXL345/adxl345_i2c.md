# Controlador do acelerômetro ADXL345 por I2C (DE0-Nano e DE10-Lite)

🌐 [Português](../../pt-br/ADXL345/adxl345_i2c.md) · [English](../../en/ADXL345/adxl345_i2c.md)

## 1. O que é

Controlador de barramento do acelerômetro de três eixos ADXL345 pelo I2C (`adxl345_i2c`), irmão do controlador SPI descrito em `adxl345.md` e com o mesmo mapa de registradores. Ao ser habilitado, configura o chip (taxa, faixa, resolução e interrupção de dado pronto) e depois lê, em intervalos fixos ou a cada aviso de dado pronto em INT1 ou INT2, os seis bytes dos eixos X, Y e Z. Cada eixo vira um registrador de 32 bits com o valor de 16 bits em complemento de dois estendido em sinal. O chip entra em I2C com a seleção de chip em nível alto, e o controlador a mantém em 1 em `o_adxl_cs_n`.

| Bloco | Função |
| :--- | :--- |
| `i2c_core` | Máquina de linha do mestre I2C, com início, repetição de início, parada e esticamento de clock |
| `adxl345_i2c` | Sequenciador de comandos, registradores dos eixos, temporização e interrupção |
| `adxl345_consts` | Endereços de registrador do chip, valores de configuração e endereços de 7 bits do escravo |

## 2. Pinos e placas

### 2.1. DE0-Nano

O manual (seção 3.7, tabela 3-10) liga o ADXL345 às linhas `I2C_SCLK` e `I2C_SDAT`, que ele compartilha com o EEPROM, a `G_SENSOR_CS_N` e a `G_SENSOR_INT`. A seção 3.4 do manual dá os endereços 0xA0 e 0xA1 do EEPROM, que não colidem com os do acelerômetro.

| Porta | Função | Nome no manual | Pino do FPGA |
| :--- | :--- | :--- | :--- |
| `o_adxl_scl_low` e `i_adxl_scl` | SCL | `I2C_SCLK` | `PIN_F2` |
| `o_adxl_sda_low` e `i_adxl_sda` | SDA | `I2C_SDAT` | `PIN_F1` |
| `o_adxl_cs_n` | Seleção de chip, em 1 para I2C | `G_SENSOR_CS_N` | `PIN_G5` |
| `i_adxl_int1` | Interrupção | `G_SENSOR_INT` | `PIN_M2` |

O manual da DE0-Nano não diz o endereço do chip. Os pinos `o_adxl_sdo` e `i_adxl_int2` ficam sem ligação nessa placa.

### 2.2. DE10-Lite

O manual (seção 3.10, tabela 3-13) diz que, com `GSENSOR_CS_n` em nível alto, o chip fica em I2C, e que o pino `GSENSOR_SDO` em nível alto dá o endereço de 7 bits 0x1D e em nível baixo o 0x53. Nesse modo `GSENSOR_SDI` é o dado serial (SDA) e `GSENSOR_SCLK` o clock (SCL). O SDO é um pino da FPGA, então o controlador o dirige com `o_adxl_sdo`.

| Porta | Função | Nome no manual | Pino do FPGA |
| :--- | :--- | :--- | :--- |
| `o_adxl_scl_low` e `i_adxl_scl` | SCL | `GSENSOR_SCLK` | `PIN_AB15` |
| `o_adxl_sda_low` e `i_adxl_sda` | SDA | `GSENSOR_SDI` | `PIN_V11` |
| `o_adxl_sdo` | Seleção do endereço | `GSENSOR_SDO` | `PIN_V12` |
| `o_adxl_cs_n` | Seleção de chip, em 1 para I2C | `GSENSOR_CS_n` | `PIN_AB16` |
| `i_adxl_int1` | Interrupção 1 | `GSENSOR_INT1` | `PIN_Y14` |
| `i_adxl_int2` | Interrupção 2 | `GSENSOR_INT2` | `PIN_Y13` |

Todos em 3,3 V LVTTL. As linhas SCL e SDA são de dreno aberto: o topo da plataforma liga um tristate a cada uma (valendo 0 quando `o_adxl_*_low` vale 1 e em alta impedância quando vale 0), devolve o nível do pino em `i_adxl_scl` e `i_adxl_sda`, e as linhas precisam de pull-up.

## 3. Parâmetros e portas

| Parâmetro | Padrão | Significado |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Frequência do clock do módulo, em hertz |
| `scl_hz` | 100000 | Frequência de SCL depois do reset, em hertz |
| `sample_hz` | 100 | Amostras por segundo depois do reset, quando o intervalo é por tempo |
| `bus_free_ns` | 1300 | Intervalo mínimo entre uma parada e o início seguinte, em nanossegundos |
| `address_select_high` | falso | Verdadeiro com SDO em nível alto (endereço 0x1D); falso com SDO em nível baixo (0x53) |

O divisor de reset é $\lceil clock\_hz / (5 \cdot scl\_hz) \rceil - 1$, nunca abaixo de 2, e o intervalo de reset entre amostras é $clock\_hz / sample\_hz$ ciclos. As portas do barramento são `i_clk`, `i_rst`, `i_write`, `i_address` (3 bits), `i_data_in`, `o_data_out` e `o_irq`, mais os pinos da seção 2. A janela do bloco ocupa 8 palavras e não há efeito de leitura.

## 4. Sequência

Com `ENABLE` em 1, e depois de qualquer escrita em `CONTROL`, o controlador repete a configuração, e o chip só mede depois do último passo.

| Passo | Transação | Efeito |
| ---: | :--- | :--- |
| 1 | leitura de `DEVID` (0x00), um byte | O byte lido fica no registrador `DEVID` |
| 2 | escrita de `BW_RATE` (0x2C) | Código de taxa de `RATE` |
| 3 | escrita de `DATA_FORMAT` (0x31) | `FULL_RES` e `RANGE` |
| 4 | escrita de `INT_MAP` (0x2F) | Dado pronto em INT1 (`INT_PIN` em 0) ou em INT2 |
| 5 | escrita de `INT_ENABLE` (0x2E) | 0x80, dado pronto |
| 6 | escrita de `POWER_CTL` (0x2D) | 0x08, medição |
| 7 | leitura em rajada a partir de `DATAX0` (0x32), seis bytes | X, Y e Z, byte baixo primeiro |

Uma escrita de registrador é início, endereço do escravo com escrita, endereço do registrador, valor e parada. Uma leitura é início, endereço com escrita, endereço do registrador, repetição de início, endereço com leitura, os bytes lidos com ACK e o último com NACK, e parada. A leitura em rajada repete a cada `PERIOD` ciclos ou, com `USE_INT`, enquanto o pino escolhido por `INT_PIN` estiver em nível alto.

Um NACK do escravo ou uma arbitragem perdida encerra a sequência: o controlador solta as linhas (com uma parada, se o comando que recebeu o NACK não a levava), levanta `NACK` ou `ARB_LOST` em `STATUS` e volta ao repouso até a próxima escrita em `CONTROL`.

### 4.1. Origem de cada parâmetro

A folha de dados do ADXL345 não está no repositório, então só o que os manuais dizem é confirmado.

| Item | Origem |
| :--- | :--- |
| Pinos, I2C de 2 fios, CS alto igual a I2C, endereços 0x1D e 0x53 pelo SDO, INT1 e INT2 | Confirmado pelos manuais (DE0-Nano seção 3.7, DE10-Lite seção 3.10) |
| Endereços 0x00, 0x2C, 0x2D, 0x2E, 0x2F, 0x31 e 0x32 a 0x37 e seus valores, ponteiro de registrador com avanço automático | Não confirmado; da folha de dados, de memória |
| `DEVID` igual a 0xE5 | Não confirmado; o controlador só guarda o byte lido |
| SCL de até 400 kHz e intervalo mínimo entre parada e início | Não confirmado; o controlador usa valores conservadores |

## 5. Registradores

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `X` | R | 0 | Eixo X, 16 bits em complemento de dois estendidos em sinal |
| 1 | `Y` | R | 0 | Eixo Y |
| 2 | `Z` | R | 0 | Eixo Z |
| 3 | `STATUS` | R/W1C | 0 | Estado e marcas (tabela abaixo) |
| 4 | `CONTROL` | R/W | `0xA00` | Habilitação, interrupção, faixa, resolução, disparo, pino e taxa |
| 5 | `PERIOD` | R/W | seção 3 | Bits 23:0, ciclos entre amostras sem `USE_INT` |
| 6 | `DEVID` | R | 0 | Bits 7:0, último `DEVID` lido |
| 7 | `DIVIDER` | R/W | seção 3 | Bits 15:0, divisor de clock de SCL, mínimo 2 |

| Bit de `STATUS` | Nome | Acesso | Significado |
| ---: | :--- | :--- | :--- |
| 0 | `BUSY` | R | Uma transação está em andamento |
| 1 | `SAMPLE` | W1C | Uma amostra nova foi lida; um evento novo vence a limpeza |
| 2 | `VALID` | R | Já houve uma amostra desde o reset |
| 3 | `CONFIGURED` | R | A configuração terminou |
| 4 | `NACK` | W1C | O escravo não respondeu com ACK |
| 5 | `ARB_LOST` | W1C | O controlador perdeu a arbitragem |
| 6 | `INT1` | R | Nível sincronizado do pino INT1 |
| 7 | `INT2` | R | Nível sincronizado do pino INT2 |

| Bit de `CONTROL` | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Liga a configuração e a leitura periódica |
| 1 | `IRQ_ENABLE` | Interrupção enquanto `SAMPLE` vale 1 |
| 3:2 | `RANGE` | Faixa, de 0 a 3 para 2, 4, 8 e 16 g |
| 4 | `FULL_RES` | Resolução plena |
| 5 | `USE_INT` | A leitura espera o pino de interrupção em nível alto em vez do tempo |
| 6 | `INT_PIN` | Pino do dado pronto, 0 para INT1 e 1 para INT2 |
| 11:8 | `RATE` | Código de taxa escrito em `BW_RATE` (reset 0xA) |

A saída `o_irq` é de nível e vale `SAMPLE` com `IRQ_ENABLE`. Uma escrita em `CONTROL` refaz a configuração, e uma escrita em `PERIOD` ou `DIVIDER` vale a partir da transação seguinte.

## 6. Verificação

O teste de entidade liga o controlador a um modelo do ADXL345 no I2C, com ponteiro de registrador, arquivo de registradores e os pinos INT1 e INT2, e roda com SDO em nível baixo e em nível alto. Os casos cobrem os valores de reset e os pinos em repouso, a sequência de configuração com a faixa e a taxa pedidas e as contagens de início e de parada do barramento, a leitura periódica com eixos negativos e positivos de 13 bits e 1 g no eixo Z, a leitura disparada por INT1 e por INT2, a interrupção, a reconfiguração por `CONTROL` e o NACK de um escravo ausente, com as linhas soltas e a recuperação depois da correção. O modelo repete as suposições da seção 4.1, marcadas no código. A leitura de 1 g no eixo Z com a placa parada depende de um teste de bancada.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

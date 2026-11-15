# Ponte do módulo Wi-Fi NINA

🌐 [Português](../../pt-br/WIFI/wifi.md) · [English](../../en/WIFI/wifi.md)

## 1. Referência

A Arduino MKR Vidor 4000 (ABX00022) tem o módulo Wi-Fi e Bluetooth NINA-W102 da u-blox, baseado no ESP32, ligado ao FPGA 10CL016YU256C8G pelos pinos `WM_*`. O número de cada rede `WM_PIO` é o do pino do módulo. Os pinos vêm do catálogo de placas do Insper-RISC-V (`boards/mkr-vidor-4000/pins.yaml`), lido do arquivo de pinos do projeto de referência da Arduino (`vidor_s_pins.qsf`, VidorBitstream) e conferido com o esquemático ABX00022 e com o datasheet da placa.

| Sinal da placa | Pino do FPGA | Padrão elétrico | Função no módulo | Porta da ponte |
| :--- | :--- | :--- | :--- | :--- |
| `oWM_RESET` | R1 | 2,5 V | Reset do módulo (ativo em nível baixo) | `o_wm_reset_n` |
| `bWM_PIO27` | N9 | 3,3 V LVTTL | GPIO0 do ESP32 (seleção de boot) | `o_wm_gpio0`, `o_wm_gpio0_oe` |
| `bWM_PIO7` | P6 | 3,3 V LVTTL | GPIO33 do ESP32 (pronto do SPI, ACK) | `i_wm_ack` |
| `bWM_PIO29` | T10 | 3,3 V LVTTL | Relógio do SPI (GPIO18) | `o_wm_sck` |
| `bWM_PIO36` | N1 | 2,5 V | COPI do SPI (GPIO12) | `o_wm_copi` |
| `bWM_PIO1` | T11 | 3,3 V LVTTL | CIPO do SPI (GPIO23) | `i_wm_cipo` |
| `bWM_PIO28` | N11 | 3,3 V LVTTL | Seleção do SPI (GPIO5) | `o_wm_cs_n` |
| `iWM_TX` | E15 | 3,3 V LVTTL | Saída serial do módulo (GPIO1) | `i_wm_tx` |
| `oWM_RX` | T6 | 3,3 V LVTTL | Entrada serial do módulo (GPIO3) | `o_wm_rx` |
| `bWM_PIO20` | R5 | 3,3 V LVTTL | RTS do módulo | `i_wm_rts` |
| `bWM_PIO21` | R6 | 3,3 V LVTTL | CTS do módulo | `o_wm_cts` |

A associação dos pinos às funções do ESP32 vem do projeto de referência da Arduino, que liga o SPI e a UART do microcontrolador SAMD21 da placa ao módulo por esses mesmos pinos. O firmware de co-processador Wi-Fi do módulo (`nina-fw`, da Arduino) funciona como escravo SPI no modo 0, mantém o pino de pronto em nível alto quando está livre e o leva a nível baixo durante uma troca, e fala a 115200 baud em sua UART de console. O ESP32 entra no modo de gravação do firmware quando GPIO0 está em nível baixo na saída do reset. A polaridade de reset (ativa em nível baixo) e o par RTS e CTS em `WM_PIO20` e `WM_PIO21` (nomes `iWM_RTS` e `iWM_CTS` do arquivo de pinos) são premissas sem confirmação em bancada.

## 2. O que é

A ponte dá ao processador, numa só janela de registradores, tudo o que o FPGA liga ao módulo. O módulo roda um firmware de cada vez, e a ponte oferece os dois caminhos que ele usa, o SPI do firmware de co-processador e a UART do carregador de firmware e dos comandos AT, de modo que o software escolhe um deles.

| Bloco | Instância | Função |
| :--- | :--- | :--- |
| Controle | `wifi_regs` | Reset do módulo, seleção de boot (GPIO0) e entrada ACK com interrupção |
| SPI | `spi` (mestre SPI do repositório) | Mestre SPI de uma linha de seleção, com filas de transmissão e de recepção |
| UART | `uart` (UART do repositório) | UART 8N1 com filas e, opcionalmente, controle de fluxo RTS e CTS |

O topo `wifi` só decodifica o endereço, escolhe o dado de leitura e soma as interrupções. Os registradores do SPI e da UART são os dos documentos [SPI](../SPI/spi.md) e [UART](../UART/serial_uart.md).

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `clock_hz` | 50000000 | Frequência do clock do sistema em Hz; dela saem o pulso de reset e o divisor de reset do SPI |
| `reset_pulse_ms` | 10 | Duração do pulso de reset do módulo em milissegundos |
| `run_at_reset` | `false` | Módulo fora de reset logo depois do reset do sistema |
| `spi_reset_sclk_hz` | 1000000 | Frequência de SCLK do SPI depois do reset, em Hz |
| `spi_rx_fifo_depth`, `spi_tx_fifo_depth` | 16 | Palavras das filas do SPI |
| `uart_baud_freq`, `uart_baud_limit` | `0x240`, `0x3AC9` | Constantes do gerador de baud (115200 baud em 50 MHz) |
| `uart_rx_fifo_depth`, `uart_tx_fifo_depth` | 16 | Bytes das filas da UART |
| `has_flow_control` | `false` | Inclui o controle de fluxo RTS e CTS na UART |

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura do processador |
| `i_address` | entrada | Endereço de palavra de 5 bits |
| `i_data_in`, `o_data_out` | entrada, saída | Dado de escrita e de leitura (`word_t`) |
| `o_irq` | saída | Interrupção em nível, ativa em 1 |
| `o_wm_reset_n` | saída | Reset do módulo, ativo em 0 |
| `o_wm_gpio0`, `o_wm_gpio0_oe` | saída | Valor (sempre 0) e habilitação do driver de GPIO0; a plataforma põe o pino em alta impedância quando a habilitação vale 0 |
| `i_wm_ack` | entrada | ACK do módulo, assíncrono; passa por um sincronizador de dois estágios |
| `o_wm_sck`, `o_wm_copi`, `i_wm_cipo`, `o_wm_cs_n` | saída, saída, entrada, saída | SPI para o módulo; a seleção é ativa em 0 |
| `i_wm_tx`, `o_wm_rx` | entrada, saída | UART para o módulo; `i_wm_tx` é a saída serial do módulo |
| `i_wm_rts`, `o_wm_cts` | entrada, saída | Controle de fluxo, ativo em 0; só valem com `has_flow_control` |

## 4. Mapa de endereços

Os acessos são de 32 bits, e o endereço é de palavra. Um endereço fora do mapa lê zero e ignora a escrita.

| Endereços | Bloco | Registradores |
| :--- | :--- | :--- |
| 0x00 a 0x02 | Controle | `CTRL`, `STATUS`, `RESET_PULSE` |
| 0x08 a 0x0D | SPI | `TX_DATA`, `RX_DATA`, `STATUS`, `CONTROL`, `DIVIDER`, `TX_LISTEN` |
| 0x10 a 0x13 | UART | `TX_DATA`, `RX_DATA`, `STATUS`, `CONTROL` |

## 5. Bloco de controle

### 5.1. `CTRL` (endereço 0x00, leitura e escrita)

| Bit | Nome | Descrição |
| :--- | :--- | :--- |
| 0 | `RUN` | Solta o reset do módulo; em 0, o módulo fica em reset (valor de reset, a menos que `run_at_reset` seja `true`) |
| 1 | `BOOT_LOW` | Puxa GPIO0 do módulo para nível baixo (modo de gravação do firmware); em 0, o pino fica em alta impedância |
| 2 | `RISE_IE` | Interrupção enquanto `RISE` vale 1 |
| 3 | `FALL_IE` | Interrupção enquanto `FALL` vale 1 |

### 5.2. `STATUS` (endereço 0x01)

| Bit | Nome | Descrição |
| :--- | :--- | :--- |
| 0 | `ACK` | Nível sincronizado do pino ACK |
| 1 | `RISE` | Houve borda de subida de ACK; permanece em 1 até escrever 1 no bit |
| 2 | `FALL` | Houve borda de descida de ACK; permanece em 1 até escrever 1 no bit |
| 3 | `PULSE` | Pulso de reset em curso (só leitura) |

### 5.3. `RESET_PULSE` (endereço 0x02)

Escrever 1 no bit 0 segura `o_wm_reset_n` em 0 por $reset\_pulse\_ms$ milissegundos e o devolve ao valor de `RUN`. O bit 0 lê 1 enquanto o pulso corre, e uma escrita de 1 durante o pulso o reinicia. Com `RUN` em 0, o pulso não muda nada no pino, que já está em 0.

$$o\_wm\_reset\_n = RUN \wedge \neg PULSE$$

## 6. Sequências de uso

### 6.1. Boot normal

| Passo | Ação |
| :--- | :--- |
| 1 | Escrever `CTRL` com `RUN` em 1 e `BOOT_LOW` em 0 |
| 2 | Esperar o módulo iniciar o firmware; com o firmware de co-processador, o pino ACK fica em nível alto quando o módulo está livre |

### 6.2. Modo de gravação do firmware

| Passo | Ação |
| :--- | :--- |
| 1 | Escrever `CTRL` com `BOOT_LOW` em 1 e `RUN` em 0 |
| 2 | Escrever `CTRL` com `BOOT_LOW` em 1 e `RUN` em 1, ou escrever 1 em `RESET_PULSE` |
| 3 | Gravar o firmware pela UART com o protocolo do carregador do ESP32 |
| 4 | Escrever `CTRL` com `BOOT_LOW` em 0 e repetir o passo 2 do boot normal |

### 6.3. Troca pelo SPI

O SPI do reset já é de 8 bits no modo 0, que é o do firmware de co-processador. O software escreve `CS_ASSERT` em `CONTROL` do SPI, enfileira os bytes de um comando em `TX_DATA` e lê as respostas em `RX_DATA`. O firmware leva o pino ACK a nível baixo durante uma troca e o devolve a nível alto quando termina, de modo que `RISE` indica módulo pronto, e a interrupção `RISE_IE` avisa o processador sem sondagem.

## 7. Interrupção

$$o\_irq = (RISE\_IE \wedge RISE) \vee (FALL\_IE \wedge FALL) \vee irq_{SPI} \vee irq_{UART}$$

A saída é de nível. As duas primeiras parcelas caem quando o software escreve 1 no bit correspondente de `STATUS`, e as outras duas seguem as máscaras do SPI e da UART.

## 8. Limites

| Item | Situação |
| :--- | :--- |
| Ponte de passagem para o SAMD21 | Não faz parte do periférico; a plataforma a fecha por fora, pelos pinos `bMKR_*`, quando precisa dela |
| Pinos de I2C do módulo (`bWM_PIO35` e `bWM_PIO31`) e demais `bWM_PIO` | Não são usados pela ponte |
| Protocolo do módulo | A ponte move bytes e controla os pinos; o protocolo de comandos do firmware é do software |
| Valores elétricos e de tempo | O pulso de reset de 10 ms, o RTS e o CTS em `WM_PIO20` e `WM_PIO21` e os níveis de 2,5 V de `oWM_RESET` e `bWM_PIO36` seguem o arquivo de pinos e não foram verificados em bancada |

## 9. Exemplo em C

O programa tira o módulo do reset e espera o pino ACK subir. A base da janela vem do cabeçalho gerado a partir do `platform.yaml`.

```c
#include <stdint.h>

enum { WIFI_CTRL = 0, WIFI_STATUS = 1, WIFI_RESET_PULSE = 2 };

enum : uint32_t {
    CTRL_RUN = 1u << 0,
    STAT_ACK = 1u << 0,
};

void wifi_boot(volatile uint32_t *wifi) {
    wifi[WIFI_CTRL] = CTRL_RUN;
    while (!(wifi[WIFI_STATUS] & STAT_ACK)) {
    }
}
```

## 10. Verificação

Os testes de entidade cobrem o bloco de controle (reset, `RUN`, `BOOT_LOW`, pulso de reset com a duração do generic, bordas de ACK, máscaras e limpeza) e o bloco completo (mapa de endereços sem sobreposição e com endereços vazios lendo zero, pulso de reset com o generic de milissegundos, troca SPI de bytes com um escravo simulado no modo 0, quadro UART nos dois sentidos e soma das interrupções). Os testes do SPI e da UART são os dos seus próprios periféricos. Os testes são de simulação, e a ponte não foi exercitada com um módulo real. O sistema de verificação formal do repositório não tem provas para esta ponte.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

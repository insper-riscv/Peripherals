# 2. Console (contrato K9)

## 1. Escopo

O console é o canal de texto entre o programa e o hospedeiro. Este contrato define os dois backends e quando cada um vale. O programa vê sempre uma UART atrás do interconector (contrato K6), e o backend só muda o que está do outro lado.

## 2. Backends

| Backend | Contrato | Quando |
| :--- | :--- | :--- |
| `jtag` (padrão) | Periférico UART com um nó de Virtual JTAG ([jtag_uart](../UART/jtag_uart.md)) | Toda placa com cadeia JTAG alcançável pelo Quartus |
| `pinos` | Periférico UART com `o_tx` e `i_rx` ([serial_uart](../UART/serial_uart.md)) | Placas com UART ou com adaptador em GPIO |

## 3. Escolha

O `jtag` é o padrão porque nem toda placa tem ponte USB-serial ligada ao FPGA, e a JTAG existe em todas. O `pinos` é opcional: pede os pinos de `o_tx` e `i_rx` na placa, e uma placa que não os oferece não o aceita. O nó de Virtual JTAG é uma primitiva de fornecedor e fica no wrapper de fornecedor, nunca no periférico.

## 4. Cadeia JTAG com processador embutido

Quando o FPGA divide a cadeia com um processador (HPS), o nó de Virtual JTAG continua alcançável pela cadeia. A UART USB dessas placas pertence ao processador e não chega ao FPGA, de modo que o console delas é `jtag`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

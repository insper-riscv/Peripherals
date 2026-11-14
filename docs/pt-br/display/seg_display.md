# Display de sete segmentos (`seg_display`)

🌐 [Português](../../pt-br/display/seg_display.md) · [English](../../en/display/seg_display.md)

## 1. O que é

Registrador que guarda 4 bits por dígito e os mostra em hexadecimal nos displays de sete segmentos, pelo conversor `hex_to_seg7`. O valor fica no registrador entre dois programas, e o hospedeiro o lê e o escreve pela cadeia JTAG, ao lado do core.

## 2. Generics

| Generic | Padrão | Efeito |
| :--- | :--- | :--- |
| `digits` | 6 | Número de dígitos, de 0 a 8. O registrador tem `4 * digits` bits e `o_hex` tem `7 * digits` bits. Zero deixa o módulo sem registrador e sem segmento |
| `active_low` | verdadeiro | Segmentos acesos em nível baixo, como nas placas DE. Falso acende em nível alto |

A polaridade fica só na saída `o_hex`. O conversor acende em nível baixo e o generic escolhe o nível do pino, de modo que o resto do módulo não depende da placa.

## 3. Interface

As portas seguem o barramento dos demais periféricos, com `o_rdata` como saída de leitura. A leitura é combinacional no endereço, por isso não há pulso de leitura.

| Interface | Porta | Sentido | Função |
| :--- | :--- | :--- | :--- |
| Controle | `i_clk`, `i_rst` | entrada | Clock do core e reset síncrono, ativo em 1 |
| Barramento | `i_address` | entrada | Deslocamento de palavra de 8 bits dentro da janela |
| Barramento | `i_data_in`, `i_write` | entrada | Dado de escrita de `XLEN` bits (`word_t`) e pulso de escrita |
| Barramento | `o_rdata` | saída | Dado de leitura de `XLEN` bits (`word_t`), combinacional no endereço |
| JTAG | `i_tck`, `i_tdi`, `o_tdo` | entrada, entrada, saída | Clock e dados seriais da cadeia do Virtual JTAG |
| JTAG | `i_ir_in` | entrada | Registrador de instrução de 2 bits |
| JTAG | `i_state_cdr`, `i_state_sdr`, `i_state_udr`, `i_state_uir` | entrada | Estados Capture-DR, Shift-DR, Update-DR e Update-IR |
| Placa | `o_value` | saída | Valor guardado, `4 * digits` bits |
| Placa | `o_fail` | saída | Bandeira de falha gravada pelo hospedeiro |
| Placa | `o_hex` | saída | Segmentos, `7 * digits` bits, com a polaridade de `active_low` |

## 4. Lado do core

Um acesso por pulso de `i_write`. A palavra 0 lê o valor de `4 * digits` bits e a escrita grava os `4 * digits` bits baixos. As outras palavras leem zero e ignoram a escrita.

## 5. Lado do hospedeiro

A instrução 1 do Virtual JTAG seleciona um registrador de `4 * digits + 1` bits. Os bits baixos são o valor novo e o bit mais alto grava o valor quando vale 1. A saída traz o valor do registrador no início da varredura. A instrução 2 seleciona o registrador de 2 bits da bandeira de falha, que só o hospedeiro e a reconfiguração alteram. A gravação do hospedeiro atravessa para o relógio do core por um toggle e dois flip-flops, e vale o core quando os dois gravam no mesmo ciclo.

## 6. Verificação

Os testes de entidade cobrem o padrão de cada dígito, o acesso do core e do hospedeiro, a variante de três dígitos com segmentos ativos em nível alto (registrador de 12 bits e varredura de 13 bits) e o módulo de zero dígito, que não guarda nada e lê zero.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

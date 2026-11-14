# Display de sete segmentos (`seg_display`)

🌐 [Português](../../pt-br/display/seg_display.md) · [English](../../en/display/seg_display.md)

## 1. O que é

Registrador que guarda 4 bits por dígito e os mostra em hexadecimal nos displays de sete segmentos, pelo conversor `hex_to_seg7`. O valor fica no registrador entre dois programas, e o hospedeiro o lê e o escreve pela cadeia JTAG, ao lado do core.

## 2. Generics

| Generic | Padrão | Efeito |
| :--- | :--- | :--- |
| `digits` | 6 | Número de dígitos, de 0 a 8. O registrador tem `4 * digits` bits e `o_hex` tem `7 * digits` bits. Zero deixa o módulo sem registrador e sem segmento |
| `active_low` | verdadeiro | Segmentos acesos em nível baixo, como nas placas DE. Falso acende em nível alto |
| `group_count` | 1 | Número de grupos de dígitos, de 1 a 8 |
| `member_count` | 6 | Total de índices de dígito listados em `group_members`, igual à soma dos tamanhos |
| `group_sizes` | `x"06"` | `std_logic_vector(8 * group_count - 1 downto 0)`; o campo $g$ é o número de dígitos do grupo $g$ |
| `group_members` | dígitos 0 a 5 | `std_logic_vector(8 * member_count - 1 downto 0)`; índices de dígito de todos os grupos em sequência, na ordem escrita |
| `has_dp` | falso | Dígitos de oito segmentos, com o ponto decimal. Verdadeiro leva `o_hex` a `8 * digits` bits e habilita a palavra 1 de cada grupo (seção 6); falso mantém `7 * digits` bits e o comportamento sem ponto |

Os campos das listas têm 8 bits, com o elemento $k$ nos bits $8k+7$ a $8k$, como no generic de partição do GPIO (`docs/pt-br/GPIO/gpio.md`). Um dígito que não está na lista de nenhum grupo fica apagado, com todos os segmentos no nível inativo da placa, e o `o_value` continua com os 4 bits dele para o hospedeiro.
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
| Placa | `o_hex` | saída | Segmentos, `7 * digits` bits (`8 * digits` com `has_dp`), com a polaridade de `active_low` |
| Placa | `o_dp` | saída | Bit guardado do ponto de cada dígito, `digits` bits, 1 = aceso; zero sem `has_dp` |

## 4. Lado do core

Um acesso por pulso de `i_write`. Cada grupo tem 64 bytes de janela, e o grupo $g$ começa na palavra $16g$ do endereço de palavra. A palavra 0 do grupo guarda os dígitos dele, e o dígito $k$ da lista do grupo ocupa os bits $4k+3$ a $4k$. A leitura devolve os dígitos do grupo, e a escrita grava só os dígitos do grupo, sem tocar nos outros. As outras palavras do grupo, e os grupos que não existem, leem zero e ignoram a escrita. O bloco ocupa uma janela de $64 G$ bytes arredondada para a potência de dois seguinte, como o GPIO, e `i_address` tem 8 bits.

## 5. Lado do hospedeiro

A instrução 1 do Virtual JTAG seleciona um registrador de `4 * digits + 1` bits. Os bits baixos são o valor novo e o bit mais alto grava o valor quando vale 1. A saída traz o valor do registrador no início da varredura. A instrução 2 seleciona o registrador de 2 bits da bandeira de falha, que só o hospedeiro e a reconfiguração alteram. A gravação do hospedeiro atravessa para o relógio do core por um toggle e dois flip-flops, e vale o core quando os dois gravam no mesmo ciclo.

## 6. Ponto decimal

Com `has_dp` verdadeiro, cada dígito de `o_hex` tem 8 bits. O dígito $n$ ocupa os bits $8n+7$ a $8n$, com os sete segmentos `gfedcba` nos bits baixos e o ponto no bit 7, como o `HEXn[7]` da DE10-Lite. O bit do ponto de cada dígito do grupo fica na palavra 1 do grupo (palavra $16g+1$), com o dígito $k$ da lista do grupo no bit $k$ e 1 para ponto aceso. A palavra 0 mantém o formato da seção 4, de modo que um programa que só escreve dígitos não muda.

| Palavra do grupo | Com `has_dp` falso | Com `has_dp` verdadeiro |
| :--- | :--- | :--- |
| 0 | Dígitos, nibble $k$ no bit $4k$ | Igual |
| 1 | Lê zero, ignora a escrita | Pontos, bit $k$ = ponto do dígito $k$ do grupo; os bits acima do tamanho do grupo leem zero e ignoram a escrita |
| 2 a 15 | Lê zero, ignora a escrita | Lê zero, ignora a escrita |

O registrador dos pontos é só do core: o hospedeiro pelo JTAG não o lê nem o escreve, e a reconfiguração da FPGA e o reset o zeram. Um dígito fora de todos os grupos não tem bit de ponto e fica totalmente apagado, ponto incluso. A polaridade do ponto é a de `active_low`, igual à dos sete segmentos, e `o_dp` espelha o registrador sem polaridade para a integração.

Das placas dos manuais, só a DE10-Lite tem o oitavo segmento (seção 3.4, tabela 3-6, sinais `HEX07`, `HEX17`, `HEX27`, `HEX37`, `HEX47` e `HEX57`). A DE0-CV (seção 3.3) e a DE2-115 (seção 4.4) listam apenas `HEXn[6:0]`.

### 6.1. Exemplo em C

O exemplo acende o ponto do dígito 2 do grupo 0 e mostra o valor `0x1234` nos quatro primeiros dígitos. `base` é o endereço de byte da janela do `seg_display` no SoC e cada grupo ocupa 64 bytes.

```c
#include <stdint.h>

#define SEG_GROUP_BYTES 64u
#define SEG_WORD_DIGITS 0u
#define SEG_WORD_DOTS   1u

static volatile uint32_t *seg_word(uintptr_t base, unsigned group, unsigned word)
{
    return (volatile uint32_t *)(base + group * SEG_GROUP_BYTES + word * 4u);
}

void seg_show(uintptr_t base)
{
    /* Dígito k do grupo 0 no nibble k: 0x1234 aparece como "1234" da direita para a esquerda. */
    *seg_word(base, 0, SEG_WORD_DIGITS) = 0x1234u;
    /* Bit k = ponto do dígito k do grupo 0; aqui só o dígito 2 fica com o ponto aceso. */
    *seg_word(base, 0, SEG_WORD_DOTS) = 1u << 2;
}

void seg_dot_off(uintptr_t base)
{
    *seg_word(base, 0, SEG_WORD_DOTS) = 0u;
}
```

## 7. Verificação

Os testes de entidade cobrem o padrão de cada dígito, o acesso do core e do hospedeiro, o ponto decimal (oito dígitos em dois grupos com dígitos apagados, três dígitos ativos em nível alto, o ponto aceso e apagado, os dígitos fora de grupo, o reset e o hospedeiro sem efeito sobre o ponto, e o padrão sem `has_dp` com a palavra 1 muda), a variante de três dígitos com segmentos ativos em nível alto (registrador de 12 bits e varredura de 13 bits) e o módulo de zero dígito, que não guarda nada e lê zero, e as partições com um dígito só, explícita (`[[0,1,2,3],[5,6]]` em 8 dígitos) e com a ordem dos dígitos invertida. A prova formal (`seg_display_props.sv`) compara a leitura, o valor guardado, os pontos e os segmentos de todos os dígitos com um modelo ideal, em quatro partições (A e B sem ponto, C e D com `has_dp`), e cinco mutantes do ponto são pegos.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

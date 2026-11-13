# Receptor de infravermelho com decodificador NEC

🌐 [Português](../../pt-br/IR/ir_receiver.md) · [English](../../en/IR/ir_receiver.md)

## 1. Referência

A DE2-115 tem um módulo receptor de infravermelho (IRM-V538N7/TR1) que entrega o sinal já demodulado. O módulo só aceita portadora de 38 kHz, com taxa máxima de cerca de 4 kbit/s, e o controle remoto que acompanha a placa usa o codificador uPD6121G, que gera o protocolo NEC. A saída do módulo chega ao pino `IRDA_RXD` (`PIN_Y15`, 3,3 V).

Este periférico mede cada pulso e cada espaço da linha em ciclos de clock, reconhece quadros NEC (inclusive a repetição e o endereço estendido de 16 bits), guarda os quadros numa FIFO e deixa a última medida bruta à disposição do software, para outros protocolos.

## 2. Parâmetros

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `clk_freq_hz` | 50000000 | Frequência do clock em Hz, abaixo de 238 MHz. Todos os tempos do NEC saem dela |
| `tolerance_percent` | 25 | Tolerância de cada largura em torno do valor nominal, em por cento, de 0 a 30 |
| `glitch_us` | 20 | Tempo mínimo, em microssegundos, que a linha precisa ficar estável para uma mudança valer |
| `timeout_us` | 12000 | Tempo máximo, em microssegundos, de um mesmo nível dentro de um quadro, maior que os 9 ms do pulso inicial |
| `fifo_depth` | 8 | Número de quadros da FIFO, de 1 a 255 |
| `raw_enable` | `true` | Com `false`, as larguras brutas não são guardadas e os dois registradores leem zero |
| `active_low` | `true` | Pulso em nível baixo, como o módulo da placa; com `false` o pulso é o nível alto |

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock e reset síncrono, ativo em 1 |
| `i_data_in`, `i_address` | entrada | Dado de escrita (`word_t`) e endereço de palavra de 3 bits |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço e amostrado antes da borda da leitura |
| `o_irq` | saída | Interrupção de nível, ativa em 1 |
| `i_irda_rxd` | entrada | Pino do receptor, assíncrono; passa por um sincronizador de dois estágios |

## 4. Decodificação NEC

### 4.1. Quadro

A unidade de tempo é $T = 562{,}5\ \mu s$. Um quadro é a sequência de pulsos e espaços da tabela, e o bit menos significativo de cada byte sai primeiro.

| Elemento | Pulso | Espaço |
| :--- | :--- | :--- |
| Início do quadro | $16T$ (9 ms) | $8T$ (4,5 ms) |
| Bit 0 | $T$ | $T$ |
| Bit 1 | $T$ | $3T$ |
| Pulso final | $T$ | |
| Repetição | $16T$, depois $T$ no fim | $4T$ (2,25 ms) |

Os 32 bits do quadro formam quatro bytes: endereço, endereço invertido (ou byte alto do endereço, no NEC estendido), comando e comando invertido.

### 4.2. Tolerância

Cada largura medida $w$ vale para $n$ unidades quando

$$nT_c\left(1 - \frac{p}{100}\right) \le w \le nT_c\left(1 + \frac{p}{100}\right)$$

com $p$ igual a `tolerance_percent` e $T_c = \lfloor f_{clk} / 16000 \rfloor \cdot 9$ ciclos, a unidade $T$ convertida para o clock.

### 4.3. Validação

| Situação | Resultado |
| :--- | :--- |
| Comando e comando invertido são complementares | Quadro aceito; caso contrário, quadro malformado |
| Endereço invertido é o complemento do endereço | Endereço de 8 bits (`extended` em 0, byte alto zero) |
| Endereço invertido não é o complemento, bit `EXT_EN` em 1 | Endereço de 16 bits (`extended` em 1) |
| Endereço invertido não é o complemento, bit `EXT_EN` em 0 | Quadro malformado |
| Repetição depois de um quadro válido | Quadro com a flag de repetição e o endereço e o comando do quadro anterior |
| Repetição sem quadro anterior | Quadro malformado |

Um quadro malformado acende `FRAME_ERR` e é descartado. O erro só existe depois de um pulso inicial válido: pulsos de ruído que não casam com o início do quadro são ignorados sem erro. Depois de um erro o decodificador volta ao repouso, e um pulso que já casa com o início do quadro começa o quadro seguinte. Um nível que dura mais que `timeout_us` dentro de um quadro também é um quadro malformado.

### 4.4. Filtro de ruído

A linha sincronizada só muda de nível depois de ficar `glitch_us` microssegundos estável no novo nível, e a largura de cada nível é contada a partir dessa mudança. Pulsos de ruído mais curtos que o filtro não aparecem nas medidas.

## 5. Mapa de registradores

Os acessos são de 32 bits, e o endereço é de palavra. Um endereço fora do mapa lê zero e ignora a escrita.

| Endereço | Registrador | Acesso | Reset | Descrição |
| :--- | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | L/E | `0x08` | Controle |
| 1 | `STATUS` | L/E (escrever 1 limpa) | 0 | Status |
| 2 | `DATA` | L | 0 | Quadro mais antigo da FIFO; a leitura o remove |
| 3 | `RAW_MARK` | L | 0 | Largura em ciclos do último pulso |
| 4 | `RAW_SPACE` | L | 0 | Largura em ciclos do último espaço |

### 5.1. `CTRL`

| Bit | Nome | Descrição |
| :--- | :--- | :--- |
| 0 | `EN` | Habilita o receptor; em 0, o medidor e o decodificador ficam parados e a FIFO é mantida |
| 1 | `FRAME_IE` | Interrupção enquanto a FIFO não está vazia |
| 2 | `ERR_IE` | Interrupção enquanto `FRAME_ERR` ou `OVERFLOW` valem 1 |
| 3 | `EXT_EN` | Aceita o endereço estendido de 16 bits |
| 4 | `RAW_IE` | Interrupção enquanto `RAW_NEW` vale 1 |
| 5 | `FLUSH` | Escrever 1 esvazia a FIFO; lê sempre 0 |

### 5.2. `STATUS`

| Bit | Nome | Descrição |
| :--- | :--- | :--- |
| 0 | `NOT_EMPTY` | A FIFO tem pelo menos um quadro |
| 1 | `FULL` | A FIFO está cheia |
| 2 | `FRAME_ERR` | Quadro malformado descartado; permanece em 1 até escrever 1 no bit |
| 3 | `OVERFLOW` | Um quadro válido chegou com a FIFO cheia e foi perdido; permanece em 1 até escrever 1 no bit |
| 4 | `LINE` | Nível filtrado da linha, 1 durante um pulso |
| 5 | `RAW_NEW` | Uma medida bruta nova chegou; permanece em 1 até escrever 1 no bit |
| 15:8 | `LEVEL` | Número de quadros na FIFO |

### 5.3. `DATA`

| Bits | Campo | Descrição |
| :--- | :--- | :--- |
| 15:0 | `address` | Endereço; no NEC de 8 bits só os 8 bits baixos valem |
| 23:16 | `command` | Comando |
| 24 | `repeat` | 1 quando o quadro é uma repetição do anterior |
| 25 | `extended` | 1 quando o quadro usou o endereço de 16 bits |

Com a FIFO vazia a leitura devolve zero e não remove nada.

## 6. Medida bruta

A cada pulso e a cada espaço que acaba, o medidor grava a largura em ciclos de clock em `RAW_MARK` ou em `RAW_SPACE` e acende `RAW_NEW`. O software que quer tratar outro protocolo espera `RAW_NEW`, lê os dois registradores, escreve 1 em `RAW_NEW` e converte os ciclos em tempo pela frequência do clock. Os dois registradores mudam a cada medida, então um software que precisa dos dois valores de um mesmo par deve lê-los logo depois de `RAW_NEW` subir, antes da medida seguinte.

## 7. Interrupção

$$o\_irq = (FRAME\_IE \wedge NOT\_EMPTY) \vee (ERR\_IE \wedge (FRAME\_ERR \vee OVERFLOW)) \vee (RAW\_IE \wedge RAW\_NEW)$$

A saída é de nível. A primeira parcela cai quando o software remove o último quadro, e as outras duas caem quando o software escreve 1 no bit correspondente de `STATUS`.

## 8. Exemplo em C

O programa liga o receptor com o endereço estendido e imprime cada quadro recebido. A base da janela vem do cabeçalho gerado a partir do `platform.yaml`.

```c
#include <stdint.h>
#include <stdio.h>

enum { IR_CTRL, IR_STATUS, IR_DATA, IR_RAW_MARK, IR_RAW_SPACE };

enum : uint32_t {
    CTRL_EN = 1u << 0,
    CTRL_EXT_EN = 1u << 3,
    STAT_NOT_EMPTY = 1u << 0,
    STAT_FRAME_ERR = 1u << 2,
    STAT_OVERFLOW = 1u << 3,
    FRAME_REPEAT = 1u << 24,
    FRAME_EXT = 1u << 25,
};

static volatile uint32_t *const ir = (volatile uint32_t *)IR_WINDOW_BASE;

int main(void) {
    ir[IR_CTRL] = CTRL_EN | CTRL_EXT_EN;

    for (;;) {
        uint32_t status = ir[IR_STATUS];

        if (status & (STAT_FRAME_ERR | STAT_OVERFLOW)) {
            ir[IR_STATUS] = status & (STAT_FRAME_ERR | STAT_OVERFLOW);
            puts("quadro perdido ou malformado");
        }

        if (status & STAT_NOT_EMPTY) {
            uint32_t frame = ir[IR_DATA];
            printf("endereco=0x%04x comando=0x%02x%s%s\n",
                   (unsigned)(frame & 0xFFFFu), (unsigned)((frame >> 16) & 0xFFu),
                   (frame & FRAME_EXT) ? " estendido" : "",
                   (frame & FRAME_REPEAT) ? " repeticao" : "");
        }
    }
}
```

## 9. Pino

| Sinal | Pino da DE2-115 | Padrão de E/S | Descrição |
| :--- | :--- | :--- | :--- |
| `IRDA_RXD` | `PIN_Y15` | 3,3 V | Saída demodulada do receptor de infravermelho, ligada a `i_irda_rxd` |

## 10. Verificação

Os testes de entidade cobrem a FIFO, o medidor, o decodificador e os registradores, e o teste do bloco completo usa um gerador de quadros NEC que inclui o quadro padrão e o estendido, repetições, larguras com variação de 12 %, pulsos de ruído dentro e fora do quadro, quadros truncados, complemento errado, FIFO cheia, esvaziamento, máscaras de interrupção e medida bruta. A prova formal cobre a FIFO e os registradores (`ir_fifo_props.sv` e `ir_regs_props.sv`), com mutantes e a verificação de cobertura.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

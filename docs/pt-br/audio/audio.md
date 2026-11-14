# Interface de áudio I2S (`audio`)

## 1. O que é

A interface de áudio liga o barramento do núcleo a um codec de áudio por I2S, como o WM8731 da DE2-115. Ela gera o clock mestre do codec e os clocks de bit e de canal, serializa as amostras de reprodução, desserializa as de gravação, guarda ambas em filas e pode tocar uma onda quadrada de teste sem software. A configuração do codec (volumes, formato, taxa) é feita por I2C, com o periférico `i2c_master`, e não passa por esta interface.

| Item | Valor |
| :--- | :--- |
| Formato | I2S, canal esquerdo com `LRCK` em zero, dado trocando na borda de descida do `BCLK` e bit mais significativo um ciclo de `BCLK` depois da troca do `LRCK` |
| Largura da palavra | 16, 24 ou 32 bits por canal (generic `word_bits` e campo `WORD`) |
| Modo | Mestre ou escravo para `BCLK` e `LRCK` (generic `master`); `AUD_XCK` é sempre gerado |
| Padrão | 12,288 MHz em `AUD_XCK`, 3,072 MHz em `BCLK` e 48 kHz de amostragem, com clock de sistema de 50 MHz |
| Filas | Uma de reprodução e uma de gravação, com profundidade por generic (padrão 32 palavras) |
| Bloco de registradores | 14 palavras, `i_address` de 4 bits |
| Acesso mapeado | 1 ciclo, sem espera do barramento |

## 2. Portas de topo e integração

| Porta | Sentido | Ligação |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono ativo em nível alto |
| `i_data_in`, `i_address` (4 bits), `i_write`, `i_read`, `o_data_out` | barramento | Slot de 16 palavras no interconector |
| `o_irq` | saída | Fonte de interrupção de nível para o PLIC |
| `o_xck` | saída | Pino `AUD_XCK` (E1) |
| `i_bclk`, `o_bclk`, `o_bclk_oe` | entrada, saída e habilitação | Pino `AUD_BCLK` (F2) |
| `i_adclrck`, `o_adclrck`, `o_adclrck_oe` | entrada, saída e habilitação | Pino `AUD_ADCLRCK` (C2) |
| `i_daclrck`, `o_daclrck`, `o_daclrck_oe` | entrada, saída e habilitação | Pino `AUD_DACLRCK` (E3) |
| `i_adcdat` | entrada | Pino `AUD_ADCDAT` (D2) |
| `o_dacdat` | saída | Pino `AUD_DACDAT` (D1) |

Os três pinos bidirecionais seguem o padrão das demais interfaces, em que a camada de tristate do topo da plataforma liga a saída quando a habilitação vale um. No modo mestre as três habilitações valem um e as entradas são ignoradas. No modo escravo valem zero, e `BCLK`, `ADCLRCK` e `DACLRCK` passam por sincronizadores de dois estágios, o que exige clock de sistema com pelo menos quatro vezes a frequência do `BCLK`.

### 2.1. Generics

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `clk_freq` | 50 000 000 | Frequência do clock do sistema em Hz |
| `xck_freq` | 12 288 000 | Frequência de `AUD_XCK` em Hz, no máximo `clk_freq / 2` |
| `sample_rate` | 48 000 | Taxa de amostragem em Hz que fixa o divisor do `BCLK` no reset |
| `slot_bits` | 32 | Ciclos de `BCLK` por canal no reset, no mínimo `word_bits` |
| `word_bits` | 24 | Largura da palavra no reset (16, 24 ou 32) |
| `tx_fifo_depth`, `rx_fifo_depth` | 32 | Profundidade das filas em palavras, de 2 a 65535 |
| `master` | verdadeiro | Modo mestre para `BCLK` e `LRCK` |
| `has_tone` | verdadeiro | Inclui o gerador de tom |
| `tone_freq`, `tone_amp` | 1000 e 8192 | Frequência em Hz e amplitude de 16 bits do tom no reset |
| `autostart` | falso | Reset com clocks, reprodução e tom ligados |

## 3. Clocks

O clock mestre é uma onda quadrada gerada por um acumulador fracionário. A cada ciclo o acumulador soma `XCK_STEP` e, ao alcançar `XCK_MOD`, desconta `XCK_MOD` e inverte `AUD_XCK`. Com $step = 2 \cdot f_{xck}$ e $mod = f_{clk}$ a razão é exata em média, e a saída tem no máximo um período do clock do sistema de jitter.

$$f_{xck} = \frac{XCK\_STEP}{XCK\_MOD} \cdot \frac{f_{clk}}{2}, \qquad f_{bclk} = \frac{f_{xck}}{BCLK\_DIV}, \qquad f_s = \frac{f_{bclk}}{2 \cdot SLOT\_BITS}$$

Os valores do reset dão 12,288 MHz, 3,072 MHz e 48 kHz. As demais taxas da placa se obtêm reprogramando os registradores, e o registrador 8 do codec deve escolher a mesma razão entre `AUD_XCK` e a amostragem.

| Taxa de amostragem | `XCK_STEP` (clock de 50 MHz) | `BCLK_DIV` | `SLOT_BITS` |
| ---: | ---: | ---: | ---: |
| 48 kHz | 24 576 000 | 4 | 32 |
| 96 kHz | 24 576 000 | 2 | 32 |
| 32 kHz | 24 576 000 | 6 | 32 |
| 8 kHz | 24 576 000 | 24 | 32 |
| 44,1 kHz | 22 579 200 | 4 | 32 |

Vale $XCK\_STEP \le XCK\_MOD$ e `XCK_STEP` zero mantém o pino em zero. No modo mestre o `LRCK` inverte na borda de descida do `BCLK`, junto com a troca do dado, a cada `SLOT_BITS` ciclos de `BCLK`. A geração só corre com `CLK_EN` em um.

## 4. Registradores

Os endereços são de palavra. Todos os campos não listados leem zero.

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CONTROL` | L/E | 0 (ver abaixo) | Habilitações, descritas na tabela seguinte |
| 1 | `STATUS` | L/E1C | `TX_NOT_FULL` e `TX_EMPTY` | Estado das filas e flags de erro |
| 2 | `LEVELS` | L | 0 | Bits 15:0 nível da fila de reprodução, bits 31:16 da de gravação |
| 3 | `TX_DATA` | E | n/a | Empilha uma amostra na fila de reprodução; a leitura devolve zero |
| 4 | `RX_DATA` | L | n/a | Amostra mais antiga da fila de gravação, removida ao final da leitura |
| 5 | `IRQ_LEVEL` | L/E | `0x0001_0000` | Bits 15:0 limiar da reprodução, bits 31:16 limiar da gravação |
| 6 | `XCK_STEP` | L/E | $2 \cdot$ `xck_freq` | Passo do acumulador do clock mestre |
| 7 | `XCK_MOD` | L/E | `clk_freq` | Módulo do acumulador do clock mestre |
| 8 | `BCLK_DIV` | L/E | $f_{xck} / f_{bclk}$ | Bits 15:0, inversões do clock mestre entre inversões do `BCLK` |
| 9 | `SLOT_BITS` | L/E | `slot_bits` | Bits 15:0, ciclos de `BCLK` por canal |
| 10 | `TONE_HALF` | L/E | $f_s / (2 \cdot$ `tone_freq`$)$ | Bits 15:0, quadros por semiciclo do tom |
| 11 | `TONE_AMP` | L/E | `tone_amp` | Bits 15:0, amplitude do tom em escala de 16 bits |
| 12 | `CONFIG` | L | n/a | Bits 15:0 profundidade da reprodução, bits 31:16 da gravação |
| 13 | `CAPS` | L | n/a | Bit 0 `MASTER`, bit 1 `HAS_TONE` |

Com `autostart` falso, `CONTROL` zera todas as habilitações e o campo `WORD` vale o código de `word_bits`. Com `autostart` verdadeiro, `TX_EN`, `CLK_EN` e `TONE_EN` valem um.

| Bits de `CONTROL` | Nome | Significado |
| :--- | :--- | :--- |
| 0 | `TX_EN` | O serializador consome quadros da fila (ou do tom) |
| 1 | `RX_EN` | O desserializador grava quadros na fila de gravação |
| 2 | `TX_IRQ_EN` | Habilita a interrupção da fila de reprodução |
| 3 | `RX_IRQ_EN` | Habilita a interrupção da fila de gravação |
| 4 | `ERR_IRQ_EN` | Habilita a interrupção por erro |
| 5 | `CLK_EN` | Gera `AUD_XCK` e, no modo mestre, `BCLK` e `LRCK` |
| 6 | `TONE_EN` | Troca a fila de reprodução pelo tom de teste (só com `has_tone`) |
| 9:8 | `WORD` | Largura da palavra, 0 para 16, 1 para 24, 2 ou 3 para 32 bits |

| Bits de `STATUS` | Nome | Significado |
| :--- | :--- | :--- |
| 0 | `TX_NOT_FULL` | A fila de reprodução aceita uma palavra |
| 1 | `RX_NOT_EMPTY` | A fila de gravação tem uma palavra |
| 2 | `TX_EMPTY` | A fila de reprodução está vazia |
| 3 | `RX_FULL` | A fila de gravação está cheia |
| 4 | `TX_UNDERFLOW` | Um quadro começou sem duas palavras na fila de reprodução |
| 5 | `RX_OVERFLOW` | Um quadro recebido foi descartado com a fila de gravação sem espaço para dois |
| 6 | `TX_DROPPED` | Uma escrita em `TX_DATA` foi descartada com a fila cheia |

Os bits 4 a 6 são persistentes. Uma escrita de um no próprio bit o limpa, e uma escrita de zero o preserva. Um evento novo no mesmo ciclo de uma limpeza tem prioridade.

## 5. Formato das amostras

A fila de reprodução e a de gravação guardam as amostras intercaladas, esquerda e direita, uma por palavra de 32 bits.

| Sentido | Formato da palavra de 32 bits |
| :--- | :--- |
| Reprodução | As `WORD` bits menos significativos formam a amostra em complemento de dois; os bits acima são ignorados |
| Gravação | A amostra de `WORD` bits chega com extensão de sinal para 32 bits |

Um quadro de reprodução só é consumido quando a fila tem pelo menos duas palavras no começo do canal esquerdo. Com menos, os dois canais saem em zero, `TX_UNDERFLOW` sobe e as palavras da fila ficam, o que mantém a ordem esquerda e direita. Na gravação, um quadro só é aceito se a fila tem espaço para as duas palavras; senão o quadro inteiro é descartado e `RX_OVERFLOW` sobe. Em ambos os sentidos as palavras mais antigas são preservadas.

Quando `SLOT_BITS` é maior que a largura da palavra, os bits restantes do canal saem em zero e são ignorados na entrada. Quando é igual, o último bit da amostra sai junto com a troca do `LRCK`, como pede o formato I2S.

## 6. Tom de teste

Com `TONE_EN` em um, o serializador deixa de ler a fila de reprodução e envia nos dois canais uma onda quadrada que vale $+TONE\_AMP$ e $-TONE\_AMP$, trocando a cada `TONE_HALF` quadros. A amplitude está em escala de 16 bits e ocupa os bits mais altos da palavra, de modo que o mesmo valor produz o mesmo volume em 16, 24 ou 32 bits.

$$f_{tom} = \frac{f_s}{2 \cdot TONE\_HALF}$$

Com 48 kHz e `TONE_HALF` igual a 24 o tom é de 1 kHz. Com o generic `autostart`, o tom sai do reset sem nenhuma escrita, o que prova o caminho do clock, do serializador e dos pinos sem software.

## 7. Interrupção

A saída `o_irq` é de nível e vale o OU de três causas, cada uma com a sua habilitação, zeradas no reset.

| Causa | Condição | Deixa de valer quando |
| :--- | :--- | :--- |
| Reprodução (`TX_IRQ_EN`) | Nível da fila de reprodução menor ou igual ao limiar `TX` de `IRQ_LEVEL` | O software empilha amostras acima do limiar |
| Gravação (`RX_IRQ_EN`) | Nível da fila de gravação maior ou igual ao limiar `RX` de `IRQ_LEVEL` | O software retira amostras abaixo do limiar |
| Erro (`ERR_IRQ_EN`) | `TX_UNDERFLOW`, `RX_OVERFLOW` ou `TX_DROPPED` ativo | O software limpa os bits em `STATUS` |

## 8. Sequência de uso

1. Configurar o codec por I2C (seção 9).
2. Escrever `CONTROL` com a largura da palavra desejada em `WORD`, sem habilitações.
3. Reprogramar `XCK_STEP`, `XCK_MOD`, `BCLK_DIV` e `SLOT_BITS` se a taxa não for a do reset.
4. Pré-carregar a fila de reprodução com `TX_DATA` até `TX_NOT_FULL` cair.
5. Escrever `CONTROL` com `CLK_EN`, `TX_EN` (e `RX_EN` para gravar).
6. Reabastecer a fila por polling em `STATUS` ou por interrupção de nível, e ler `RX_DATA` enquanto `RX_NOT_EMPTY` valer.

## 9. Exemplo em C

O exemplo toca um tom de 1 kHz de duas formas: por hardware, com o gerador de tom, e por software, empilhando a onda na fila. A função `i2c_write` pertence ao driver do `i2c_master`, e `AUDIO_BASE` é a base do periférico na plataforma. O WM8731 é escravo do I2S: o formato, a largura e a taxa são escolhidos pelos registradores 7 e 8 do codec, de endereço de 7 bits e dado de 9 bits.

```c
#include <stdbool.h>
#include <stdint.h>

#define AUDIO_REG(n) (*(volatile uint32_t *)(AUDIO_BASE + 4u * (n)))

enum {
    AUDIO_CONTROL, AUDIO_STATUS, AUDIO_LEVELS, AUDIO_TX_DATA, AUDIO_RX_DATA, AUDIO_IRQ_LEVEL,
    AUDIO_XCK_STEP, AUDIO_XCK_MOD, AUDIO_BCLK_DIV, AUDIO_SLOT_BITS, AUDIO_TONE_HALF, AUDIO_TONE_AMP
};

#define TX_EN      (1u << 0)
#define CLK_EN     (1u << 5)
#define TONE_EN    (1u << 6)
#define WORD_16    (0u << 8)
#define TX_NOT_FULL (1u << 0)

extern void i2c_write(uint8_t device, uint8_t reg, uint16_t value);

#define WM8731 0x1Au

static void codec_setup(void)
{
    i2c_write(WM8731, 15, 0x000);  /* reinicia o codec */
    i2c_write(WM8731, 6, 0x000);   /* liga todos os blocos */
    i2c_write(WM8731, 2, 0x079);   /* volume do fone de ouvido */
    i2c_write(WM8731, 4, 0x010);   /* seleciona o DAC */
    i2c_write(WM8731, 5, 0x000);   /* sem mudo digital */
    i2c_write(WM8731, 7, 0x002);   /* escravo, I2S, 16 bits */
    i2c_write(WM8731, 8, 0x000);   /* 48 kHz com mestre de 12,288 MHz */
    i2c_write(WM8731, 9, 0x001);   /* ativa a interface digital */
}

static void tone_in_hardware(void)
{
    AUDIO_REG(AUDIO_TONE_HALF) = 24;      /* 48 kHz / (2 * 24) = 1 kHz */
    AUDIO_REG(AUDIO_TONE_AMP) = 0x2000;
    AUDIO_REG(AUDIO_CONTROL) = WORD_16 | CLK_EN | TX_EN | TONE_EN;
}

static void tone_in_software(void)
{
    AUDIO_REG(AUDIO_CONTROL) = WORD_16 | CLK_EN | TX_EN;

    for (uint32_t frame = 0;; ++frame) {
        const int16_t sample = ((frame / 24u) & 1u) ? -0x2000 : 0x2000;

        while (!(AUDIO_REG(AUDIO_STATUS) & TX_NOT_FULL)) {
        }
        AUDIO_REG(AUDIO_TX_DATA) = (uint16_t)sample;  /* esquerdo */
        while (!(AUDIO_REG(AUDIO_STATUS) & TX_NOT_FULL)) {
        }
        AUDIO_REG(AUDIO_TX_DATA) = (uint16_t)sample;  /* direito */
    }
}

int main(void)
{
    codec_setup();
    tone_in_hardware();
    /* tone_in_software() toca o mesmo tom pela fila. */
    for (;;) {
    }
}
```

## 10. Verificação

Os testes de entidade usam um modelo do codec que reconstrói as amostras recebidas pelo DAC e alimenta o ADC, nos modos mestre e escravo e com canal justo e com preenchimento. Eles cobrem o estado de reset, a ordem e a largura de 16, 24 e 32 bits na reprodução e na gravação com extensão de sinal, o alinhamento dos canais depois de um subfluxo, o descarte com a fila cheia, as interrupções por limiar e por erro, as taxas de 48 kHz e 44,1 kHz dos clocks e o tom, inclusive com `autostart`. As provas formais cobrem o gerador do clock mestre, os divisores de bit e de canal e o contrato dos registradores, das filas e da interrupção, com mutantes.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

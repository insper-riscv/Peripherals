# Saída de áudio HDMI

🌐 [Português](../../pt-br/HDMI/hdmi_audio.md) · [English](../../en/HDMI/hdmi_audio.md)

## 1. Referência

O periférico entrega áudio digital estéreo ao transmissor HDMI de uma placa pelo barramento I2S. O transmissor é o ADV7513 da Analog Devices, o mesmo do vídeo HDMI (`docs/pt-br/HDMI/hdmi_tx.md`). O manual da DE10-Nano (seção 3.6.5 e seção 5.3) confirma o que este periférico usa do chip e o que ele deixa para o software.

| Fato | Fonte |
| :--- | :--- |
| Os quatro sinais de áudio chegam ao FPGA pelos pinos da tabela 1.1, todos em 3,3 V | Manual da DE10-Nano, Tabela 3-13 |
| O chip aceita de 2 a 8 canais de áudio I2S, com taxa de amostragem de até 192 kHz | Manual da DE10-Nano, seção 5.3 |
| O chip aceita I2S padrão, justificado à esquerda e justificado à direita | Manual da DE10-Nano, seção 5.3 |
| A frequência de áudio fica no registrador `0x15` do chip e o formato no registrador `0xAF`, ambos escritos pelo I2C | Manual da DE10-Nano, seção 5.3 |
| O exemplo da Terasic toca um sinal senoidal a 48 kHz, com 16 bits por canal, pelo I2S padrão | Manual da DE10-Nano, seção 5.3, Figura 5-6 |

O manual não traz os valores dos registradores de áudio, a razão entre o clock mestre e o clock de canal que o chip espera, nem os parâmetros de regeneração do clock de áudio (`N` e `CTS`). Eles estão no guia de programação do fabricante, que não faz parte dos manuais das placas. Por isso o periférico não traz nenhum valor de registrador do ADV7513, e a razão MCLK/LRCLK é um generic que a plataforma escolhe.

Não confirmado: a razão MCLK/LRCLK que o ADV7513 exige, os valores dos registradores de áudio (taxa, formato, `N`, `CTS`, seleção de canais), e se o chip tolera o jitter de um ciclo do clock do sistema no MCLK da seção 4.2. As razões 128 e 256 vezes a taxa de amostragem são as que o periférico oferece.

### 1.1. Pinos do manual da DE10-Nano

| Sinal da placa | Pino do FPGA | Função no chip | Porta do periférico |
| :--- | :--- | :--- | :--- |
| `HDMI_MCLK` | PIN_U11 | Clock de referência do áudio | `o_mclk` |
| `HDMI_SCLK` | PIN_T12 | Clock do I2S (clock de bit) | `o_sclk` |
| `HDMI_LRCLK` | PIN_T11 | Seleção do canal esquerdo e direito | `o_lrclk` |
| `HDMI_I2S0` | PIN_T13 | Dado do canal I2S 0 | `o_i2s0` |

## 2. O que é

O periférico é um invólucro fino sobre o periférico de áudio I2S (`docs/pt-br/audio/audio.md`), usado no modo mestre e só para reprodução. O invólucro calcula os generics do periférico de áudio a partir da taxa de amostragem e da razão MCLK/LRCLK, liga as quatro saídas aos sinais do transmissor e fixa o que não existe nesta direção, que é a entrada de áudio e os pinos de entrada dos clocks. Nenhuma lógica é copiada.

| Bloco | Função |
| :--- | :--- |
| `audio_xck_gen` | Gera o MCLK por acumulador de fase fracionário a partir do clock do sistema |
| `audio_frame_clocks` | Deriva o SCLK e o LRCLK das inversões do MCLK |
| `audio_i2s_tx` | Serializa uma palavra por canal no formato I2S |
| `audio_tone` | Gera a onda quadrada de teste em hardware |
| `uart_fifo` | Fila de amostras de reprodução, esquerda e direita intercaladas |
| `audio` | Registradores, filas e interrupção do periférico de áudio |
| `hdmi_audio` | Invólucro que escolhe os generics e entrega os quatro pinos do transmissor |

A fila e o desserializador de gravação do periférico de áudio ficam sem uso, com a profundidade mínima e a entrada fixa em zero. Escrever o bit `RX_EN` não tem efeito útil.

### 2.1. Generics

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `clk_freq` | 100000000 | Frequência do clock do sistema em Hz, no mínimo o dobro da frequência do MCLK |
| `sample_rate` | 48000 | Taxa de amostragem do reset em Hz: 32000, 44100 ou 48000 |
| `mclk_ratio` | 256 | Razão MCLK/LRCLK do reset: 128 ou 256 |
| `word_bits` | 24 | Largura da palavra do reset: 16 ou 24 bits |
| `tx_fifo_depth` | 32 | Profundidade da fila de reprodução em palavras, no mínimo 2 |
| `has_tone` | verdadeiro | Inclui o gerador de tom de teste |
| `tone_freq` | 1000 | Frequência do tom do reset em Hz |
| `tone_amp` | 8192 | Amplitude do tom do reset em escala de 16 bits |
| `autostart` | falso | O reset já liga os clocks, a reprodução e o tom, para tocar sem software |

Um valor fora das listas acima derruba a elaboração com uma mensagem de erro.

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura do processador |
| `i_address` | entrada | Endereço de palavra do registrador, 4 bits |
| `i_data_in` | entrada | Dado de escrita de 32 bits |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço |
| `o_irq` | saída | Interrupção em nível (limiares das filas e erros) |
| `o_mclk` | saída | Clock mestre, para o pino `HDMI_MCLK` |
| `o_sclk` | saída | Clock de bit, para o pino `HDMI_SCLK` |
| `o_lrclk` | saída | Clock de canal, em 0 no canal esquerdo, para o pino `HDMI_LRCLK` |
| `o_i2s0` | saída | Dado serial, para o pino `HDMI_I2S0` |

Os quatro pinos são saídas simples de 3,3 V, sem habilitação de saída nem buffer de fabricante.

## 4. Temporização

### 4.1. Relações entre os clocks

O slot de cada canal tem 32 ciclos de SCLK, e a palavra de 16 ou 24 bits sai alinhada à esquerda, com zeros no resto do slot. Com $f_s$ a taxa de amostragem e $R$ a razão MCLK/LRCLK,

$$f_{LRCLK} = f_s \qquad f_{SCLK} = 64 \, f_s \qquad f_{MCLK} = R \, f_s \qquad \frac{f_{MCLK}}{f_{SCLK}} = \frac{R}{64}$$

O SCLK inverte a cada $R/64$ períodos de MCLK, o que dá o divisor 2 para $R = 128$ e 4 para $R = 256$. O LRCLK inverte a cada $R/2$ períodos de MCLK, e cada semiciclo é um canal.

| Taxa $f_s$ | MCLK com $R = 128$ | MCLK com $R = 256$ | SCLK |
| :--- | :--- | :--- | :--- |
| 32 kHz | 4,096 MHz | 8,192 MHz | 2,048 MHz |
| 44,1 kHz | 5,6448 MHz | 11,2896 MHz | 2,8224 MHz |
| 48 kHz | 6,144 MHz | 12,288 MHz | 3,072 MHz |

O formato é o I2S padrão: o LRCLK vale 0 no canal esquerdo, o bit mais significativo sai um ciclo de SCLK depois da troca do LRCLK e o dado muda na descida do SCLK, de modo que o receptor o amostra estável na subida.

### 4.2. Geração do MCLK

O MCLK vem do clock do sistema por um acumulador de fase com passo $2 f_{MCLK}$ e módulo $f_{clk}$. A frequência média é exata, e cada borda do MCLK se desloca no máximo um período do clock do sistema em relação ao instante ideal. Quando o clock do sistema é múltiplo par do MCLK, não há jitter. Vale a condição

$$f_{clk} \ge 2 \, f_{MCLK}$$

Com o clock do sistema de 100 MHz e $R = 256$, o jitter do MCLK é de até 10 ns. O SCLK e o LRCLK são contados nas inversões do MCLK e herdam o mesmo jitter, sem erro acumulado. O LRCLK medido em muitos quadros tem exatamente a taxa $f_s$, e um semiciclo isolado dura um ciclo a mais ou a menos que a média.

## 5. Registradores

O mapa é o do periférico de áudio, em endereços de palavra de 4 bits (`docs/pt-br/audio/audio.md`, seção 4). Os registradores usados na reprodução, com os valores de reset que o invólucro calcula, são:

| Palavra | Nome | Valor de reset | Uso |
| :--- | :--- | :--- | :--- |
| 0 | `CONTROL` | 0, ou ligado com `autostart` | `TX_EN` (bit 0), `CLK_EN` (bit 5), `TONE_EN` (bit 6), `WORD` (bits 9:8, 0 = 16 e 1 = 24 bits) |
| 1 | `STATUS` | `TX_NOT_FULL` e `TX_EMPTY` | Fila de reprodução, subfluxo e escrita descartada |
| 2 | `LEVELS` | 0 | Nível da fila de reprodução nos bits 15:0 |
| 3 | `TX_DATA` | | Empilha uma amostra, esquerda e direita alternadas, nos `word_bits` bits baixos |
| 5 | `IRQ_LEVEL` | 0 | Limiar da interrupção da fila de reprodução, nos bits 15:0 |
| 6 | `XCK_STEP` | $2 \cdot R \cdot f_s$ | Passo do acumulador do MCLK |
| 7 | `XCK_MOD` | `clk_freq` | Módulo do acumulador do MCLK |
| 8 | `BCLK_DIV` | $R / 64$ | Inversões do MCLK por inversão do SCLK |
| 9 | `SLOT_BITS` | 32 | Ciclos de SCLK por canal |
| 10 | `TONE_HALF` | $f_s / (2 \cdot tone\_freq)$ | Quadros por semiciclo do tom |
| 11 | `TONE_AMP` | `tone_amp` | Amplitude do tom |
| 12 | `CONFIG` | | Profundidade da fila de reprodução nos bits 15:0 |
| 13 | `CAPS` | | Bit 0 em 1 (modo mestre) e bit 1 com o tom presente |

### 5.1. Troca de taxa em tempo de execução

A taxa e a razão MCLK/LRCLK podem mudar por software, com `CLK_EN` em 0, escrevendo `XCK_STEP` com $2 \cdot R \cdot f_s$ e `BCLK_DIV` com $R / 64$, e religando `CLK_EN`. A condição $f_{clk} \ge 2 f_{MCLK}$ vale para qualquer escolha, e `SLOT_BITS` deve continuar em 32.

## 6. Configuração do transmissor

O periférico não escreve no ADV7513. O software, com o `i2c_master`, ou o sequenciador de inicialização do `hdmi_tx`, com a tabela de áudio, escreve nos registradores do chip a taxa, o formato do I2S e a seleção de áudio.

| Item | Situação |
| :--- | :--- |
| Registradores `0x15` (frequência de áudio) e `0xAF` (formato) | Existem, pelo manual da placa; os valores não são confirmados |
| Demais registradores de áudio, `N` e `CTS` | Não confirmados; estão no guia de programação do fabricante |
| Tabela de áudio do sequenciador (`audio_init_table` do `hdmi_tx`) | Vazia por padrão, sem nenhum valor de registrador |

O generic `audio_init_table` do `hdmi_tx` recebe a tabela de áudio no mesmo formato da `init_table`, quatro dígitos hexadecimais por entrada, registrador e depois valor. O sequenciador escreve as entradas da `init_table` e em seguida as da `audio_init_table`, e as duas juntas somam no máximo 255 entradas. Com a tabela vazia, nada é escrito para o áudio. A plataforma que tiver os valores do guia do fabricante os coloca nesse generic, e os registradores de contagem do sequenciador (`docs/pt-br/HDMI/hdmi_tx.md`, seção 7.3) passam a contar as entradas dos dois.

## 7. Limites

| Limite | Detalhe |
| :--- | :--- |
| Dois canais | O ADV7513 aceita de 2 a 8 canais, mas o periférico gera só o canal I2S 0, estéreo; a Tabela 3-13 do manual lista só `HDMI_I2S0` |
| Taxas | 32, 44,1 e 48 kHz no reset; outras taxas exigem o ajuste dos registradores da seção 5.1 |
| Palavra | 16 e 24 bits; a palavra de 32 bits do periférico de áudio não é aceita no reset |
| Formato | I2S padrão; os formatos justificados à esquerda e à direita não são gerados |
| Gravação | Não existe; o transmissor é só de recepção de áudio |

## 8. Ligação no topo da placa

1. `o_mclk`, `o_sclk`, `o_lrclk` e `o_i2s0` vão aos pinos `HDMI_MCLK`, `HDMI_SCLK`, `HDMI_LRCLK` e `HDMI_I2S0`, todos em 3,3 V.
2. Nenhuma PLL é necessária: o clock do sistema deve ter no mínimo o dobro da frequência do MCLK.
3. O .sdc declara as quatro saídas como saídas do clock do sistema, sem relação de fase com o clock de pixel.
4. O transmissor é configurado pelo I2C do `hdmi_tx`, ou pelo `i2c_master` quando o `hdmi_tx` não tem o sequenciador.

## 9. Exemplo em C

O programa espera o sequenciador do `hdmi_tx` terminar a inicialização do chip, liga o clock mestre e a reprodução e toca uma onda quadrada de 1 kHz a 48 kHz, com palavra de 24 bits e a mesma amostra nos dois canais. As bases são definidas pela plataforma, e os valores dos registradores de áudio do chip estão na tabela de áudio da plataforma.

```c
#include <stdint.h>

/* Bases dos periféricos, definidas pela plataforma. */
#define HDMI_BASE        0x40000000u
#define HDMI_AUDIO_BASE  0x40010000u
#define HDMI_REG(word)   (*(volatile uint32_t *)(HDMI_BASE + 4u * (word)))
#define AUDIO_REG(word)  (*(volatile uint32_t *)(HDMI_AUDIO_BASE + 4u * (word)))

enum { HDMI_STATUS = 9u };
enum { STATUS_DONE = 1u << 2, STATUS_INIT = 1u << 4 };

enum { REG_CONTROL = 0u, REG_STATUS = 1u, REG_TX_DATA = 3u };
enum { CTRL_TX_EN = 1u << 0, CTRL_CLK_EN = 1u << 5, CTRL_WORD_24 = 1u << 8 };
enum { AUDIO_TX_NOT_FULL = 1u << 0 };

enum {
    SAMPLE_RATE = 48000,
    TONE_HZ = 1000,
    HALF_PERIOD = SAMPLE_RATE / (2 * TONE_HZ),
    AMPLITUDE = 0x2000,
};

static void push_sample(int32_t sample)
{
    while (!(AUDIO_REG(REG_STATUS) & AUDIO_TX_NOT_FULL)) {
    }
    AUDIO_REG(REG_TX_DATA) = (uint32_t)sample & 0xFFFFFFu;
}

int main(void)
{
    /* Com o sequenciador, espera a tabela chegar ao transmissor. */
    if (HDMI_REG(HDMI_STATUS) & STATUS_INIT) {
        while (!(HDMI_REG(HDMI_STATUS) & STATUS_DONE)) {
        }
    }

    /* Encha a fila antes de ligar a reprodução, para não haver subfluxo. */
    int32_t level = AMPLITUDE << 8;
    uint32_t frames = 0;
    for (uint32_t i = 0; i < 8; i++) {
        push_sample(level);
        push_sample(level);
    }
    AUDIO_REG(REG_CONTROL) = CTRL_CLK_EN | CTRL_TX_EN | CTRL_WORD_24;

    for (;;) {
        if (++frames == HALF_PERIOD) {
            frames = 0;
            level = -level;
        }
        push_sample(level);
        push_sample(level);
    }
}
```

O bit `TONE_EN` do registrador de controle (bit 6) troca a fila pelo tom de hardware e dispensa o laço de amostras, com `TONE_HALF` e `TONE_AMP` escolhendo a frequência e a amplitude.

## 10. Verificação

| Verificação | Cobertura |
| :--- | :--- |
| Testes de entidade `HdmiAudio48k`, `HdmiAudio44k1` e `HdmiAudio32k` | Registradores de reset de cada taxa; contagem exata de subidas de MCLK e de SCLK por canal e duração média do canal contra a taxa, medidas só nas saídas; reconstrução, por um modelo de receptor I2S, das amostras estéreo escritas na fila, com 16 e 24 bits e preenchimento zerado; troca de taxa por registradores |
| Teste de entidade `HdmiAudioTone` | Tom de 1 kHz, a 44,1 kHz com 24 bits, sem nenhuma escrita no barramento |
| Testes de entidade `HdmiInitSeqAudio`, `HdmiInitSeqAudioOnly` e `HdmiTxInitAudio` | A tabela de áudio sai depois da tabela geral, ou sozinha, com o modelo de escravo I2C do ADV7513, e os contadores somam as duas |
| Provas formais `hdmiaud128_*`, `hdmiaud256_*` e `hdmiseq_audio_*` | Contagem exata, em ciclos, de MCLK, SCLK e LRCLK nas razões 128 e 256, o dado só mudando depois da descida do SCLK, e a ordem das duas tabelas do sequenciador, com mutantes |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

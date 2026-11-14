# Captura de vídeo do decodificador de TV

🌐 [Português](../../pt-br/TV/tv.md) · [English](../../en/TV/tv.md)

## 1. Referência

A placa DE2-115 tem o decodificador de TV ADV7180, que converte vídeo analógico de banda base (NTSC, PAL ou SECAM) em vídeo 4:2:2 no padrão ITU-R BT.656 de 8 bits. O chip é configurado por I2C (endereço de escrita 0x40 e de leitura 0x41, seção 4.15 do manual da placa) e entrega o vídeo ao FPGA pelos pinos abaixo.

| Sinal | Pino | Sentido, visto do FPGA | Função |
| :--- | :--- | :--- | :--- |
| `TD_DATA[0]` a `TD_DATA[7]` | E8, A7, D8, C7, D7, D6, E7, F7 | entrada | Byte do fluxo BT.656 |
| `TD_CLK27` | B14 | entrada | Clock de 27 MHz do fluxo |
| `TD_HS`, `TD_VS` | E5, E4 | entrada | Sincronismos do decodificador, não usados: o periférico lê o sincronismo dos códigos embutidos no fluxo |
| `TD_RESET_N` | G7 | saída | Reset do decodificador, ativo em nível baixo |

## 2. O que é

O periférico recebe o fluxo BT.656, reconhece o início e o fim do vídeo ativo de cada linha, extrai a luminância Y e as crominâncias Cb e Cr, converte cada pixel para RGB de 16 bits (RGB565) ou para luminância de 8 bits, descarta pixels para reduzir a resolução por fatores inteiros e grava um quadro numa memória de dois clocks. O processador lê o quadro pelo barramento, depois que o periférico avisa que ele está pronto. O periférico não fala I2C: o software programa o ADV7180 com o periférico I2C da plataforma.

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `fb_width` | 160 | Largura da memória do quadro em pixels |
| `fb_height` | 120 | Altura da memória do quadro em pixels |
| `src_width` | 720 | Largura em pixels da área de origem capturada, a partir do canto superior esquerdo (720 no NTSC) |
| `src_height` | 480 | Altura em linhas da área de origem capturada, contando os dois campos (480 no NTSC) |
| `check_protection` | `true` | Confere os quatro bits de proteção de cada código de temporização |
| `present_cycles` | 4096 | Ciclos de `TD_CLK27` sem código válido depois dos quais o vídeo é dado como ausente |

O quadro cabe na memória se $\lceil \text{src\_width} / x \rceil \le \text{fb\_width}$ e $\lceil \text{src\_height} / y \rceil \le \text{fb\_height}$ para os fatores de decimação $x$ e $y$ escolhidos; o que passa disso é descartado.

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura do processador |
| `i_address` | entrada | Endereço de palavra de 4 bits |
| `i_data_in`, `o_data_out` | entrada, saída | Dado de escrita e de leitura (`word_t`); os registradores usam os 32 bits baixos |
| `o_irq` | saída | Interrupção em nível, ativa em 1 |
| `i_td_clk27` | entrada | `TD_CLK27`, assíncrono em relação a `i_clk` |
| `i_td_data` | entrada | `TD_DATA[7:0]` |
| `o_td_reset_n` | saída | `TD_RESET_N`, controlado pelo bit `DECODER_RUN` |

O reset do sistema deve durar pelo menos três ciclos de `i_td_clk27`.

## 4. O fluxo BT.656

Cada linha tem um prefixo de referência de quatro bytes, `FF 00 00 XY`, no início (SAV) e no fim (EAV) do vídeo ativo. O byte `XY` tem a forma $1\,F\,V\,H\,P_3\,P_2\,P_1\,P_0$.

| Bit | Nome | Significado |
| :--- | :--- | :--- |
| 6 | `F` | Campo, 0 no primeiro e 1 no segundo |
| 5 | `V` | 1 fora do vídeo ativo (apagamento vertical) |
| 4 | `H` | 1 no EAV, 0 no SAV |
| 3 a 0 | `P` | Proteção, $P_3 = V \oplus H$, $P_2 = F \oplus H$, $P_1 = F \oplus V$ e $P_0 = F \oplus V \oplus H$ |

Entre o SAV e o EAV de uma linha ativa os bytes seguem a ordem Cb, Y, Cr, Y, com 1440 bytes por linha para 720 pixels. Cada grupo de quatro bytes gera dois pixels que repartem o Cb e o Cr. Os três bytes que antecedem o `XY` de um EAV só são reconhecidos como prefixo nele e por isso são retirados da fila de pixels; nenhum byte de prefixo vira pixel. No NTSC o quadro tem 525 linhas de 1716 bytes, e cada campo tem 240 linhas ativas.

### 4.1. Eventos de sincronismo

| Evento | Condição |
| :--- | :--- |
| Início de linha | SAV com $V = 0$ |
| Início de campo | Início de linha com o código anterior de $V = 1$ |
| Fim de campo | Primeiro código com $V = 1$ depois de vídeo ativo |
| Erro de sincronismo | Proteção inválida, SAV dentro de uma linha, EAV fora de uma linha ou EAV no meio de um grupo Cb Y Cr Y |

O vídeo é dado como presente enquanto o último código válido tem menos de `present_cycles` ciclos.

## 5. Captura de um quadro

Uma escrita de 1 em `START` pede a captura de um quadro, desde que não haja captura em andamento. A captura espera o início do primeiro campo pedido, grava as linhas ativas e termina no fim do último campo. O campo é escolhido em `FORMAT`.

| `FIELD` | Campos capturados | Linha de origem |
| :--- | :--- | :--- |
| 0 | Os dois, entrelaçados | A linha $n$ do campo $F$ é a linha $2n + F$ do quadro |
| 1 | Só o primeiro | A linha $n$ do campo é a linha $n$ |
| 2 | Só o segundo | A linha $n$ do campo é a linha $n$ |

A captura é abortada, sem quadro pronto e com o erro de sincronismo levantado, se o vídeo deixa de estar presente ou se um campo chega fora da ordem esperada. Pedir a captura sem vídeo presente aborta na hora.

### 5.1. Decimação

Com os fatores $x$ em colunas e $y$ em linhas, o pixel de coluna $c$ e linha $r$ da origem vai à memória só se $c$ e $r$ forem múltiplos de $x$ e de $y$, e sua posição na memória é $(c / x,\ r / y)$. A decimação é por amostragem pontual, sem média. Pixels fora de `src_width` por `src_height` ou fora de `fb_width` por `fb_height` são descartados.

### 5.2. Formato do pixel

| `PIXEL` | Formato | Pixels por palavra |
| :--- | :--- | :--- |
| 0 | RGB565, vermelho nos bits 15:11, verde em 10:5 e azul em 4:0 | 2, o de índice par nos bits 15:0 |
| 1 | Luminância Y de 8 bits | 4, o de índice $4k + n$ no byte $n$ |

O pixel de índice $i$ é o da linha $\lfloor i / \text{fb\_width} \rfloor$ e coluna $i \bmod \text{fb\_width}$ da memória. A conversão segue o ITU-R BT.601 com luminância de 16 a 235, em ponto fixo de 8 bits fracionários, e satura cada canal em 0 a 255 antes de reduzi-lo:

$$R = \frac{298\,(Y - 16) + 409\,(C_r - 128) + 128}{256}$$

$$G = \frac{298\,(Y - 16) - 100\,(C_b - 128) - 208\,(C_r - 128) + 128}{256}$$

$$B = \frac{298\,(Y - 16) + 516\,(C_b - 128) + 128}{256}$$

Com $Y < 16$ o termo de luminância vale zero.

## 6. Mapa de registradores

Os acessos são de 32 bits. O endereço de palavra é o deslocamento em bytes dividido por 4.

| Palavra | Deslocamento | Nome | Acesso | Reset | Descrição |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 0 | `0x00` | `CTRL` | L/E | 0 | Controle |
| 1 | `0x04` | `STATUS` | L/E1C | 0 | Estado |
| 2 | `0x08` | `FRAME_COUNT` | L | 0 | Quadros completos capturados desde o reset |
| 3 | `0x0C` | `DECIMATION` | L/E | `0x0101` | Fatores de decimação |
| 4 | `0x10` | `FORMAT` | L/E | 0 | Formato do pixel e campo |
| 5 | `0x14` | `GEOMETRY` | L | generics | Largura nos bits 15:0 e altura nos 31:16 da memória do quadro |
| 6 | `0x18` | `RD_ADDR` | L/E | 0 | Ponteiro de palavra de leitura da memória do quadro |
| 7 | `0x1C` | `RD_DATA` | L | 0 | Palavra da memória do quadro no ponteiro, com incremento do ponteiro |
| 8 | `0x20` | `SOURCE` | L | generics | `src_width` nos bits 15:0 e `src_height` nos 31:16 |

Um endereço sem registrador lê zero e ignora a escrita. E1C é escrita de 1 para limpar.

### 6.1. `CTRL`

| Bit | Nome | Acesso | Descrição |
| :--- | :--- | :--- | :--- |
| 0 | `START` | E | Escrever 1 inicia a captura de um quadro; ignorado com a captura em andamento; lê 0. Também limpa `READY` |
| 1 | `FRAME_IRQ` | L/E | Habilita a interrupção de quadro pronto |
| 2 | `ERROR_IRQ` | L/E | Habilita a interrupção de erro de sincronismo |
| 3 | `DECODER_RUN` | L/E | Vale 1 para soltar o reset do decodificador (`TD_RESET_N` em nível alto); no reset vale 0 |

Toda escrita em `CTRL` grava os bits 1 a 3 com os valores escritos.

### 6.2. `STATUS`

| Bit | Nome | Acesso | Descrição |
| :--- | :--- | :--- | :--- |
| 0 | `BUSY` | L | Captura em andamento, de um `START` aceito até o fim da captura |
| 1 | `READY` | L/E1C | Quadro completo na memória; sobe no fim de uma captura completa e cai com `START` |
| 2 | `ERROR` | L/E1C | Erro de sincronismo desde que foi limpo, por erro do receptor ou captura abortada |
| 3 | `PRESENT` | L | Códigos de temporização válidos chegando |

### 6.3. `DECIMATION`, `FORMAT` e leitura da memória

| Registrador | Campo | Bits | Descrição |
| :--- | :--- | :--- | :--- |
| `DECIMATION` | `X_DIV` | 7:0 | Fator em x de 1 a 255; escrever 0 grava 1 |
| `DECIMATION` | `Y_DIV` | 15:8 | Fator em y de 1 a 255; escrever 0 grava 1 |
| `FORMAT` | `PIXEL` | 0 | 0 RGB565, 1 luminância |
| `FORMAT` | `FIELD` | 2:1 | 0 e 3 os dois campos, 1 só o primeiro, 2 só o segundo |

`DECIMATION` e `FORMAT` só aceitam escrita com a captura parada. O ponteiro `RD_ADDR` conta palavras de 32 bits de 0 a $\lceil \text{fb\_width} \cdot \text{fb\_height} / 2 \rceil - 1$; escrever um valor fora da memória é ignorado. Cada leitura de `RD_DATA` devolve a palavra do ponteiro e o avança, voltando a 0 depois da última palavra. A palavra de um ponteiro recém-escrito fica disponível na leitura seguinte. Ler a memória durante uma captura pode devolver pixels antigos e novos misturados.

## 7. Interrupção

`o_irq` é um nível, $\text{FRAME\_IRQ} \cdot \text{READY} + \text{ERROR\_IRQ} \cdot \text{ERROR}$. Ele cai quando o software escreve 1 no bit de `STATUS` que o causou (ou, para `READY`, com um novo `START`).

## 8. Domínios de clock

| Sinal | Origem | Destino | Cruzamento |
| :--- | :--- | :--- | :--- |
| Reset | `i_clk` | `i_td_clk27` | Sincronizador de dois estágios |
| Pedido de captura | `i_clk` | `i_td_clk27` | Toggle em sincronizador de dois estágios |
| Fim de captura | `i_td_clk27` | `i_clk` | Toggle em sincronizador de dois estágios |
| Erro do receptor | `i_td_clk27` | `i_clk` | Toggle em sincronizador de dois estágios |
| Vídeo presente | `i_td_clk27` | `i_clk` | Nível em sincronizador de dois estágios |
| Resultado da captura, fatores, formato e campo | entre os dois | | Vetores parados no momento em que o toggle os revela |
| Pixels | `i_td_clk27` | `i_clk` | Memória de duas portas, uma porta em cada clock |

Os toggles de erro e de fim de captura são lidos em `i_clk`; `i_clk` deve ser mais rápido que 13,5 MHz (metade de `TD_CLK27`), pois dois códigos de temporização distam pelo menos quatro ciclos de `TD_CLK27` e um toggle por erro não pode se perder. O arquivo de restrições da plataforma deve cortar com `set_false_path` o caminho que entra no primeiro estágio de cada sincronizador, os vetores parados e o caminho entre as duas portas da memória.

## 9. Memória

A memória do quadro tem $\lceil \text{fb\_width} \cdot \text{fb\_height} / 2 \rceil$ palavras de 32 bits em quatro faixas de byte, para que o Quartus infira blocos de memória com habilitação de bytes. Cada faixa ocupa $\lceil \text{palavras} / 1024 \rceil$ blocos de 1024 palavras de 8 bits, e a memória inteira ocupa quatro vezes isso.

| Configuração | Palavras | Blocos de memória |
| :--- | :--- | :--- |
| 160x120 (padrão) | 9600 | 40 |
| 180x120 | 10800 | 44 |
| 320x240 | 38400 | 152 |

A DE2-115 (Cyclone IV E) tem 432 blocos M9K.

## 10. Uso pelo software

O exemplo captura um quadro RGB565 decimado por 4 em x e em y (180x120) e o copia para um vetor. A configuração do ADV7180 por I2C vem antes, com o periférico I2C da plataforma, e não faz parte deste periférico.

```c
#include <stdint.h>

#define TV_CTRL        0
#define TV_STATUS      1
#define TV_FRAME_COUNT 2
#define TV_DECIMATION  3
#define TV_FORMAT      4
#define TV_GEOMETRY    5
#define TV_RD_ADDR     6
#define TV_RD_DATA     7

#define CTRL_START       (1u << 0)
#define CTRL_DECODER_RUN (1u << 3)
#define STATUS_BUSY      (1u << 0)
#define STATUS_READY     (1u << 1)
#define STATUS_ERROR     (1u << 2)
#define STATUS_PRESENT   (1u << 3)

/* Captura um quadro RGB565 dos dois campos, decimado por x_div e y_div, em out.
   Devolve 0 em sucesso e -1 se a captura falhou. */
int tv_capture_frame(volatile uint32_t *tv, uint16_t *out, uint32_t x_div, uint32_t y_div)
{
    tv[TV_CTRL] = CTRL_DECODER_RUN;                  /* solta o reset do ADV7180 */
    /* ... aqui o software programa o ADV7180 por I2C e espera o vídeo ... */
    while ((tv[TV_STATUS] & STATUS_PRESENT) == 0) {
    }

    tv[TV_DECIMATION] = (y_div << 8) | x_div;
    tv[TV_FORMAT]     = 0;                           /* RGB565, dois campos */
    tv[TV_STATUS]     = STATUS_READY | STATUS_ERROR; /* limpa os avisos antigos */
    tv[TV_CTRL]       = CTRL_START | CTRL_DECODER_RUN;

    uint32_t status;
    do {
        status = tv[TV_STATUS];
    } while ((status & STATUS_BUSY) != 0);

    if ((status & STATUS_READY) == 0) {
        return -1;
    }

    uint32_t geometry = tv[TV_GEOMETRY];
    uint32_t pixels   = (geometry & 0xFFFFu) * (geometry >> 16);

    tv[TV_RD_ADDR] = 0;
    for (uint32_t i = 0; i < pixels; i += 2) {
        uint32_t word = tv[TV_RD_DATA];
        out[i]     = (uint16_t)(word & 0xFFFFu);
        if (i + 1 < pixels) {
            out[i + 1] = (uint16_t)(word >> 16);
        }
    }

    return 0;
}
```

Com interrupção, o software habilita `FRAME_IRQ` em `CTRL`, retorna depois do `START` e, no tratador, lê `STATUS`, copia o quadro e escreve 1 em `READY` para baixar `o_irq`. Uma captura leva até um campo de espera mais um quadro, ou seja, cerca de 50 ms no NTSC.

## 11. Verificação

| Verificação | Cobertura |
| :--- | :--- |
| Testes de entidade `TV` | Gerador de fluxo NTSC BT.656 de 720x480 entrelaçado, 525 linhas de 1716 bytes. Valores de reset e geometria, captura de um quadro RGB565 dos dois campos com decimação 4x4 e interrupção, de luminância do segundo campo com decimação 4x2, com fatores 3 e 5 que cortam colunas além da memória, regras de configuração com a captura em curso, erro de proteção injetado, captura sem vídeo e ponteiro de leitura. Cada pixel gravado é comparado com um modelo |
| Testes de entidade `TVReceiver` e `TVColor` | Receptor: pixels contra os bytes enviados, um início e um fim de campo, segundo campo, prefixo que nunca vira pixel, proteção inválida, linha desalinhada, SAV sem EAV e fim da presença do vídeo. Cor: conversão para RGB565 e luminância contra o modelo, com os extremos de Y, Cb e Cr e 3000 pixels ao acaso, e o empacotamento por índice |
| Testes de entidade `TVRegs` e `TVCapture` | Registradores: reset, início e fim por toggle, configuração travada com a captura em curso, interrupção com as máscaras, erro do receptor e ponteiro de leitura. Controle: decimação em x e em y, campos entrelaçados e campo único, abortos por falta de vídeo e por campo fora de ordem e fim de campo sem início |
| Prova formal `tv_regs` | Os registradores, a interrupção, o toggle de pedido, a trava de configuração, o quadro pronto, o contador, o erro e o ponteiro de leitura seguem um modelo de referência para qualquer sequência de acessos e de eventos do outro domínio; nove defeitos injetados são todos pegos; cover de fim de captura completa e abortada |
| Prova formal `tv_capture` | Protocolo da captura de um quadro nos três modos de campo: um único pulso de fim, quadro completo só depois dos campos pedidos, na ordem, pixels só durante a captura e dentro da memória, reset; três defeitos injetados são pegos; cover de um quadro completo |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

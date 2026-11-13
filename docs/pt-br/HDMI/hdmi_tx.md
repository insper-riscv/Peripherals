# Saída de vídeo HDMI

🌐 [Português](../../pt-br/HDMI/hdmi_tx.md) · [English](../../en/HDMI/hdmi_tx.md)

## 1. Referência

O periférico entrega vídeo digital paralelo ao transmissor HDMI de uma placa. O transmissor é o ADV7513 da Analog Devices, que recebe pixels RGB de 24 bits em 4:4:4 com os sinais DE (habilitação de dados), HS e VS, faz a codificação TMDS e atende modos de vídeo até 1080p com clock de pixel de até 165 MHz. O manual da DE10-Nano descreve o barramento de pixel como R[7:0] nos bits 23:16, G[7:0] nos bits 15:8 e B[7:0] nos bits 7:0, e a configuração do chip por uma interface I2C.

O periférico não conhece a placa: o modo de vídeo, o formato do pixel e a tabela de inicialização do chip chegam por generics, e o clock de pixel vem de uma PLL do topo da placa.

### 1.1. Pinos do manual da DE10-Nano

Os sinais abaixo são os que o manual da placa (Tabela 3-13) liga ao transmissor, todos em 3,3 V. O topo da placa os liga às portas do periférico.

| Sinal da placa | Pino do FPGA | Porta do periférico |
| :--- | :--- | :--- |
| `HDMI_TX_D0` a `HDMI_TX_D7` | AD12, AE12, W8, Y8, AD11, AD10, AE11, Y5 | `o_tx_d(0)` a `o_tx_d(7)`, canal azul |
| `HDMI_TX_D8` a `HDMI_TX_D15` | AF10, Y4, AE9, AB4, AE7, AF6, AF8, AF5 | `o_tx_d(8)` a `o_tx_d(15)`, canal verde |
| `HDMI_TX_D16` a `HDMI_TX_D23` | AE4, AH2, AH4, AH5, AH6, AG6, AF9, AE8 | `o_tx_d(16)` a `o_tx_d(23)`, canal vermelho |
| `HDMI_TX_CLK` | AG5 | `o_tx_clk` |
| `HDMI_TX_DE` | AD19 | `o_tx_de` |
| `HDMI_TX_HS` | T8 | `o_tx_hs` |
| `HDMI_TX_VS` | V13 | `o_tx_vs` |
| `HDMI_TX_INT` | AF11 | `i_tx_int` |
| `I2C_SCL` | U10 | `o_i2c_scl_out` e `o_i2c_scl_oe` |
| `I2C_SDA` | AA4 | `i_i2c_sda`, `o_i2c_sda_out` e `o_i2c_sda_oe` |

Os pinos de áudio do transmissor (`HDMI_I2S0`, `HDMI_MCLK`, `HDMI_LRCLK` e `HDMI_SCLK`) não são usados, porque o periférico não transporta áudio HDMI.

## 2. O que é

O processador escreve pixels em um framebuffer, e uma varredura independente os lê e os envia ao transmissor. O periférico é um invólucro fino sobre os blocos do periférico de vídeo (`docs/pt-br/video/video.md`) e acrescenta o que é próprio do HDMI.

| Bloco | Domínio | Função |
| :--- | :--- | :--- |
| `video_timing` | pixel | Contadores de coluna e linha, sincronismos com polaridade, área visível e coordenadas do framebuffer |
| `video_dpram` | sistema e pixel | Memória de duas portas com clocks independentes, uma para o framebuffer e outra para a paleta |
| `video_regs` | sistema | Registradores de controle, estado do quadro, geometria e formato, janela do framebuffer e paleta |
| `hdmi_scanout` | pixel | Endereço de leitura, escolha do pixel na palavra, paleta ou expansão de RGB565 para 24 bits |
| `hdmi_out` | pixel | Registrador de saída do barramento RGB, de DE, de HS e de VS |
| `hdmi_regs` | sistema | Registradores do HDMI (modo, estado, interrupções, reinício da inicialização) |
| `hdmi_init_seq` | sistema | Percorre a tabela de pares registrador-valor e pede uma escrita I2C por par |
| `hdmi_i2c_writer` | sistema | Mestre I2C somente de escrita, a 100 kHz, de dreno aberto |
| `hdmi_tx` | ambos | Topo estrutural, só instancia e conecta os blocos |

Cada pixel do framebuffer cobre `scale` x `scale` pixels da tela, e a imagem fica centrada na área visível, com faixas pretas no que sobra do quadro. O framebuffer fica em memória de duas portas, escrita no clock do sistema e lida no clock de pixel.

A temporização, a memória de duas portas e os registradores do framebuffer são os do vídeo genérico por generics, sem cópia.

### 2.1. Generics

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `clk_freq` | 100000000 | Frequência do clock do sistema em Hz, base do SCL do I2C |
| `fb_width`, `fb_height` | 320, 180 | Dimensões do framebuffer; uma linha deve ocupar um número inteiro de palavras de 32 bits |
| `pixel_format` | `"indexed"` | `"indexed"` (8 bits com paleta de 24 bits) ou `"direct"` (RGB565 de 16 bits) |
| `scale` | 4 | Fator de ampliação em x e em y; a imagem ampliada deve caber na área visível |
| `addr_width` | 16 | Largura do endereço de palavra da janela, no mínimo 11 e maior que o endereço do framebuffer |
| `h_visible`, `v_visible` | 1280, 720 | Pixels visíveis por linha e linhas visíveis por quadro |
| `h_front_porch`, `v_front_porch` | 110, 5 | Pórticos frontais |
| `h_sync`, `v_sync` | 40, 5 | Largura do pulso de sincronismo em pixels e em linhas |
| `h_back_porch`, `v_back_porch` | 220, 20 | Pórticos traseiros |
| `h_sync_positive`, `v_sync_positive` | verdadeiro, verdadeiro | Polaridade do pulso, verdadeiro para nível alto durante o pulso |
| `mode_id` | 4 | Número do modo CEA-861 (VIC), ou 0 para um modo próprio; só informativo |
| `pixel_clock_khz` | 74250 | Clock de pixel do modo em kHz; só informativo, o clock real vem da PLL |
| `init_enable` | falso | Inclui o sequenciador de inicialização do transmissor |
| `init_auto_start` | verdadeiro | A sequência começa sozinha depois do reset |
| `init_table` | `""` | Tabela de inicialização, quatro dígitos hexadecimais por entrada (seção 7) |
| `i2c_dev_addr` | `0111001` | Endereço de 7 bits do transmissor no I2C |
| `i2c_freq` | 100000 | Frequência do SCL em Hz |
| `int_active_low` | verdadeiro | O pino de interrupção do transmissor é ativo em nível baixo |

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_pixel_clk` | entrada | Clock de pixel, assíncrono em relação a `i_clk` |
| `i_data_in`, `i_address` | entrada | Dado de escrita de 32 bits e endereço de palavra de `addr_width` bits |
| `i_byteena` | entrada | Habilitação de bytes da escrita, um bit por byte |
| `i_write` | entrada | Pulso de escrita do processador |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço |
| `o_irq` | saída | Interrupção em nível (seção 8) |
| `o_tx_d` | saída | Barramento de vídeo RGB de 24 bits, vermelho em 23:16 |
| `o_tx_clk` | saída | O próprio `i_pixel_clk`, para o pino `HDMI_TX_CLK` |
| `o_tx_de`, `o_tx_hs`, `o_tx_vs` | saída | Habilitação de dados e sincronismos, com a polaridade do modo |
| `i_tx_int` | entrada | Pino de interrupção do transmissor, assíncrono |
| `i_i2c_sda` | entrada | Nível da linha SDA lido do pino, assíncrono |
| `o_i2c_sda_out`, `o_i2c_sda_oe` | saída | Valor (sempre 0) e habilitação de saída de SDA; habilitada puxa a linha para baixo |
| `o_i2c_scl_out`, `o_i2c_scl_oe` | saída | Valor (sempre 0) e habilitação de saída de SCL |

O periférico não instancia buffer de fabricante. A camada de tristate do topo da placa coloca cada pino I2C em alta impedância quando a habilitação vale 0, e o resistor de pull-up da placa leva a linha a 1. A leitura do periférico não tem efeito colateral, por isso não há pulso de leitura. O reset do sistema deve durar pelo menos três ciclos de `i_pixel_clk`, porque ele alcança o domínio de pixel por um sincronizador de dois estágios.

## 4. Mapa de endereços

Os acessos são de 32 bits, e os endereços abaixo são de palavra. O bit mais significativo de `i_address` separa a janela do framebuffer do espaço de registradores.

| Endereço de palavra | Conteúdo | Acesso |
| :--- | :--- | :--- |
| 0 | Controle, bit 0 liga a exibição do framebuffer (reset 0) | L/E |
| 1 | Estado do quadro, bit 0 vale 1 durante o pulso de VS e bit 1 durante o apagamento vertical | L |
| 2 | Contador de quadros, uma unidade a cada início de apagamento vertical | L |
| 3 | Geometria, largura nos bits 15:0 e altura nos bits 31:16 | L |
| 4 | Formato, bits por pixel em 7:0, ampliação em 15:8, bits por canal em 23:16 e bit 24 em 1 no formato indexado | L |
| 8 | Modo (seção 4.1) | L |
| 9 | Estado do transmissor (seção 4.1) | L |
| 10 | Habilitação das interrupções (seção 8) | L/E |
| 11 | Interrupções pendentes (seção 8) | L/E1C |
| 12 | Controle do sequenciador de inicialização (seção 7.3) | E |
| 13 | Contadores do sequenciador (seção 7.3) | L |
| 14 | Clock de pixel do modo em kHz | L |
| 256 a 511 | Paleta de 256 entradas de 24 bits, só no formato indexado | E |
| `2^(addr_width-1)` em diante | Framebuffer, uma palavra por endereço | E |

Um endereço sem registrador lê zero e ignora a escrita. O framebuffer e a paleta não podem ser lidos. Com `addr_width` igual a 16 a janela tem 256 KiB e o framebuffer começa no deslocamento de byte `0x20000`.

A escrita no framebuffer grava só os bytes marcados em `i_byteena`, de modo que um `sw` troca quatro pixels indexados ou dois RGB565, um `sh` troca metade disso e um `sb` troca um byte. A escrita na paleta exige as três faixas baixas, e a cor ocupa os 24 bits baixos do dado. A escrita no framebuffer e na paleta chega à memória um ciclo do sistema depois do pulso de escrita.

### 4.1. Registradores do HDMI

| Palavra | Bits | Nome | Descrição |
| :--- | :--- | :--- | :--- |
| 8 | 7:0 | `MODE_ID` | Número do modo CEA-861 do generic `mode_id` |
| 8 | 8 | `HS_POS` | 1 se o sincronismo horizontal é positivo |
| 8 | 9 | `VS_POS` | 1 se o sincronismo vertical é positivo |
| 9 | 0 | `INT` | 1 enquanto o pino de interrupção do transmissor está ativo |
| 9 | 1 | `BUSY` | 1 enquanto o sequenciador escreve no chip |
| 9 | 2 | `DONE` | 1 depois que a tabela inteira foi escrita, até o próximo reinício |
| 9 | 3 | `NACK` | 1 se alguma escrita da tabela não recebeu confirmação do chip |
| 9 | 4 | `INIT` | 1 se a instância tem o sequenciador |
| 14 | 31:0 | `PIXEL_KHZ` | Generic `pixel_clock_khz` |

Todos os registradores zeram no reset, exceto os de leitura de generics.

## 5. Formato de pixel e memória

Um framebuffer guarda `32 / bits por pixel` pixels por palavra, com o pixel de menor índice nos bits menos significativos.

| `pixel_format` | Bits por pixel | Decodificação |
| :--- | :--- | :--- |
| `"indexed"` | 8 | O byte é um índice de 0 a 255, e a paleta devolve a cor de 24 bits (vermelho em 23:16, verde em 15:8 e azul em 7:0) |
| `"direct"` | 16 | RGB565, com vermelho em 15:11, verde em 10:5 e azul em 4:0, expandido para 24 bits repetindo os bits altos de cada canal nos bits que faltam, de modo que o branco `0xFFFF` vira `0xFFFFFF` |

O registrador de formato (palavra 4) informa 5 bits por canal no formato direto, que é o tamanho dos canais vermelho e azul; o canal verde tem 6 bits.

### 5.1. Resoluções que cabem na DE10-Nano

O FPGA da DE10-Nano tem 5570 kbit de memória embarcada, em 557 blocos M10K de 10 kbit. O framebuffer usa quatro faixas de 8 bits, e cada faixa ocupa blocos de 1024 palavras, de modo que

$$\text{blocos} = 4 \cdot \left\lceil \frac{\text{palavras}}{1024} \right\rceil \qquad \text{palavras} = \frac{\text{largura} \cdot \text{altura} \cdot \text{bits por pixel}}{32}$$

A paleta do formato indexado usa mais 1 bloco, de 256 entradas de 24 bits. A tabela mostra a estimativa para framebuffers de proporção 16:9 e de 4:3, com a ampliação que os leva a um modo CEA-861. A conta é feita sobre a organização acima e não sobre um relatório de síntese.

| Framebuffer | Formato | Palavras | Blocos M10K | Cabe em 557 | Ampliação para o modo |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 320x180 | indexado | 14400 | 61 | sim | 4 para 1280x720, 6 para 1920x1080 |
| 480x270 | indexado | 32400 | 129 | sim | 4 para 1920x1080 |
| 640x360 | indexado | 57600 | 229 | sim | 2 para 1280x720, 3 para 1920x1080 |
| 640x480 | indexado | 76800 | 301 | sim | 1 para 640x480 |
| 800x600 | indexado | 120000 | 473 | sim | 1 para um modo 800x600 |
| 960x540 | indexado | 129600 | 509 | sim | 2 para 1920x1080 |
| 1280x720 | indexado | 230400 | 901 | não | |
| 320x180 | RGB565 | 28800 | 116 | sim | 4 para 1280x720, 6 para 1920x1080 |
| 480x270 | RGB565 | 64800 | 256 | sim | 4 para 1920x1080 |
| 640x360 | RGB565 | 115200 | 452 | sim | 2 para 1280x720, 3 para 1920x1080 |
| 640x480 | RGB565 | 153600 | 600 | não | |

Um framebuffer de resolução nativa 1280x720 ou 1920x1080 não cabe na memória do FPGA e exigiria memória externa, que está fora do periférico.

## 6. Temporização

### 6.1. Parâmetros do modo

Cada direção tem área visível, pórtico frontal, sincronismo e pórtico traseiro, e o total é a soma dos quatro.

$$H_{total} = h\_visible + h\_front\_porch + h\_sync + h\_back\_porch$$

$$V_{total} = v\_visible + v\_front\_porch + v\_sync + v\_back\_porch$$

A coluna $h$ e a linha $v$ avançam a cada ciclo de pixel. O pulso começa em $h_s = h\_visible + h\_front\_porch$ e em $v_s = v\_visible + v\_front\_porch$, e as saídas valem o nível do pulso quando

$$h_s \le h < h_s + h\_sync \qquad v_s \le v < v_s + v\_sync$$

O nível do pulso é 1 se a polaridade é positiva e 0 se é negativa, e o repouso é o nível oposto. DE vale 1 em toda a área visível, nas $h\_visible$ colunas de cada uma das $v\_visible$ linhas, e a taxa de quadros é $f_{pixel} / (H_{total} \cdot V_{total})$.

### 6.2. Modos CEA-861 documentados

| Modo | VIC | Visível | Pórtico frontal | Sincronismo | Pórtico traseiro | Total | Polaridade | Clock de pixel |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 640x480p60, horizontal | 1 | 640 | 16 | 96 | 48 | 800 | negativa | 25,2 MHz |
| 640x480p60, vertical | 1 | 480 | 10 | 2 | 33 | 525 | negativa | |
| 720x480p60, horizontal | 2 | 720 | 16 | 62 | 60 | 858 | negativa | 27,0 MHz |
| 720x480p60, vertical | 2 | 480 | 9 | 6 | 30 | 525 | negativa | |
| 1280x720p60, horizontal | 4 | 1280 | 110 | 40 | 220 | 1650 | positiva | 74,25 MHz |
| 1280x720p60, vertical | 4 | 720 | 5 | 5 | 20 | 750 | positiva | |
| 1920x1080p60, horizontal | 16 | 1920 | 88 | 44 | 148 | 2200 | positiva | 148,5 MHz |
| 1920x1080p60, vertical | 16 | 1080 | 4 | 5 | 36 | 1125 | positiva | |

O clock nominal do 640x480 é 25,175 MHz; com 25,2 MHz o quadro dura $800 \cdot 525 / 25{,}2\,\text{MHz}$ = 16,67 ms, ou 60 quadros por segundo. O ADV7513 aceita clock de pixel de até 165 MHz, e o manual da placa usa 25, 27 e 148,5 MHz nos modos 640x480, 720x480 e 1080p do seu exemplo. A PLL do topo da placa gera o clock do modo escolhido, e o topo passa a temporização do modo aos generics.

### 6.3. Posição da imagem e latência

A imagem ampliada tem $W = \text{fb\_width} \cdot \text{scale}$ colunas e $H = \text{fb\_height} \cdot \text{scale}$ linhas, e começa em

$$x_0 = \frac{h\_visible - W}{2} \qquad y_0 = \frac{v\_visible - H}{2}$$

Fora da imagem as três cores valem zero, mas DE continua em 1 em toda a área visível. A memória do framebuffer lê em um ciclo, a escolha do pixel leva um segundo e o registrador de saída um terceiro. Cores, DE, HS e VS atravessam os mesmos três estágios e saem alinhados, três ciclos de pixel depois dos contadores.

## 7. Inicialização do transmissor

### 7.1. Escritor I2C

Com `init_enable`, o periférico escreve registradores do ADV7513 sem ajuda do software. O escritor I2C é um mestre único somente de escrita, de 7 bits de endereço, que gera para cada par uma transação de partida, endereço do escravo com o bit de escrita, registrador, valor e parada, com uma confirmação depois de cada byte. Cada bit dura quatro quartos de período de SCL, e um quarto dura $\lfloor clk\_freq / (4 \cdot i2c\_freq) \rfloor$ ciclos do sistema. A confirmação é amostrada no meio do pulso de SCL e, se faltar, a transação segue até a parada e a escrita é contada como sem confirmação. O alongamento de SCL pelo escravo não é tratado.

### 7.2. Tabela de inicialização

A tabela é o generic `init_table`, uma cadeia com quatro dígitos hexadecimais por entrada, o registrador e depois o valor, na ordem de escrita. A cadeia `"980301001520"` escreve 0x03 no registrador 0x98, 0x00 no 0x01 e 0x20 no 0x15. A tabela aceita até 255 entradas, e uma cadeia vazia faz o sequenciador só marcar o fim.

O manual da DE10-Nano diz que o exemplo da Terasic usa RGB de 24 bits em 4:4:4, que o formato de vídeo e a frequência de áudio estão no registrador 0x15 e que o formato do registrador 0xAF também deve ser observado, e remete ao documento `ADV7513_Programming_Guide_R0.pdf` para os valores. Esse guia não faz parte do manual da placa, então a plataforma fornece todos os valores no generic `init_table`, e o periférico não traz nenhum valor padrão. Os pares usados nos testes são ilustrativos e não configuram o chip.

O endereço de 7 bits padrão do transmissor é `0x39`, o endereço de escrita de 8 bits `0x72` do chip sem o bit de escrita, e é o generic `i2c_dev_addr`.

### 7.3. Controle do sequenciador

| Palavra | Bits | Acesso | Descrição |
| :--- | :--- | :--- | :--- |
| 12 | 0 | E | Escrever 1 reinicia a tabela se o sequenciador está parado; durante a sequência a escrita é ignorada |
| 13 | 7:0 | L | Entradas já escritas desde o início, saturado em 255 |
| 13 | 15:8 | L | Escritas sem confirmação desde o início, saturado em 255 |
| 13 | 23:16 | L | Entradas da tabela |

Com `init_auto_start` verdadeiro a sequência começa sozinha depois do reset. Sem `init_enable`, as saídas do I2C ficam liberadas, e a escrita no registrador de controle é ignorada, o que deixa os pinos para um controlador I2C de software.

## 8. Interrupções

A saída `o_irq` vale 1 enquanto alguma interrupção pendente estiver habilitada. Os dois registradores têm os mesmos bits.

| Bit | Evento |
| :--- | :--- |
| 0 | Fim de quadro, a borda de subida do apagamento vertical |
| 1 | Ativação do pino de interrupção do transmissor, a borda para o nível ativo de `int_active_low` |

Um bit de `IRQ_PEND` sobe com o evento e só cai quando o processador escreve 1 nele. Um evento no mesmo ciclo da limpeza vence a limpeza. A leitura de `IRQ_PEND` não tem efeito colateral. O estado do pino aparece também no bit 0 do registrador de estado (palavra 9).

## 9. Ligação no topo da placa

1. A PLL do topo gera `i_pixel_clk` na frequência do modo e leva o mesmo clock ao pino `HDMI_TX_CLK` por `o_tx_clk`.
2. Os 24 bits de `o_tx_d`, `o_tx_de`, `o_tx_hs` e `o_tx_vs` vão aos pinos `HDMI_TX_D[23:0]`, `HDMI_TX_DE`, `HDMI_TX_HS` e `HDMI_TX_VS`.
3. `HDMI_TX_INT` entra em `i_tx_int`.
4. A camada de tristate liga `I2C_SCL` e `I2C_SDA` às portas de dreno aberto, com o pino em alta impedância quando a habilitação vale 0.
5. O .sdc declara `i_clk` e `i_pixel_clk` como clocks assíncronos.

## 10. Exemplo em C

O programa carrega uma paleta de oito cores, desenha oito barras verticais de 40 pixels em um framebuffer indexado de 320x180 (ampliado 4 vezes para 1280x720), espera a inicialização do chip, liga a exibição e conta quadros por polling da interrupção pendente.

```c
#include <stdint.h>

/* Base do periférico, definida pela plataforma. */
#define HDMI_BASE 0x40000000u
#define HDMI_REG(word) (*(volatile uint32_t *)(HDMI_BASE + 4u * (word)))

#define REG_CTRL      0u
#define REG_STATUS    9u
#define REG_IRQ_PEND  11u
#define REG_PALETTE   256u
/* addr_width = 16, framebuffer na metade alta da janela. */
#define REG_FB        (1u << 15)

#define STATUS_DONE   (1u << 2)
#define STATUS_INIT   (1u << 4)
#define IRQ_FRAME     (1u << 0)

#define FB_WIDTH      320u
#define FB_HEIGHT     180u
#define BAR_WIDTH     40u
#define BARS          8u

static const uint32_t bar_colors[BARS] = {
    0xFFFFFFu, 0xFFFF00u, 0x00FFFFu, 0x00FF00u,
    0xFF00FFu, 0xFF0000u, 0x0000FFu, 0x000000u,
};

static void draw_bars(void)
{
    /* Quatro pixels indexados por palavra; a barra cobre 10 palavras. */
    for (uint32_t row = 0; row < FB_HEIGHT; row++) {
        for (uint32_t word = 0; word < FB_WIDTH / 4u; word++) {
            uint32_t bar = (word * 4u) / BAR_WIDTH;
            HDMI_REG(REG_FB + row * (FB_WIDTH / 4u) + word) = bar * 0x01010101u;
        }
    }
}

int main(void)
{
    for (uint32_t i = 0; i < BARS; i++) {
        HDMI_REG(REG_PALETTE + i) = bar_colors[i];
    }
    draw_bars();

    /* Com o sequenciador, espera a tabela chegar ao transmissor. */
    if (HDMI_REG(REG_STATUS) & STATUS_INIT) {
        while (!(HDMI_REG(REG_STATUS) & STATUS_DONE)) {
        }
    }

    HDMI_REG(REG_CTRL) = 1u;

    uint32_t frames = 0;
    for (;;) {
        if (HDMI_REG(REG_IRQ_PEND) & IRQ_FRAME) {
            HDMI_REG(REG_IRQ_PEND) = IRQ_FRAME;
            frames++;
        }
    }
}
```

## 11. Verificação

| Verificação | Cobertura |
| :--- | :--- |
| Testes de entidade `HdmiTxIndexed` e `HdmiTxDirect` | Monitor comportamental que mede largura de linha, de quadro, polaridades, largura dos pulsos de HS e VS, DE e pórticos, e confere cada pixel de dois quadros contra o framebuffer e a paleta, com a exibição ligada e desligada; mapa de registradores, interrupção de fim de quadro e interrupção do pino do transmissor |
| Testes de entidade `HdmiTxCea640x480`, `HdmiTxCea720x480`, `HdmiTxCea1280x720` e `HdmiTxCea1920x1080` | Largura de linha e de quadro, pulsos, polaridades, DE e pórticos medidos nos quatro modos CEA-861 com o clock de pixel de cada um |
| Testes de entidade `HdmiTxInit` e `HdmiTxNoInit` | Modelo de escravo I2C do ADV7513 que registra as escritas da inicialização (ordem, endereço, valor), reinício, contagem de escritas sem confirmação e pinos livres sem o sequenciador |
| Testes de entidade `HdmiI2cWriter`, `HdmiInitSeq`, `HdmiInitSeqManual` e `HdmiInitSeqEmpty` | Transação, confirmação, período de SCL a 100 kHz, início automático e manual, NACK e tabela vazia |
| Testes de entidade `HdmiScanoutIndexed`, `HdmiScanoutDirect`, `HdmiOut` e `HdmiRegs` | Escolha do pixel, paleta, expansão de RGB565, latência, máscara da cor, reset, interrupções e leitura de cada palavra |
| Provas formais `hdmitim_*`, `hdmiregs_*`, `hdmiseq_*` e `hdmii2c_*` | Contagens do gerador de temporização contra os generics (indução e medida só nas saídas), registradores e interrupções do HDMI (indução), ordem e contagens do sequenciador, protocolo de dreno aberto do escritor I2C, com mutantes de cada bloco |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

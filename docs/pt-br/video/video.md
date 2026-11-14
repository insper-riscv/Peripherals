# Vídeo VGA

🌐 [Português](../../pt-br/video/video.md) · [English](../../en/video/video.md)

## 1. Referência

O periférico gera um modo de vídeo VGA qualquer a partir de generics, sem conhecer placa nem pino. O modo padrão é o 640x480 a 60 Hz do padrão VESA, com 800 x 525 pixels totais por quadro e sincronismos de polaridade negativa. O clock de pixel nominal é 25,175 MHz; com 25 MHz o quadro dura $800 \cdot 525 / 25\,\text{MHz} = 16{,}8\ \text{ms}$, ou 59,52 quadros por segundo, dentro da tolerância dos monitores.

A largura de cada canal de cor também é um generic. A DE0-CV liga as saídas a um conversor resistivo de 4 bits por canal, e a DE2-115 a um ADV7123 de 8 bits por canal, que pede ainda os sinais de apagamento e de sincronismo composto.

## 2. O que é

O processador escreve pixels em um framebuffer, e uma varredura independente os lê e os envia ao monitor. O framebuffer fica em uma memória de duas portas com clocks independentes, escrita no clock do sistema e lida no clock de pixel. Cada pixel do framebuffer cobre `scale` x `scale` pixels da tela, e a imagem fica centrada na área visível, com faixas pretas no que sobra do quadro. O clock de pixel vem de fora do periférico, normalmente de uma PLL do topo da placa.

### 2.1. Generics

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `fb_width` | 320 | Largura do framebuffer em pixels; uma linha deve ocupar um número inteiro de palavras de 32 bits |
| `fb_height` | 200 | Altura do framebuffer em pixels |
| `channel_bits` | 4 | Bits de cada canal de cor, de 1 a 10 (4 na DE0-CV, 8 na DE2-115) |
| `pixel_format` | `"indexed"` | Formato do pixel, `"indexed"` ou `"direct"` (seção 5) |
| `scale` | 2 | Fator de ampliação em x e em y; a imagem ampliada deve caber na área visível |
| `addr_width` | 16 | Largura do endereço de palavra da janela, no mínimo 11 e maior que o endereço do framebuffer |
| `h_visible`, `v_visible` | 640, 480 | Pixels visíveis por linha e linhas visíveis por quadro |
| `h_front_porch`, `v_front_porch` | 16, 10 | Pórticos frontais, entre o fim da área visível e o pulso de sincronismo |
| `h_sync`, `v_sync` | 96, 2 | Largura do pulso de sincronismo em pixels e em linhas |
| `h_back_porch`, `v_back_porch` | 48, 33 | Pórticos traseiros, entre o pulso de sincronismo e a área visível |
| `h_sync_positive`, `v_sync_positive` | falso, falso | Polaridade do pulso, verdadeiro para nível alto durante o pulso |

Com os valores padrão a imagem ocupa 640x400 e as faixas pretas têm 40 linhas no alto e 40 embaixo. Os valores de temporização de cada modo vêm do catálogo de modos da placa, e o gerador de topo os passa ao periférico.

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_pixel_clk` | entrada | Clock de pixel, assíncrono em relação a `i_clk` |
| `i_data_in`, `i_address` | entrada | Dado de escrita de `XLEN` bits (`word_t`) e endereço de palavra de `addr_width` bits |
| `i_byteena` | entrada | Habilitação de bytes da escrita, um bit por byte |
| `i_write` | entrada | Pulso de escrita do processador |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço |
| `o_vga_r`, `o_vga_g`, `o_vga_b` | saída | Canais de cor de `channel_bits` bits cada |
| `o_vga_hs`, `o_vga_vs` | saída | Sincronismos horizontal e vertical, com a polaridade do modo |
| `o_vga_blank_n` | saída | Apagamento do conversor, em nível baixo fora da área visível (pino `VGA_BLANK_N` do ADV7123) |
| `o_vga_sync_n` | saída | Sincronismo composto do conversor, sempre em nível baixo (pino `VGA_SYNC_N` do ADV7123) |

Na DE0-CV os dois últimos sinais ficam sem ligação. Na DE2-115 o topo liga também `i_pixel_clk` ao pino `VGA_CLK` do conversor.

A leitura não tem efeito colateral, por isso não há pulso de leitura nem interrupção. O reset do sistema deve durar pelo menos três ciclos de `i_pixel_clk`, porque ele alcança o domínio de pixel por um sincronizador de dois estágios.

## 4. Mapa de endereços

Os acessos são de 32 bits, e os endereços abaixo são de palavra. O bit mais significativo de `i_address` separa a janela do framebuffer do espaço de registradores.

| Endereço de palavra | Conteúdo | Acesso |
| :--- | :--- | :--- |
| 0 | Controle, bit 0 liga a exibição do framebuffer (reset 0) | L/E |
| 1 | Estado, bit 0 vale 1 durante o pulso de sincronismo vertical e bit 1 vale 1 durante o apagamento vertical | L |
| 2 | Contador de quadros, uma unidade a cada início de apagamento vertical, zerado no reset | L |
| 3 | Geometria, largura do framebuffer nos bits 15:0 e altura nos bits 31:16 | L |
| 4 | Formato, bits por pixel nos bits 7:0, fator de ampliação nos bits 15:8, bits por canal nos bits 23:16 e bit 24 em 1 no formato indexado | L |
| 256 a 511 | Paleta de 256 entradas de $3 \cdot$ `channel_bits` bits, existe só no formato indexado | E |
| `2^(addr_width-1)` em diante | Framebuffer, uma palavra por endereço | E |

Um endereço sem registrador lê zero e ignora a escrita. O framebuffer e a paleta não podem ser lidos. Uma escrita na janela depois da última palavra do framebuffer é descartada.

Com `addr_width` igual a 16 a janela tem 256 KiB e o framebuffer começa no deslocamento `0x20000`. Uma plataforma que reserva uma janela maior que a do periférico liga a ele só os `addr_width` bits baixos do endereço de palavra.

### 4.1. Escrita com máscara de bytes

A escrita no framebuffer grava só os bytes marcados em `i_byteena`, de modo que um `sw` troca quatro pixels indexados ou dois diretos de 16 bits de uma vez, um `sh` troca metade disso e um `sb` troca um byte. A escrita na paleta exige as faixas baixas que guardam a cor, ou seja, duas faixas com 4 bits por canal e três com 8 bits por canal; um acesso que não as cubra é ignorado. A cor ocupa os $3 \cdot$ `channel_bits` bits baixos do dado, e os demais são ignorados. O registrador de controle muda se o byte 0 estiver habilitado. A escrita no framebuffer e na paleta chega à memória um ciclo de clock do sistema depois do pulso de escrita.

## 5. Formato de pixel

Um framebuffer guarda `32 / bits por pixel` pixels por palavra, com o pixel de menor índice nos bits menos significativos, que é a ordem de bytes do processador.

| `pixel_format` | Bits por pixel | Decodificação |
| :--- | :--- | :--- |
| `"indexed"` | 8 | O byte é um índice de 0 a 255, e a paleta devolve a cor de $3 \cdot$ `channel_bits` bits |
| `"direct"` | 16 se $3 \cdot$ `channel_bits` $\le 16$, senão 32 | Os $3 \cdot$ `channel_bits` bits baixos do pixel são a cor; os bits altos restantes são ignorados |

Em uma cor, o vermelho ocupa os `channel_bits` bits mais altos, o verde os do meio e o azul os mais baixos. Com 4 bits por canal a cor é um RGB444, e com 8 bits é um RGB888.

O formato indexado é o padrão porque é o formato nativo do DOOM, dispensa a conversão por pixel no processador e mantém o framebuffer em 8 bits por pixel qualquer que seja a largura do canal da placa. O formato direto dispensa a paleta e serve para exercitar o vídeo sem ela.

O pixel de índice $n$ do framebuffer, contado por linhas, fica na palavra $\lfloor n \cdot \text{bits} / 32 \rfloor$.

## 6. Temporização

### 6.1. Parâmetros do modo

Cada direção tem área visível, pórtico frontal, sincronismo e pórtico traseiro, e o total é a soma dos quatro.

$$H_{total} = h\_visible + h\_front\_porch + h\_sync + h\_back\_porch$$

$$V_{total} = v\_visible + v\_front\_porch + v\_sync + v\_back\_porch$$

A coluna $h$ e a linha $v$ avançam a cada ciclo de pixel, com $h$ de 0 a $H_{total}-1$ e $v$ de 0 a $V_{total}-1$. O pulso começa em $h_s = h\_visible + h\_front\_porch$ e em $v_s = v\_visible + v\_front\_porch$, e as saídas valem o nível do pulso quando

$$h_s \le h < h_s + h\_sync \qquad v_s \le v < v_s + v\_sync$$

O nível do pulso é 1 se a polaridade é positiva e 0 se é negativa, e o repouso é o nível oposto. O modo padrão tem os valores abaixo.

| Direção | Visível | Pórtico frontal | Sincronismo | Pórtico traseiro | Total | Polaridade |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Horizontal, em pixels | 640 | 16 | 96 | 48 | 800 | negativa |
| Vertical, em linhas | 480 | 10 | 2 | 33 | 525 | negativa |

### 6.2. Diagrama

Uma linha do modo padrão, com o tempo em ciclos de pixel. O pulso de HS dura 96 ciclos.

```
 h        0                    640   656      752       800
          |<--- visível 640 -->|<-16->|<- 96 ->|<- 48 ->|
 o_vga_hs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾
 cor      [  imagem ou preto  ]   preto     preto
```

Um quadro do modo padrão, com o tempo em linhas. O pulso de VS dura 2 linhas, ou 1600 ciclos.

```
 v        0                          480  490 492        525
          |<------ visível 480 ----->|<10>|2|<--- 33 ---->|
 o_vga_vs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_/‾‾‾‾‾‾‾‾‾‾‾‾
 vblank   ___________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 vsync    ______________________________/‾\___________________
```

Os bits de estado `vsync` e `vblank` lidos pelo processador valem 1 durante o pulso e depois da última linha visível, qualquer que seja a polaridade da saída.

### 6.3. Posição da imagem

A imagem ampliada tem $W = \text{fb\_width} \cdot \text{scale}$ colunas e $H = \text{fb\_height} \cdot \text{scale}$ linhas, e começa em

$$x_0 = \frac{h\_visible - W}{2} \qquad y_0 = \frac{v\_visible - H}{2}$$

O pixel da tela $(x, y)$ dentro da imagem mostra o pixel do framebuffer de coluna $\lfloor (x - x_0) / \text{scale} \rfloor$ e linha $\lfloor (y - y_0) / \text{scale} \rfloor$. Fora da imagem as três cores valem zero. Uma imagem de 320x200 com `scale` 2 em um modo 16:9 de 1280x720 ($W = 640$, $H = 400$) fica com faixas laterais de 320 colunas e faixas de 160 linhas no alto e embaixo, e com `scale` 3 ocupa 960x600.

### 6.4. Latência

A memória do framebuffer lê em um ciclo, a escolha do pixel leva um segundo e a saída do backend VGA é registrada em um terceiro. Os sincronismos, o apagamento e a marca de imagem atravessam os mesmos três estágios, então cores, HS, VS e `o_vga_blank_n` saem alinhados, três ciclos de pixel depois dos contadores. Os bits de estado vistos pelo processador vêm dos contadores, sem esse atraso.

## 7. Blocos

| Bloco | Domínio | Função |
| :--- | :--- | :--- |
| `video_timing` | pixel | Contadores de coluna e linha, sincronismos com polaridade, área visível e coordenadas do framebuffer |
| `video_scanout` | pixel | Endereço de leitura, escolha do pixel na palavra, paleta e decodificação da cor |
| `video_vga` | pixel | Registrador de saída dos canais, dos sincronismos e do apagamento, com o apagamento das cores fora da imagem |
| `video_regs` | sistema | Decodificação do barramento, registradores, contador de quadros e escritas do framebuffer e da paleta |
| `video_dpram` | os dois | Memória de duas portas com escrita por faixa de byte |
| `video` | os dois | Topo que só instancia e conecta os blocos e os sincronizadores |

## 8. Domínios de clock

| Sinal | Origem | Destino | Cruzamento |
| :--- | :--- | :--- | :--- |
| Reset | `i_clk` | `i_pixel_clk` | Sincronizador de dois estágios |
| Exibição habilitada | `i_clk` | `i_pixel_clk` | Sincronizador de dois estágios |
| Sincronismo e apagamento vertical | `i_pixel_clk` | `i_clk` | Dois bits registrados no domínio de pixel e sincronizador de dois estágios |
| Dados do framebuffer e da paleta | `i_clk` | `i_pixel_clk` | Memória de duas portas, uma porta em cada clock |

Os sinais que cruzam por sincronizador são níveis longos, de pelo menos uma linha do modo, e nenhum barramento de dados passa por sincronizador. Uma escrita do processador no mesmo endereço que a varredura lê naquele ciclo mostra o dado antigo ou o novo, sem outro efeito. O arquivo de restrições da plataforma deve declarar o caminho que entra no primeiro estágio de cada sincronizador como falso ou com atraso máximo, e o caminho entre as duas portas da memória como falso, pois não há relação de fase entre os clocks.

## 9. Memória

O framebuffer usa uma memória de 32 bits de largura em quatro faixas de byte, uma matriz própria por faixa, para que o Quartus infira blocos M10K com habilitação de bytes. Um bloco M10K tem 10240 bits.

$$\text{palavras} = \frac{\text{fb\_width} \cdot \text{fb\_height} \cdot \text{bits por pixel}}{32} \qquad \text{blocos por faixa} = \left\lceil \frac{\text{palavras}}{1024} \right\rceil$$

| Configuração | Palavras | Blocos M10K | Bits úteis |
| :--- | :--- | :--- | :--- |
| 320x200, indexado | 16000 | 64 mais 1 da paleta | 512 000 |
| 320x200, direto com 4 bits por canal | 32000 | 128 no máximo, 96 se o Quartus remover os 4 bits altos de cada pixel que a varredura nunca lê | 1 024 000 |
| 320x200, direto com 8 bits por canal | 64000 | 256 no máximo, 192 se o Quartus remover os 8 bits altos de cada pixel que a varredura nunca lê | 2 048 000 |

A DE0-CV tem 308 blocos M10K. A paleta de 256 entradas cabe em um bloco com 4 bits por canal (12 bits por entrada) e em dois com 8 bits por canal (24 bits por entrada).

## 10. Uso pelo software

1. Ler o registrador de formato para saber os bits por pixel, o fator de ampliação, os bits por canal e se há paleta.
2. No formato indexado, escrever as 256 entradas da paleta, cada uma com os $3 \cdot$ `channel_bits` bits baixos da palavra.
3. Escrever o pixel $n$ no framebuffer pela janela, em palavras de 32 bits com a máscara de bytes desejada.
4. Escrever 1 no registrador de controle para exibir o framebuffer.
5. Para trocar o conteúdo sem rasgar a imagem, ler o contador de quadros, esperar que ele mude (início do apagamento vertical) e então escrever; no modo padrão o apagamento dura 45 linhas, ou cerca de 1,4 ms.

## 11. Verificação

| Verificação | Cobertura |
| :--- | :--- |
| Testes de entidade `Video`, `VideoDirect`, `VideoSmall`, `VideoScale3`, `VideoPalette`, `VideoIndexedChannel8`, `VideoDirectChannel8`, `VideoTinyMode` e `VideoMixedPolarity` | Reset e registradores, contagem exata de ciclos de HS e VS na polaridade do modo, a área visível, as faixas pretas e o apagamento pixel a pixel contra um modelo, a duplicação em x e em y, a escrita aleatória com máscara de bytes e fora da janela útil, a paleta, o bit de sincronismo vertical, o contador de quadros e o cruzamento de clocks em três razões entre os clocks, nos dois formatos, com 4 e 8 bits por canal e em modos de outra resolução e polaridade |
| Testes de entidade `VideoTiming`, `VideoTimingScale3`, `VideoTimingFull`, `VideoTimingSvga`, `VideoTimingTiny` e `VideoTimingMixed` | Contadores, sincronismos nas duas polaridades, área visível, retângulo da imagem e coordenadas do framebuffer, inclusive com a imagem de 640x480 sem faixas e com o modo 800x600 |
| Testes de entidade `VideoDpram` e `VideoDpramNarrow` | Escrita por faixa, leitura registrada e razões entre os clocks |
| Testes de entidade `VideoRegs`, `VideoRegsDirect`, `VideoRegsPalette`, `VideoRegsIndexedChannel8` e `VideoRegsDirectChannel8` | Decodificação, registrador de formato, máscara de bytes da cor da paleta, contador de bordas e escritas registradas |
| Testes de entidade `VideoScanout`, `VideoScanoutDirect`, `VideoScanoutPalette`, `VideoScanoutIndexedChannel8` e `VideoScanoutDirectChannel8` | Endereço, escolha do pixel, paleta, latência de dois ciclos até o backend e habilitação |
| Testes de entidade `VideoVga` e `VideoVgaChannel8` | Separação dos canais, apagamento das cores, apagamento do conversor e níveis de repouso do reset nas duas polaridades |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

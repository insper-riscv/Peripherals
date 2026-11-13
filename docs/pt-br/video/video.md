# Vídeo VGA

🌐 [Português](../../pt-br/video/video.md) · [English](../../en/video/video.md)

## 1. Referência

O periférico gera o modo VGA 640x480 a 60 Hz do padrão VESA, com 800 x 525 pixels totais por quadro e sincronismos horizontal e vertical de polaridade negativa. O clock de pixel nominal é 25,175 MHz; com 25 MHz o quadro dura $800 \cdot 525 / 25\,\text{MHz} = 16{,}8\ \text{ms}$, ou 59,52 quadros por segundo, dentro da tolerância dos monitores. A placa DE0-CV liga as saídas a um conversor resistivo de 4 bits por canal (`VGA_R`, `VGA_G` e `VGA_B`), mais os pinos `VGA_HS` e `VGA_VS`.

## 2. O que é

O processador escreve pixels em um framebuffer, e uma varredura independente os lê e os envia ao monitor. O framebuffer fica em uma memória de duas portas com clocks independentes, escrita no clock do sistema e lida no clock de pixel. Cada pixel do framebuffer cobre `scale` x `scale` pixels da tela, e a imagem fica centrada, com faixas pretas no que sobra do quadro de 640x480. O clock de pixel vem de fora do periférico, normalmente de uma PLL do topo da placa.

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `fb_width` | 320 | Largura do framebuffer em pixels; uma linha deve ocupar um número inteiro de palavras de 32 bits |
| `fb_height` | 200 | Altura do framebuffer em pixels |
| `pixel_bits` | 16 | Bits por pixel, 16 para RGB444 ou 8 para índice de uma paleta de 256 cores |
| `scale` | 2 | Fator de ampliação em x e em y; a imagem ampliada deve caber em 640x480 |
| `addr_width` | 16 | Largura do endereço de palavra da janela, no mínimo 11 e maior que o endereço do framebuffer |

Com os valores padrão a imagem ocupa 640x400 e as faixas pretas têm 40 linhas no alto e 40 embaixo.

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_pixel_clk` | entrada | Clock de pixel, assíncrono em relação a `i_clk` |
| `i_data_in`, `i_address` | entrada | Dado de escrita de `XLEN` bits (`word_t`) e endereço de palavra de `addr_width` bits |
| `i_byteena` | entrada | Habilitação de bytes da escrita, um bit por byte |
| `i_write` | entrada | Pulso de escrita do processador |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço |
| `o_vga_r`, `o_vga_g`, `o_vga_b` | saída | Canais de cor de 4 bits cada |
| `o_vga_hs`, `o_vga_vs` | saída | Sincronismos horizontal e vertical, ativos em nível baixo |

A leitura não tem efeito colateral, por isso não há pulso de leitura nem interrupção. O reset do sistema deve durar pelo menos três ciclos de `i_pixel_clk`, porque ele alcança o domínio de pixel por um sincronizador de dois estágios.

## 4. Mapa de endereços

Os acessos são de 32 bits, e os endereços abaixo são de palavra. O bit mais significativo de `i_address` separa a janela do framebuffer do espaço de registradores.

| Endereço de palavra | Conteúdo | Acesso |
| :--- | :--- | :--- |
| 0 | Controle, bit 0 liga a exibição do framebuffer (reset 0) | L/E |
| 1 | Estado, bit 0 vale 1 durante o pulso de sincronismo vertical e bit 1 vale 1 durante o apagamento vertical | L |
| 2 | Contador de quadros, uma unidade a cada início de apagamento vertical, zerado no reset | L |
| 3 | Geometria, largura do framebuffer nos bits 15:0 e altura nos bits 31:16 | L |
| 4 | Formato, bits por pixel nos bits 7:0 e fator de ampliação nos bits 15:8 | L |
| 256 a 511 | Paleta de 256 entradas RGB444, existe só com `pixel_bits` igual a 8 | E |
| `2^(addr_width-1)` em diante | Framebuffer, uma palavra por endereço | E |

Um endereço sem registrador lê zero e ignora a escrita. O framebuffer e a paleta não podem ser lidos. Uma escrita na janela depois da última palavra do framebuffer é descartada.

Com `addr_width` igual a 16 a janela tem 256 KiB e o framebuffer começa no deslocamento `0x20000`. Uma plataforma que reserva uma janela maior que a do periférico liga a ele só os `addr_width` bits baixos do endereço de palavra.

### 4.1. Escrita com máscara de bytes

A escrita no framebuffer grava só os bytes marcados em `i_byteena`, de modo que um acesso `sw` troca dois pixels de 16 bits de uma vez, um `sh` troca um pixel e um `sb` troca um byte. A escrita na paleta exige as duas faixas baixas, ou seja, uma meia palavra ou uma palavra; um acesso de um byte é ignorado. O registrador de controle muda se o byte 0 estiver habilitado. A escrita no framebuffer e na paleta chega à memória um ciclo de clock do sistema depois do pulso de escrita.

## 5. Formato de pixel

Um framebuffer guarda `32 / pixel_bits` pixels por palavra, com o pixel de menor índice nos bits menos significativos, que é a ordem de bytes do processador.

| `pixel_bits` | Pixel | Decodificação |
| :--- | :--- | :--- |
| 16 | Bits 11:8 vermelho, 7:4 verde e 3:0 azul; os bits 15:12 são ignorados | Direta, uma cor RGB444 |
| 8 | Índice de 0 a 255 | A paleta devolve a cor RGB444 de 12 bits, nos bits 11:0 da entrada |

O pixel de índice $n$ do framebuffer, contado por linhas, fica na palavra $\lfloor n \cdot \text{pixel\_bits} / 32 \rfloor$.

## 6. Temporização

### 6.1. Parâmetros do modo

| Direção | Visível | Pórtico frontal | Sincronismo | Pórtico traseiro | Total | Polaridade |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Horizontal, em pixels | 640 | 16 | 96 | 48 | 800 | negativa |
| Vertical, em linhas | 480 | 10 | 2 | 33 | 525 | negativa |

A coluna $h$ e a linha $v$ avançam a cada ciclo de pixel, com $h$ de 0 a 799 e $v$ de 0 a 524. As saídas valem

$$o\_vga\_hs = 0 \iff 656 \le h < 752 \qquad o\_vga\_vs = 0 \iff 490 \le v < 492$$

### 6.2. Diagrama

Uma linha, com o tempo em ciclos de pixel. O pulso de HS dura 96 ciclos.

```
 h        0                    640   656      752       800
          |<--- visível 640 -->|<-16->|<- 96 ->|<- 48 ->|
 o_vga_hs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________/‾‾‾‾‾‾‾
 cor      [  imagem ou preto  ]   preto     preto
```

Um quadro, com o tempo em linhas. O pulso de VS dura 2 linhas, ou 1600 ciclos.

```
 v        0                          480  490 492        525
          |<------ visível 480 ----->|<10>|2|<--- 33 ---->|
 o_vga_vs ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_/‾‾‾‾‾‾‾‾‾‾‾‾
 vblank   ___________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 vsync    ______________________________/‾\___________________
```

### 6.3. Posição da imagem

A imagem ampliada tem $W = \text{fb\_width} \cdot \text{scale}$ colunas e $H = \text{fb\_height} \cdot \text{scale}$ linhas, e começa em

$$x_0 = \frac{640 - W}{2} \qquad y_0 = \frac{480 - H}{2}$$

O pixel da tela $(x, y)$ dentro da imagem mostra o pixel do framebuffer de coluna $\lfloor (x - x_0) / \text{scale} \rfloor$ e linha $\lfloor (y - y_0) / \text{scale} \rfloor$. Fora da imagem as três cores valem zero.

### 6.4. Latência

A memória do framebuffer lê em um ciclo, a escolha do pixel leva um segundo e as saídas são registradas em um terceiro. Os sincronismos atravessam os mesmos três estágios, então cores, HS e VS saem alinhados, três ciclos de pixel depois dos contadores. Os bits de estado vistos pelo processador vêm dos contadores, sem esse atraso.

## 7. Domínios de clock

| Sinal | Origem | Destino | Cruzamento |
| :--- | :--- | :--- | :--- |
| Reset | `i_clk` | `i_pixel_clk` | Sincronizador de dois estágios |
| Exibição habilitada | `i_clk` | `i_pixel_clk` | Sincronizador de dois estágios |
| Sincronismo e apagamento vertical | `i_pixel_clk` | `i_clk` | Dois bits registrados no domínio de pixel e sincronizador de dois estágios |
| Dados do framebuffer e da paleta | `i_clk` | `i_pixel_clk` | Memória de duas portas, uma porta em cada clock |

Os sinais que cruzam por sincronizador são níveis longos, de pelo menos 1600 ciclos de pixel, e nenhum barramento de dados passa por sincronizador. Uma escrita do processador no mesmo endereço que a varredura lê naquele ciclo mostra o dado antigo ou o novo, sem outro efeito. O arquivo de restrições da plataforma deve declarar o caminho que entra no primeiro estágio de cada sincronizador como falso ou com atraso máximo, e o caminho entre as duas portas da memória como falso, pois não há relação de fase entre os clocks.

## 8. Memória

O framebuffer usa uma memória de 32 bits de largura em quatro faixas de byte, uma matriz própria por faixa, para que o Quartus infira blocos M10K com habilitação de bytes. Um bloco M10K tem 10240 bits.

$$\text{palavras} = \frac{\text{fb\_width} \cdot \text{fb\_height} \cdot \text{pixel\_bits}}{32} \qquad \text{blocos por faixa} = \left\lceil \frac{\text{palavras}}{1024} \right\rceil$$

| Configuração | Palavras | Blocos M10K | Bits úteis |
| :--- | :--- | :--- | :--- |
| 320x200, `pixel_bits` 16 | 32000 | 128 no máximo, 96 se o Quartus remover os 4 bits altos de cada pixel que a varredura nunca lê | 1 024 000 |
| 320x200, `pixel_bits` 8 | 16000 | 64 mais 1 da paleta | 512 000 |

A DE0-CV tem 308 blocos M10K. A paleta de 256 entradas de 12 bits cabe em um bloco.

## 9. Uso pelo software

1. Escrever o pixel $n$ no framebuffer pela janela, em palavras de 32 bits com a máscara de bytes desejada.
2. Escrever 1 no registrador de controle para exibir o framebuffer.
3. Para trocar o conteúdo sem rasgar a imagem, ler o contador de quadros, esperar que ele mude (início do apagamento vertical) e então escrever; o apagamento dura 45 linhas, ou cerca de 1,4 ms.

## 10. Verificação

| Verificação | Cobertura |
| :--- | :--- |
| Testes de entidade `Video`, `VideoSmall`, `VideoScale3` e `VideoPalette` | Reset e registradores, contagem exata de ciclos de HS e VS, a área visível e as faixas pretas pixel a pixel contra um modelo, a duplicação em x e em y, a escrita aleatória com máscara de bytes e fora da janela útil, a paleta, o bit de sincronismo vertical, o contador de quadros e o cruzamento de clocks em três razões entre os clocks |
| Testes de entidade `VideoTiming`, `VideoTimingScale3` e `VideoTimingFull` | Contadores, sincronismos, retângulo da imagem e coordenadas do framebuffer, inclusive com a imagem de 640x480 sem faixas |
| Testes de entidade `VideoDpram` e `VideoDpramNarrow` | Escrita por faixa, leitura registrada e razões entre os clocks |
| Testes de entidade `VideoRegs` e `VideoRegsPalette` | Decodificação, máscara de bytes, contador de bordas e escritas registradas |
| Testes de entidade `VideoScanout` e `VideoScanoutPalette` | Endereço, escolha do pixel, paleta, latência de três ciclos e habilitação |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

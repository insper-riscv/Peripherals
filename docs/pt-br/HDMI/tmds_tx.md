# Transmissor TMDS direto para o conector HDMI

🌐 [Português](../../pt-br/HDMI/tmds_tx.md) · [English](../../en/HDMI/tmds_tx.md)

## 1. O que é

Transmissor TMDS (`tmds_tx`) para uma placa cujo conector HDMI é ligado direto aos pinos da FPGA, sem chip transmissor externo. Ele recebe vídeo digital paralelo RGB de 24 bits com DE, HS e VS, o mesmo barramento que o `hdmi_tx` entrega ao ADV7513, e gera os três canais de dados e o canal de clock da codificação TMDS do DVI 1.0. O sinal não leva ilhas de dados, áudio nem InfoFrames, e os monitores o aceitam como vídeo HDMI. É uma entidade distinta do `hdmi_tx`, que fala com o ADV7513 por um barramento paralelo e I2C.

| Entidade | Papel |
| :--- | :--- |
| `tmds_tx` | Topo estrutural, que liga codificadores, serializadores e o registrador DDR de saída |
| `tmds_encoder` | Codificador de um canal, de 8 bits para 10 bits, com a disparidade acumulada |
| `tmds_serializer` | Serializador de um canal, de 10 bits para dois bits por ciclo do clock rápido |
| `tmds_ddr_out` | Registrador DDR de saída, com um modelo de simulação e o invólucro do `altddio_out` da Intel |
| `tmds_consts` | Largura do símbolo, símbolos de controle, símbolo do canal de clock e a contagem de bits em 1 |

## 2. Placas

O datasheet da MKR Vidor 4000 (seção 1.2) lista a FPGA Cyclone 10 CL016 e a saída de vídeo Micro HDMI, e não traz a tabela de pinos nem o padrão elétrico do conector. Os nomes `oHDMI_TX[2:0]` e `oHDMI_CLK` das saídas dessa placa vêm do projeto de referência dela, e a correspondência com `o_data` e `o_clk` é a da tabela abaixo.

| Porta | Canal TMDS | Nome na Vidor |
| :--- | :--- | :--- |
| `o_data(0)` | Canal 0, azul, com HS e VS no apagamento | `oHDMI_TX[0]` |
| `o_data(1)` | Canal 1, verde | `oHDMI_TX[1]` |
| `o_data(2)` | Canal 2, vermelho | `oHDMI_TX[2]` |
| `o_clk` | Canal de clock | `oHDMI_CLK` |

As portas são o lado positivo de cada par. O lado negativo vem da atribuição de pino diferencial do Quartus à mesma saída, e o generic `lane_invert` corrige um par ligado ao contrário na placa.

## 3. Interface

### 3.1. Generics

| Generic | Padrão | Descrição |
| :--- | :--- | :--- |
| `lane_invert` | `0000` | Um bit por canal (0 azul, 1 verde, 2 vermelho, 3 clock); 1 inverte o par |
| `device_family` | `"Cyclone 10 LP"` | Família passada ao `altddio_out` na placa; o modelo de simulação a ignora |

### 3.2. Portas

| Porta | Sentido | Descrição |
| :--- | :--- | :--- |
| `i_clk_pixel` | entrada | Clock de pixel do modo |
| `i_clk_x5` | entrada | Clock cinco vezes mais rápido, do mesmo PLL, com fase fixa em relação ao de pixel |
| `i_rst` | entrada | Reset síncrono ao clock de pixel, ativo em 1 |
| `i_rgb` | entrada, 24 bits | Pixel, vermelho em 23:16, verde em 15:8 e azul em 7:0 |
| `i_de`, `i_hsync`, `i_vsync` | entrada | Habilitação de dados e sincronismos, já na polaridade do modo |
| `o_data` | saída, 3 bits | Pares de dados, lado positivo |
| `o_clk` | saída | Par de clock, lado positivo |

O bloco não tem janela de registradores. Ele não guarda estado que o software configure, e a habilitação da exibição é a do controlador de vídeo que alimenta `i_de`, `i_hsync` e `i_vsync`.

## 4. Codificação

O codificador de cada canal faz duas etapas sobre o byte $d$ de entrada. A primeira minimiza as transições e produz nove bits $q_m$, com $N_1(d)$ o número de bits em 1 de $d$.

$$
q_m[0] = d[0], \qquad q_m[i] = q_m[i-1] \oplus d[i] \ \text{(XOR)} \quad \text{ou} \quad q_m[i] = \overline{q_m[i-1] \oplus d[i]} \ \text{(XNOR)}
$$

A cadeia é XNOR e $q_m[8] = 0$ quando $N_1(d) > 4$ ou quando $N_1(d) = 4$ e $d[0] = 0$, e é XOR com $q_m[8] = 1$ nos demais casos. A segunda etapa balanceia o símbolo de 10 bits com a disparidade acumulada $D$, e a diferença $\delta = N_1(q_m[7:0]) - N_0(q_m[7:0])$.

| Condição | Bit 9 | Bits 7:0 | Nova disparidade |
| :--- | :--- | :--- | :--- |
| $D = 0$ ou $\delta = 0$, com $q_m[8] = 1$ | 0 | $q_m[7:0]$ | $D + \delta$ |
| $D = 0$ ou $\delta = 0$, com $q_m[8] = 0$ | 1 | $\overline{q_m[7:0]}$ | $D - \delta$ |
| $D$ e $\delta$ de mesmo sinal | 1 | $\overline{q_m[7:0]}$ | $D - \delta + 2 q_m[8]$ |
| Demais casos | 0 | $q_m[7:0]$ | $D + \delta - 2 \overline{q_m[8]}$ |

O bit 8 do símbolo é $q_m[8]$. Fora da área visível ($DE = 0$) o símbolo é um dos quatro de controle, escolhido por $C_1 C_0$, e $D$ volta a zero. O canal azul leva $C_0 = HS$ e $C_1 = VS$, e os canais verde e vermelho levam zero.

| $C_1 C_0$ | Símbolo (bit 9 primeiro) |
| :--- | :--- |
| 00 | `1101010100` |
| 01 | `0010101011` |
| 10 | `0101010100` |
| 11 | `1010101011` |

## 5. Serialização e clocks

O símbolo sai do bit 0 ao bit 9. O serializador entrega dois bits por ciclo de `i_clk_x5`, um para cada metade do ciclo, de modo que cada canal transmite $10$ bits por período de pixel e a taxa de cada par vale dez vezes o clock de pixel. O canal de clock transmite o símbolo constante `1111100000` (cinco bits em 0 e depois cinco em 1), um período do clock de pixel.

$$
f_{x5} = 5 \cdot f_{pixel}, \qquad f_{bit} = 10 \cdot f_{pixel}
$$

| Modo | $f_{pixel}$ | $f_{x5}$ |
| :--- | ---: | ---: |
| 480p60 | 27 MHz | 135 MHz |
| 720p60 | 74,25 MHz | 371,25 MHz |

O símbolo muda a cada borda do clock de pixel e atravessa para o domínio rápido por um registrador de retenção e por um bit de alternância sincronizado em dois estágios, que carrega o registrador de deslocamento. Os dois clocks têm de sair do mesmo PLL, e a restrição de tempo do caminho do registrador de retenção para o de deslocamento é um multiciclo de cinco ciclos do clock rápido.

## 6. Integração

O `tmds_tx` aceita direto as saídas `o_tx_d`, `o_tx_de`, `o_tx_hs` e `o_tx_vs` do `hdmi_tx`, sem o sequenciador de inicialização do ADV7513. Uma plataforma de placa inclui exatamente um entre `src/HDMI/tmds/sim/tmds_ddr_out.vhd` (simulação) e `src/HDMI/tmds/altera/tmds_ddr_out.vhd` (placa), duas descrições da mesma entidade. O registrador da placa usa o megafunction `altddio_out`, que o Quartus exige na biblioteca `altera_mf`.

## 7. Verificação

O teste do codificador compara os 256 bytes em sequência e um fluxo aleatório com apagamentos contra um modelo de referência escrito à parte e confere que cada símbolo decodificado devolve o byte, com a disparidade acumulada limitada. O teste do serializador confere que cada símbolo sai inteiro, do bit 0 ao 9, na ordem de entrada, e o do transmissor recupera os símbolos dos três canais dos pinos, alinhados pelo canal de clock, e os compara com o modelo, incluindo HS e VS no canal azul. A prova formal do codificador verifica que o símbolo decodificado é o byte, que o símbolo de apagamento é o do par $C_1 C_0$, que a disparidade acumulada é a soma dos símbolos enviados e que o seu módulo nunca passa de 8, com mutantes que ela precisa reprovar.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

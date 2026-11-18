# Saída HDMI com TMDS direto pela FPGA

🌐 [Português](../../pt-br/HDMI/hdmi_tmds_tx.md) · [English](../../en/HDMI/hdmi_tmds_tx.md)

## 1. O que é

O `hdmi_tmds_tx` é a saída de vídeo HDMI do processador para uma placa cujo conector é ligado direto aos pinos da FPGA, sem chip transmissor externo, como a MKR Vidor 4000. O processador escreve pixels em um framebuffer, uma varredura independente os lê, e o transmissor TMDS serializa o resultado nos três pares de dados e no par de clock do conector.

O invólucro é estrutural e não tem lógica própria. Ele compõe duas entidades que têm documento próprio.

| Entidade | Papel neste invólucro |
| :--- | :--- |
| `hdmi_tx`, sem o sequenciador do ADV7513 | Registradores do vídeo e do HDMI, paleta, framebuffer de duas portas, temporização e varredura; entrega o vídeo paralelo RGB de 24 bits com DE, HS e VS no clock de pixel |
| `tmds_tx` | Codifica o vídeo em TMDS e serializa os quatro pares com o clock serial |

O mapa de endereços, a temporização por generics, os formatos de pixel e as interrupções são os do `hdmi_tx`, resumidos na seção 4, e as diferenças estão na seção 5.

## 2. Domínios de clock

| Clock | Frequência | Domínio |
| :--- | :--- | :--- |
| `i_clk` | do sistema | Registradores, janelas de escrita e interrupções |
| `i_pixel_clk` | clock de pixel do modo, assíncrono em relação a `i_clk` | Temporização, varredura e codificação TMDS |
| `i_serial_clk` | $5 \times$ `i_pixel_clk`, do mesmo PLL | Serialização dos pares |

Com 720p60 os clocks de pixel e serial são 74,25 MHz e 371,25 MHz, e com 480p60 são 27 MHz e 135 MHz. O reset do sistema atravessa para o domínio de pixel por um sincronizador de dois estágios e deve durar pelo menos três ciclos de `i_pixel_clk`.

## 3. Interface

### 3.1. Generics

Os generics de modo e de framebuffer têm o significado e o padrão do `hdmi_tx`. Não existem `clk_freq`, `init_*`, `i2c_*` nem `int_active_low`, que pertencem ao sequenciador e ao pino de interrupção do ADV7513.

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
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
| `pixel_clock_khz` | 74250 | Clock de pixel do modo em kHz; só informativo, o clock real vem do PLL |
| `lane_invert` | `0000` | Um bit por par, 0 azul, 1 verde, 2 vermelho e 3 clock; 1 inverte o par ligado ao contrário na placa |
| `device_family` | `"Cyclone 10 LP"` | Família passada ao registrador DDR de saída da placa |

### 3.2. Portas

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_pixel_clk` | entrada | Clock de pixel |
| `i_serial_clk` | entrada | Clock serial, cinco vezes o de pixel |
| `i_data_in`, `i_address` | entrada | Dado de escrita de 32 bits e endereço de palavra de `addr_width` bits |
| `i_byteena` | entrada | Habilitação de bytes da escrita, um bit por byte |
| `i_write` | entrada | Pulso de escrita do processador |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço |
| `o_irq` | saída | Interrupção em nível, de fim de quadro ou de conexão do monitor, conforme as máscaras |
| `i_hpd` | entrada | Detecção de conexão do monitor, ativa em 1, assíncrona |
| `o_tmds_d` | saída, 3 bits | Pares de dados, lado positivo: 0 azul, 1 verde, 2 vermelho |
| `o_tmds_clk` | saída | Par de clock, lado positivo |

As saídas são o lado positivo de cada par; o lado negativo vem da atribuição de pino diferencial do Quartus à mesma saída.

## 4. Mapa de endereços

Os acessos são de 32 bits e os endereços são de palavra. O bit mais significativo de `i_address` separa a janela do framebuffer do espaço de registradores. Um endereço sem registrador lê zero e ignora a escrita, e o framebuffer e a paleta não podem ser lidos.

| Endereço de palavra | Conteúdo | Acesso |
| :--- | :--- | :--- |
| 0 | Controle, bit 0 liga a exibição do framebuffer (reset 0) | L/E |
| 1 | Estado do quadro, bit 0 vale 1 durante o pulso de VS e bit 1 durante o apagamento vertical | L |
| 2 | Contador de quadros, uma unidade a cada início de apagamento vertical | L |
| 3 | Geometria, largura nos bits 15:0 e altura nos bits 31:16 | L |
| 4 | Formato, bits por pixel em 7:0, ampliação em 15:8, bits por canal em 23:16 e bit 24 em 1 no formato indexado | L |
| 8 | Modo, `mode_id` em 7:0 e polaridade de HS e de VS nos bits 8 e 9 | L |
| 9 | Estado do HDMI (seção 5) | L |
| 10 | Habilitação das interrupções, bit 0 de fim de quadro e bit 1 de conexão do monitor | L/E |
| 11 | Interrupções pendentes, nos mesmos bits; escrever 1 limpa | L/E1C |
| 14 | Clock de pixel do modo em kHz | L |
| 256 a 511 | Paleta de 256 entradas de 24 bits, só no formato indexado | E |
| `2^(addr_width-1)` em diante | Framebuffer, uma palavra por endereço, com a escrita por byte | E |

## 5. Diferenças em relação ao `hdmi_tx`

| Tópico | Comportamento |
| :--- | :--- |
| Estado do HDMI, palavra 9, bit 0 (`INT`) | Reflete `i_hpd`, 1 com o monitor conectado |
| Interrupção de bit 1 | Sobe na ativação de `i_hpd`, isto é, quando o monitor é conectado |
| Estado do HDMI, palavra 9, bits 4:1 | Valem 0, porque não há sequenciador; o reinício na palavra 12 não tem efeito |
| Canal DDC do conector (SCL e SDA) | Não passa por este bloco; o topo o liga a um mestre I2C de uso geral, que lê a EDID do monitor por software |

## 6. Uso

1. Escrever a paleta (formato indexado) e os pixels na janela do framebuffer.
2. Escrever 1 na palavra 0 para ligar a exibição.
3. Ler a palavra 9 para saber se há monitor conectado, e habilitar a interrupção de bit 1 na palavra 10 para ser avisado da conexão.

## 7. Verificação

| Verificação | O que confere |
| :--- | :--- |
| cocotb `HdmiTmdsTx` | Amostra os quatro pares nas duas bordas do clock serial, decodifica os símbolos de volta em pixels e sincronismos e confere cada pixel de quatro quadros contra o framebuffer e a temporização; confere o estado e a interrupção de conexão |
| Prova formal `hdmitmds_*` | Com os três clocks livres, o bit 0 do estado é o pino `i_hpd` passado pelo sincronizador de dois estágios do sistema e os demais bits da palavra de estado valem 0; com mutantes do pino ligado a 0 e do pino invertido |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

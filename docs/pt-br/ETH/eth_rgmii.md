# MAC Ethernet de 10, 100 e 1000 Mbit/s em RGMII

🌐 [Português](../../pt-br/ETH/eth_rgmii.md) · [English](../../en/ETH/eth_rgmii.md)

## 1. O que é

O mesmo MAC do periférico `eth` (barramento, registradores, buffers, filtro, contadores e MDIO) ligado ao PHY pelo RGMII, o modo de fábrica dos dois Marvell 88E1111 da DE2-115 (jumper JP1 para o ENET0 e JP2 para o ENET1 nas posições 1 e 2; o PHY precisa de um reset por hardware depois de trocar o jumper). Com o RGMII o enlace opera a 10, 100 ou 1000 Mbit/s, e a velocidade vem do PHY por MDIO ou é forçada pelo programa.

A interface de barramento é a do `eth`. A diferença está na camada do PHY e em um registrador a mais, o `SPEED`.

## 2. Estrutura

| Entidade | Função |
| :--- | :--- |
| `eth_rgmii_mac` | Topo estrutural: instancia o `eth` com `gigabit` em verdadeiro e a camada `eth_rgmii` |
| `eth` | O MAC; com `gigabit` os dados têm 8 bits (GMII) e o registrador `SPEED` existe |
| `eth_rgmii` | Converte entre o RGMII do PHY e o GMII do MAC e gera o clock de envio |
| `eth_ddr_in`, `eth_ddr_out` | Registradores DDR dos pinos, folhas finas com dois arquivos de mesmo nome (seção 6) |
| `eth_speed` | Registrador `SPEED` e consulta periódica da velocidade ao PHY |
| `eth_mac_tx`, `eth_mac_rx`, `eth_crc32` | Enviam, recebem e calculam o CRC de um nibble (MII) ou de um byte (GMII) por ciclo |

O mesmo `eth_mac_tx`, `eth_mac_rx` e `eth_crc32` servem ao MII e ao GMII. Com a entrada `i_wide` em `'0'` operam um nibble por ciclo, como antes; com `'1'` operam um byte por ciclo.

## 3. Domínios de clock e velocidade

| Domínio | Clock | Observação |
| :--- | :--- | :--- |
| Sistema | `i_clk` | Barramento, buffer de recepção, MDIO e consulta de velocidade |
| Envio | `i_tx_clk` | 125 MHz livre, gerado por PLL da plataforma; o MAC de envio avança só com `o_tx_ce` |
| Recepção | `i_rgmii_rxc` | RXC do PHY: 125, 25 ou 2,5 MHz conforme a velocidade |

A tabela mostra o que muda com a velocidade.

| Velocidade | Envio | Recepção |
| :--- | :--- | :--- |
| 1000 Mbit/s | Um byte por ciclo de 125 MHz; TXC de 125 MHz; nibble baixo na borda de subida e alto na de descida | Um byte por ciclo de RXC: nibble baixo na subida e alto na descida |
| 100 Mbit/s | Um nibble a cada 5 ciclos (`o_tx_ce`); TXC de 25 MHz com 50 % de ciclo de trabalho; o nibble sai nas duas bordas | Um nibble por ciclo de RXC, o da borda de subida; o da descida é ignorado |
| 10 Mbit/s | Um nibble a cada 50 ciclos; TXC de 2,5 MHz com 50 % | Igual a 100 Mbit/s |

O ciclo de trabalho de 50 % de TXC a 25 e 2,5 MHz sai do registrador DDR de TXC: cada ciclo de 125 MHz coloca um nível na metade alta e outro na baixa, de modo que cinco ciclos formam cinco metades altas e cinco baixas. A sinalização de erro de recepção usa o RX_CTL da borda de descida: $\mathrm{RX\_ER} = \mathrm{RX\_CTL}_{\downarrow} \oplus \mathrm{RX\_CTL}_{\uparrow}$, e o envio leva $\mathrm{TX\_CTL}_{\downarrow} = \mathrm{TX\_EN} \oplus \mathrm{TX\_ER}$, com `TX_ER` sempre em `'0'`.

O MAC só opera em full duplex. O bit de duplex do PHY aparece em `SPEED`, mas o MAC não implementa CSMA/CD.

### 3.1. Atraso do clock

O RGMII exige que o clock chegue ao receptor deslocado de cerca de 2 ns em relação aos dados, e o deslocamento pode ser feito pelo transmissor, pelo receptor ou por trilhas.

| Sentido | O que o projeto faz | Confirmado no manual |
| :--- | :--- | :--- |
| Envio (MAC para PHY) | Se `i_tx_clk_dly` é o clock de 125 MHz deslocado de 90 graus (2 ns) por PLL e `shifted_txc` é verdadeiro, o MAC centra TXC nos dados. Se `i_tx_clk_dly` é `i_tx_clk` e `shifted_txc` é falso, os dados e TXC saem alinhados e o PHY precisa atrasar TXC | Não. O manual não diz se o 88E1111 atrasa TXC nem em que registrador se liga o atraso |
| Recepção (PHY para MAC) | O projeto supõe que RXC chega centrado nos dados, isto é, que o PHY insere o atraso, e as restrições da seção 8 descrevem essa suposição | Não. O manual não descreve o atraso interno do 88E1111 e remete ao datasheet, que não está na pasta Docs |

Se o PHY não inserir o atraso de recepção, o ajuste é feito nas restrições (atraso de entrada) ou por um deslocamento de fase do RXC na plataforma, sem alterar a entidade. A posição do registrador do PHY que liga cada atraso (registrador 20, bits 1 e 7 no datasheet do chip) vem da memória do datasheet e não está confirmada no manual da placa.

## 4. Interface

### 4.1. Generics de `eth_rgmii_mac`

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `clk_freq_hz`, `mdc_freq_hz` | 50 MHz, 2,5 MHz | Como no `eth` |
| `tx_buffer_addr_bits`, `rx_buffer_addr_bits` | 9 | Como no `eth` |
| `rx_fifo_addr_bits` | 11 | A 1000 Mbit/s a fila de recepção recebe um byte por ciclo de 125 MHz e o sistema consome um por ciclo de `i_clk`; com 11 bits (2048 bytes) cabe um quadro máximo mesmo que o sistema não consuma durante o quadro. Com sistema de 125 MHz ou mais, 4 basta |
| `sync_stages`, `reset_cycles` | 2, 64 | Como no `eth` |
| `phy_addr` | 16 | Endereço MDIO do PHY consultado; o manual dá 10000 (16) para o ENET0 e 10001 (17) para o ENET1 |
| `poll_cycles` | 50000 | Ciclos do sistema entre duas consultas de velocidade (1 ms a 50 MHz) |
| `shifted_txc` | verdadeiro | Descreve `i_tx_clk_dly`, seção 3.1 |

### 4.2. Portas de `eth_rgmii_mac`

| Porta | Sentido | Pino da DE2-115 (tabela 4-23 do manual) |
| :--- | :--- | :--- |
| `i_clk`, `i_rst`, `i_write`, `i_read`, `i_address`, `i_data_in`, `o_data_out`, `o_irq` | | Barramento do `eth` |
| `i_tx_clk` | entrada | Clock de 125 MHz da plataforma |
| `i_tx_clk_dly` | entrada | Mesmo clock deslocado de 90 graus, ou `i_tx_clk` |
| `o_rgmii_txc` | saída | `ENETn_GTX_CLK` (ENET0 A17, ENET1 C23) |
| `o_rgmii_txd[3:0]` | saída | `ENETn_TX_DATA[3:0]` |
| `o_rgmii_tx_ctl` | saída | `ENETn_TX_EN` |
| `i_rgmii_rxc` | entrada | `ENETn_RX_CLK` |
| `i_rgmii_rxd[3:0]` | entrada | `ENETn_RX_DATA[3:0]` |
| `i_rgmii_rx_ctl` | entrada | `ENETn_RX_DV` |
| `o_mdc`, `i_mdio`, `o_mdio_out`, `o_mdio_oe` | | `ENETn_MDC`, `ENETn_MDIO` (tristate no topo da plataforma) |
| `i_phy_int_n`, `o_phy_rst_n` | | `ENETn_INT_N`, `ENETn_RST_N` |

Todos os pinos do ENET são de 2,5 V. A correspondência dos sinais do RGMII com os nomes da tabela 4-23 (`TXC` em `GTX_CLK`, `TX_CTL` em `TX_EN`, `RX_CTL` em `RX_DV`) é a multiplexação padrão do 88E1111 e não está escrita no texto do manual; a figura 4-27 do manual, que não está disponível em texto, é a fonte a conferir. Os pinos `ENETn_TX_CLK`, `ENETn_TX_ER`, `ENETn_RX_ER`, `ENETn_RX_COL`, `ENETn_RX_CRS` e `ENETn_LINK100` ficam livres no RGMII. A direção e o uso de `ENETCLK_25` (A14, 3,3 V) não estão no manual.

Pinos do ENET0 e do ENET1 conforme a tabela 4-23:

| Sinal | ENET0 | ENET1 |
| :--- | :--- | :--- |
| `GTX_CLK` (TXC) | A17 | C23 |
| `TX_DATA[0..3]` | C18, D19, A19, B19 | C25, A26, B26, C26 |
| `TX_EN` (TX_CTL) | A18 | B25 |
| `RX_CLK` | A15 | B15 |
| `RX_DATA[0..3]` | C16, D16, D17, C15 | B23, C21, A23, D21 |
| `RX_DV` (RX_CTL) | C17 | A22 |
| `MDC`, `MDIO` | C20, B21 | D23, D25 |
| `INT_N`, `RST_N` | A21, C19 | D24, D22 |

## 5. Registradores

Os registradores do `eth` valem sem mudança. O `SPEED` ocupa a palavra 14 (offset 0x38).

| Bits | Nome | Acesso | Significado |
| :--- | :--- | :--- | :--- |
| 1:0 | `MODE` | leitura e escrita | 0 automático (reset), 1 força 10, 2 força 100, 3 força 1000 Mbit/s |
| 5:4 | `ACTIVE` | leitura | Velocidade em uso: 0 é 10, 1 é 100 e 2 é 1000 Mbit/s |
| 8 | `LINK` | leitura | O PHY informou enlace ativo na última consulta respondida |
| 9 | `FULL_DUPLEX` | leitura | O PHY informou full duplex |
| 10 | `RESOLVED` | leitura | O PHY informou velocidade e duplex resolvidos |

No modo automático, `eth_speed` lê o registrador 17 do PHY a cada `poll_cycles` ciclos e adota os bits 15 e 14 (00 é 10, 01 é 100 e 10 é 1000 Mbit/s) quando o bit 10 (enlace) e o bit 11 (resolvido) valem 1 e o PHY respondeu. Sem enlace a velocidade anterior é mantida; o valor de reset é 1000 Mbit/s. Os campos do registrador 17 vêm do datasheet do 88E1111 e não estão confirmados no manual da placa.

A consulta usa o mestre MDIO do MAC. Enquanto dura (cerca de 26 µs a 2,5 MHz de MDC), `STATUS.MDIO_BUSY` vale 1 e um comando escrito em `MDIO_CMD` é ignorado, como com o mestre ocupado por um comando do programa. Quem usa o MDIO confere a interrupção `MDIO_DONE` e repete o comando se ela não subir. A consulta não gera `MDIO_DONE` nem altera `MDIO_NOACK`.

A velocidade só deve mudar com o MAC parado. O `ACTIVE` chega aos domínios de envio e recepção por sincronizadores.

### 5.1. Exemplo em C

```c
#define SPEED 14u
#define SPEED_MODE_1000 3u

uint32_t speed_in_use(void) {
    return (ETH(SPEED) >> 4) & 3u;      /* 0, 1 ou 2 */
}

void speed_force_1000(void) { ETH(SPEED) = SPEED_MODE_1000; }
void speed_auto(void)       { ETH(SPEED) = 0; }
```

O envio e a recepção de quadros seguem a seção 7 de `eth.md`.

## 6. Primitivas de DDR

| Entidade | Arquivo da simulação | Arquivo da placa |
| :--- | :--- | :--- |
| `eth_ddr_in` | `src/ETH/rgmii/sim/eth_ddr_in.vhd` | `src/ETH/rgmii/altera/eth_ddr_in.vhd` |
| `eth_ddr_out` | `src/ETH/rgmii/sim/eth_ddr_out.vhd` | `src/ETH/rgmii/altera/eth_ddr_out.vhd` |

Os dois arquivos de cada entidade têm o mesmo nome e as mesmas portas, e uma plataforma usa um deles. Os da placa instanciam `altddio_in` e `altddio_out` por `component`, porque o Quartus 25.1 recusa a instanciação direta deles (erro 10481 com `entity altera_mf.altddio_in`); o GHDL da imagem de ferramentas não os analisa. Os da simulação são modelos comportamentais.

| Entidade | Comportamento |
| :--- | :--- |
| `eth_ddr_in` | `o_q_rise` é o dado da borda de subida e `o_q_fall` o da borda de descida seguinte, ambos registrados na subida do ciclo seguinte |
| `eth_ddr_out` | Registra `i_d_rise` e `i_d_fall` na subida e coloca o primeiro no pino na metade alta e o segundo na baixa |

O `altddio_in` entrega o dado da borda de subida um ciclo antes do da descida; o invólucro da placa registra o primeiro uma vez para o par sair alinhado. Os invólucros e os modelos foram comparados, com 190 ciclos de dados aleatórios e zero divergências, contra os modelos de simulação do próprio megafunction da Intel (`altera_mf.vhd`).

## 7. Verificação

### 7.1. Testes cocotb

O CRC dos quadros de teste vem de `zlib.crc32`, independente do VHDL, e o PHY RGMII é um modelo em Python que gera RXC com os dados 2 ns antes de cada borda, amostra TXD e TX_CTL nas duas bordas de TXC e decodifica os quadros.

| Teste | O que cobre |
| :--- | :--- |
| `EthCrc32` | Byte por ciclo e mistura de byte e nibble contra o CRC-32 da biblioteca padrão |
| `EthGmiiTx` | Quadros de 61 a 1514 bytes, preenchimento, intervalo de 12 bytes, habilitação a cada 5 e a cada 50 ciclos |
| `EthGmiiRx` | Quadros de 60 a 1514 bytes, FCS incorreto, `RX_ER`, quadro curto |
| `EthDdrIn`, `EthDdrOut` | Os modelos dos registradores DDR |
| `EthRgmii`, `EthRgmiiInPhase` | A camada: bytes e nibbles nos pinos, período e ciclo de trabalho de TXC, TXC deslocado e em fase, entrada com o nibble da outra borda diferente |
| `EthRgmiiMac`, `EthRgmiiMacInPhase` | O topo a 1000, 100 e 10 Mbit/s nos dois sentidos, erros, velocidade automática pelo registrador 17 de um PHY MDIO, leitura MDIO entre as consultas e um ping simulado (requisição ICMP recebida pelos registradores, resposta enviada e conferida com checksums e FCS) |

O ping simulado não substitui o teste em rede real em uma placa.

### 7.2. Provas formais

| Entidade | Arquivo | Prova | Propriedade |
| :--- | :--- | :--- | :--- |
| `eth_crc32` | `eth_crc32_props.sv` | indução | Com `i_wide` o estado é o espelho do modelo não refletido depois do byte (nibble baixo e depois alto) |
| `eth_speed` | `eth_speed_props.sv` | indução e limitada | O modo é o dado escrito; a velocidade em uso é a aprendida ou a forçada e nunca vale 11; a consulta lê o registrador 17 do PHY configurado, nunca no ciclo de um pedido do programa, e só muda a velocidade aprendida com resposta, enlace e resolvido |
| `eth_async_fifo` | `eth_async_fifo_props.sv` | limitada | `o_full_next` garante que a escrita do ciclo seguinte cabe, o que permite escrever um byte por ciclo |

Cada prova tem um cover e mutantes que precisam fazê-la falhar. As provas rodam por `formal/eth.sh`.

## 8. Síntese e restrições

### 8.1. Resultado de síntese

O topo mínimo (o `eth_rgmii_mac` com os registradores do barramento em pinos virtuais e os clocks de 125 MHz em pinos) foi sintetizado e ajustado no Quartus Prime Lite 25.1 para o EP4CE115F29C7.

| Recurso | Uso |
| :--- | :--- |
| Elementos lógicos | cerca de 1850 de 114480 (2 %) |
| Registradores | cerca de 965 |
| Blocos M9K | 7 |

| Clock | Fmax (modelo lento, 85 C) |
| :--- | :--- |
| 125 MHz de envio | cerca de 147 MHz |
| `i_rgmii_rxc` | cerca de 147 a 152 MHz |
| Sistema (`i_clk`) | cerca de 84 a 94 MHz; o caminho mais longo vai da saída do M9K da fila de recepção ao endereço de gravação do `eth_rx_store` |

Com as restrições da seção 8.2, todas as folgas de setup ficam positivas (a menor, 0,25 a 0,37 ns, no registrador de TXC do clock deslocado), e o hold é positivo nos modelos lentos. No modelo rápido o hold das entradas do RXC ficou 0,11 ns negativo com atraso mínimo de entrada igual a zero, valor conservador que esse plano de restrições usa no lugar do atraso real do PHY. O atributo `M10K` do `eth_dpram` gera aviso no Cyclone IV E, que usa M9K.

### 8.2. Plano de restrições (`.sdc`)

```tcl
create_clock -name clk50     -period 20.000 [get_ports CLOCK_50]
create_clock -name clk125    -period 8.000  [get_ports <i_tx_clk>]
create_clock -name clk125_90 -period 8.000 -waveform {2.000 6.000} [get_ports <i_tx_clk_dly>]
create_clock -name enet0_rxc -period 8.000  [get_ports ENET0_RX_CLK]
create_clock -name enet0_rxc_virt -period 8.000
derive_clock_uncertainty
set_clock_groups -asynchronous -group {clk50} \
    -group {clk125 clk125_90 enet0_txc} -group {enet0_rxc enet0_rxc_virt}
create_generated_clock -name enet0_txc -source [get_ports <i_tx_clk_dly>] \
    -master_clock clk125_90 [get_ports ENET0_GTX_CLK]
set_output_delay -clock enet0_txc -max  1.0 [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_output_delay -clock enet0_txc -min -1.0 [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_output_delay -clock enet0_txc -clock_fall -max  1.0 -add_delay [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_output_delay -clock enet0_txc -clock_fall -min -1.0 -add_delay [get_ports {ENET0_TX_DATA[*] ENET0_TX_EN}]
set_input_delay -clock enet0_rxc_virt -max 2.0 [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock enet0_rxc_virt -min 0.0 [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock enet0_rxc_virt -clock_fall -max 2.0 -add_delay [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
set_input_delay -clock enet0_rxc_virt -clock_fall -min 0.0 -add_delay [get_ports {ENET0_RX_DATA[*] ENET0_RX_DV}]
```

Os clocks de 125 MHz saem de um PLL da plataforma a partir de `CLOCK_50` (PIN_Y2, 3,3 V); no PLL, `clk125_90` é a segunda saída com fase de 2000 ps. O relógio de RXC é declarado a 125 MHz, o pior caso; a 25 e 2,5 MHz as folgas só aumentam. Os valores de atraso (1,0 ns de preparação e retenção na saída, 0 a 2,0 ns na entrada) são placeholders conservadores no formato do RGMII e devem ser trocados pelos do padrão RGMII e do datasheet do 88E1111, que não estão no manual da placa. O MDC e o MDIO ficam fora da análise (caminhos falsos), porque o MDC tem 2,5 MHz.

## 9. Limites

| Limite | Valor |
| :--- | :--- |
| Duplex | Full duplex apenas |
| Velocidade em uso e buffers | Um quadro de recepção por vez e um de envio por vez, como no `eth` |
| Vazão de recepção a 1000 Mbit/s | Depende de `rx_fifo_addr_bits`, seção 4.1; o `eth_rx_store` consome um byte por ciclo do sistema |
| Sinais do 88E1111 fora do manual | Posição dos bits dos registradores 17 e 20, atraso interno e temporização RGMII |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

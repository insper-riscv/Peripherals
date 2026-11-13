# MAC Ethernet de 10/100 Mbit/s em MII

🌐 [Português](../../pt-br/ETH/eth.md) · [English](../../en/ETH/eth.md)

## 1. O que é

Periférico de barramento que liga um PHY Ethernet pelo MII e entrega ao programa quadros inteiros: envia com preâmbulo, SFD, preenchimento e FCS, e recebe conferindo o FCS e filtrando pelo endereço de destino. Cada instância atende um PHY e traz o mestre MDIO que configura esse PHY, de modo que as duas portas Ethernet da DE2-115 (PHYs Marvell 88E1111, ENET0 e ENET1) são duas instâncias independentes do mesmo periférico.

O manual da DE2-115 informa que a placa suporta nos dois PHYs o modo RGMII (padrão de fábrica) e o modo MII, escolhidos por um jumper por PHY (JP1 e JP2). O periférico implementa o modo MII, de 10 e 100 Mbit/s, e o jumper do PHY deve estar na posição MII. O RGMII de 1 Gbit/s não faz parte do periférico, porque exige registradores DDR nos pinos e um caminho de dados de 8 bits a 125 MHz.

## 2. Estrutura

A entidade `eth` é um topo estrutural. A lógica fica em blocos de função única, cada um num único domínio de clock.

| Bloco | Domínio | Função |
| :--- | :--- | :--- |
| `eth_regs` | sistema | Decodifica o barramento e guarda controle, filtro, comprimento do envio, comando do MDIO, contadores e interrupções |
| `eth_mac_tx` | `TX_CLK` do PHY | Gera preâmbulo, SFD, bytes do buffer, preenchimento, FCS e intervalo entre quadros |
| `eth_mac_rx` | `RX_CLK` do PHY | Acha o SFD, monta bytes, confere o FCS e entrega os bytes sem o FCS mais uma palavra final com as flags |
| `eth_async_fifo` | `RX_CLK` e sistema | Fila de 9 bits com ponteiros em código Gray entre o receptor e o sistema |
| `eth_rx_store` | sistema | Consome a fila, filtra pelo destino, grava o quadro no buffer de recepção e emite os eventos de contagem |
| `eth_dpram` | dois clocks | Memória de duas portas dos dois buffers de quadro e da fila |
| `eth_crc32` | cada lado | Registrador de CRC-32 que absorve um nibble por ciclo (uma instância no envio e outra na recepção) |
| `eth_pulse_cdc` | dois clocks | Leva um pulso de um domínio a outro (início do envio e fim do envio) |
| `eth_reset_stretch` | sistema | Alonga o reset para que os domínios lentos do PHY o vejam |
| `eth_mdio` | sistema | Mestre MDIO da cláusula 22 |

O buffer de envio é uma `eth_dpram` escrita no clock do sistema e lida no `TX_CLK`; o buffer de recepção é uma `eth_dpram` escrita e lida no clock do sistema. O programa só escreve no buffer de envio com o transmissor livre, e só lê o buffer de recepção depois de o quadro estar pronto, de modo que nenhum endereço é lido e escrito ao mesmo tempo.

## 3. Interface

### 3.1. Generics

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `clk_freq_hz` | 50000000 | Frequência do clock do sistema, para derivar o MDC |
| `mdc_freq_hz` | 2500000 | Frequência do MDC; o manual da DE2-115 usa 2,5 MHz |
| `tx_buffer_addr_bits` | 9 | O buffer de envio tem $2^n$ palavras (2 KiB com 9) |
| `rx_buffer_addr_bits` | 9 | O buffer de recepção tem $2^n$ palavras (2 KiB com 9) |
| `rx_fifo_addr_bits` | 4 | A fila de recepção tem $2^n$ bytes (no mínimo 2) |
| `sync_stages` | 2 | Estágios dos sincronizadores entre domínios |
| `reset_cycles` | 64 | Ciclos do clock do sistema que o reset dos domínios do PHY dura |

O meio período do MDC vale $\lceil f_{clk} / (2 f_{mdc}) \rceil$ ciclos do sistema.

### 3.2. Portas

| Porta | Sentido | Descrição |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono ativo em `'1'` |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura do barramento |
| `i_address` | entrada | Endereço de palavra, 6 bits |
| `i_data_in`, `o_data_out` | entrada, saída | Dado de escrita e de leitura, `word_t`; os registradores usam os 32 bits baixos |
| `o_irq` | saída | Interrupção em nível, ativa em `'1'` |
| `i_mii_rx_clk` | entrada | `ENETn_RX_CLK` |
| `i_mii_rxd`, `i_mii_rx_dv`, `i_mii_rx_er` | entrada | `ENETn_RX_DATA[3:0]`, `ENETn_RX_DV`, `ENETn_RX_ER` |
| `i_mii_tx_clk` | entrada | `ENETn_TX_CLK` |
| `o_mii_txd`, `o_mii_tx_en`, `o_mii_tx_er` | saída | `ENETn_TX_DATA[3:0]`, `ENETn_TX_EN`, `ENETn_TX_ER` (sempre `'0'`) |
| `o_mdc` | saída | `ENETn_MDC` |
| `i_mdio`, `o_mdio_out`, `o_mdio_oe` | entrada, saída, saída | Pino `ENETn_MDIO`, separado em entrada, saída e habilitação para a camada de tristate do topo da plataforma |
| `i_phy_int_n` | entrada | `ENETn_INT_N`, ativo em `'0'` |
| `o_phy_rst_n` | saída | `ENETn_RST_N`, ativo em `'0'` |

Os pinos `ENETn_GTX_CLK`, `ENETn_RX_COL`, `ENETn_RX_CRS`, `ENETn_LINK100` e `ENETCLK_25` não são usados no MII em full duplex e ficam livres na plataforma.

## 4. Registradores

O endereço é de palavra, com 6 bits, e o bloco ocupa 64 palavras (256 bytes). O deslocamento em bytes é quatro vezes o número da palavra. Endereços não listados leem zero e ignoram a escrita.

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | leitura e escrita | `0x04` | Controle, bits da tabela 4.1 |
| 1 | `STATUS` | leitura | 0 | Estado, bits da tabela 4.2 |
| 2 | `IRQ_STATUS` | leitura; escrever 1 limpa | 0 | Interrupções pendentes, bits da tabela 4.3 |
| 3 | `IRQ_ENABLE` | leitura e escrita | 0 | Habilita cada interrupção de `IRQ_STATUS` |
| 4 | `MAC_LO` | leitura e escrita | 0 | Quatro primeiros octetos do endereço MAC; o primeiro octeto está nos bits 7:0 |
| 5 | `MAC_HI` | leitura e escrita | 0 | Dois últimos octetos nos bits 15:0; o quinto octeto está nos bits 7:0 |
| 6 | `TX_LEN` | leitura e escrita | 0 | Comprimento em bytes do quadro a enviar, sem FCS; ignorado com o envio em andamento |
| 7 | `TX_CMD` | escrita | | Bit 0 inicia o envio; bit 1 volta o ponteiro do buffer de envio a zero |
| 8 | `TX_DATA` | leitura e escrita | 0 | Escrita acrescenta uma palavra ao buffer de envio (primeiro byte nos bits 7:0); a leitura devolve o número de palavras escritas |
| 9 | `RX_LEN` | leitura | 0 | Comprimento em bytes do quadro pronto, sem FCS; zero sem quadro |
| 10 | `RX_DATA` | leitura | | Cada leitura devolve a palavra seguinte do quadro pronto (primeiro byte nos bits 7:0) |
| 11 | `RX_CMD` | escrita | | Bit 0 libera o quadro e abre o buffer a um novo quadro; bit 1 volta o ponteiro de leitura a zero |
| 12 | `MDIO_CMD` | leitura e escrita | 0 | Escrita inicia uma transação MDIO, campos da tabela 4.4 |
| 13 | `MDIO_DATA` | leitura e escrita | 0 | Dado a escrever no PHY; depois de uma leitura, o dado lido |
| 16 | `CNT_TX` | leitura; escrita zera | 0 | Quadros enviados |
| 17 | `CNT_RX` | leitura; escrita zera | 0 | Quadros recebidos e entregues ao buffer |
| 18 | `CNT_CRC` | leitura; escrita zera | 0 | Quadros com FCS incorreto |
| 19 | `CNT_PHY` | leitura; escrita zera | 0 | Quadros com `RX_ER`, número ímpar de nibbles ou menos de 64 bytes |
| 20 | `CNT_DROP` | leitura; escrita zera | 0 | Quadros descartados por buffer ocupado, maior que o buffer, perda na fila ou MAC desabilitado |
| 21 | `CNT_FILTER` | leitura; escrita zera | 0 | Quadros recusados pelo filtro de endereço |

### 4.1. Bits de `CTRL`

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Habilita a recepção de quadros |
| 1 | `PROMISCUOUS` | Aceita qualquer endereço de destino |
| 2 | `BROADCAST` | Aceita o destino `FF:FF:FF:FF:FF:FF` (1 no reset) |
| 3 | `MULTICAST` | Aceita destinos de grupo (bit 0 do primeiro octeto em 1) |
| 4 | `ACCEPT_ERRORS` | Entrega também quadros com erro de FCS, de PHY ou de tamanho |
| 5 | `SOFT_RESET` | Escrever 1 reinicia o MAC e todos os registradores; lê sempre 0 |
| 6 | `PHY_RESET` | Mantém `ENETn_RST_N` em `'0'` enquanto vale 1 |

### 4.2. Bits de `STATUS`

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `TX_BUSY` | Há envio em andamento |
| 1 | `RX_READY` | Há quadro pronto no buffer de recepção |
| 2 | `MDIO_BUSY` | Há transação MDIO em andamento |
| 3 | `PHY_INT` | `ENETn_INT_N` está em `'0'` |
| 4 | `MDIO_NOACK` | Nenhum PHY respondeu à última leitura MDIO |

### 4.3. Bits de `IRQ_STATUS` e `IRQ_ENABLE`

| Bit | Nome | Origem |
| ---: | :--- | :--- |
| 0 | `RX_FRAME` | Quadro recebido e entregue ao buffer |
| 1 | `TX_DONE` | Quadro enviado |
| 2 | `ERROR` | Quadro recebido com erro de FCS, de PHY ou descartado, início de envio recusado ou escrita recusada no buffer de envio |
| 3 | `MDIO_DONE` | Transação MDIO concluída |
| 4 | `PHY` | Nível de `ENETn_INT_N`; segue a linha e não é limpo por escrita |

A saída `o_irq` vale `'1'` quando algum bit de `IRQ_STATUS` coincide com o bit correspondente de `IRQ_ENABLE`.

### 4.4. Campos de `MDIO_CMD`

| Bits | Nome | Significado |
| ---: | :--- | :--- |
| 4:0 | `REG` | Endereço do registrador no PHY |
| 9:5 | `PHY` | Endereço do PHY (16 para o ENET0 e 17 para o ENET1 da DE2-115, conforme o manual) |
| 10 | `WRITE` | 1 escreve `MDIO_DATA` no registrador; 0 lê o registrador para `MDIO_DATA` |

Uma escrita em `MDIO_CMD` com `MDIO_BUSY` em 1 é ignorada.

## 5. Funcionamento

### 5.1. Envio

O programa zera o ponteiro com `TX_CMD`, escreve as palavras do quadro em `TX_DATA`, escreve o comprimento em `TX_LEN` e escreve 1 em `TX_CMD`. O quadro vai do endereço de destino ao último byte de dados, sem FCS. O transmissor envia

1. sete bytes `0x55` de preâmbulo e o SFD `0xD5`;
2. os bytes do quadro, cada byte em dois nibbles, o baixo primeiro;
3. zeros até o quadro somar 60 bytes, quando o comprimento é menor;
4. o FCS, que é o complemento do CRC-32 do endereço de destino até o fim do preenchimento, enviado com o byte menos significativo primeiro;
5. um intervalo de 96 bits com `TX_EN` em 0.

O CRC-32 usa o polinômio $x^{32}+x^{26}+x^{23}+x^{22}+x^{16}+x^{12}+x^{11}+x^{10}+x^8+x^7+x^5+x^4+x^2+x+1$ com valor inicial `0xFFFFFFFF`, e um quadro íntegro com o FCS deixa o registrador em `0xDEBB20E3`. O envio é recusado, e o bit `ERROR` sobe, quando `TX_LEN` vale zero ou quando já há envio em andamento. O ponteiro do buffer volta a zero ao fim de cada envio.

### 5.2. Recepção

O receptor ignora o preâmbulo até o nibble `0xD` do SFD e junta os nibbles em bytes. Os bytes passam por uma linha de atraso de quatro bytes, que retém o FCS, e seguem para a fila. Ao fim do quadro (`RX_DV` volta a 0) uma palavra final leva as flags do quadro.

| Flag | Condição |
| :--- | :--- |
| `CRC` | O CRC-32 do quadro inteiro, FCS incluso, não é o resíduo |
| `PHY` | `RX_ER` esteve em 1 durante o quadro |
| `ALIGN` | O quadro tem um número ímpar de nibbles |
| `RUNT` | O quadro tem menos de 64 bytes com o FCS |
| `OVERFLOW` | A fila encheu e bytes foram perdidos |
| `MISSED` | Um quadro foi ignorado antes deste porque a palavra final anterior ainda esperava lugar na fila |

O lado do sistema compara os seis primeiros bytes com o filtro: aceita o endereço de `MAC_LO` e `MAC_HI`, o endereço de difusão com `BROADCAST`, um endereço de grupo com `MULTICAST` e qualquer endereço com `PROMISCUOUS`. Um quadro aceito, sem flag de erro (ou com `ACCEPT_ERRORS`) e que cabe no buffer fica pronto: `RX_READY` sobe, `RX_LEN` mostra o comprimento e `RX_DATA` entrega as palavras. O buffer guarda um quadro por vez, e o quadro seguinte é descartado e contado em `CNT_DROP` até o programa liberar o quadro com `RX_CMD`.

### 5.3. MDIO

O mestre envia 32 bits de preâmbulo em 1, o início `01`, o código de operação (`01` escrita, `10` leitura), os endereços do PHY e do registrador, a virada de barramento e 16 bits de dado, o bit mais significativo primeiro. Muda `MDIO` na borda de descida de `MDC` e lê o PHY na borda de subida. Na leitura o mestre solta a linha no primeiro bit da virada e o PHY responde `0` no segundo; se esse bit chega em 1, `MDIO_NOACK` sobe e o dado lido vale `0xFFFF`. `MDC` fica em 0 fora das transações. Com 100 MHz de clock e `mdc_freq_hz` de 2,5 MHz, o divisor do meio período é 20, que é o divisor de 40 que o manual indica para o `MDC` de 2,5 MHz.

### 5.4. Domínios de clock e reset

Quatro clocks coexistem: o do sistema, o `RX_CLK` e o `TX_CLK` do PHY (2,5 MHz a 10 Mbit/s e 25 MHz a 100 Mbit/s, cada um gerado pelo PHY) e o `MDC`, que é um sinal derivado do clock do sistema. Os cruzamentos são

| Cruzamento | Mecanismo |
| :--- | :--- |
| Bytes do receptor para o sistema | FIFO assíncrona com ponteiros em código Gray e sincronizadores de dois estágios |
| Início do envio, do sistema para o `TX_CLK` | Pulso convertido em toggle, sincronizado e convertido de volta em pulso |
| Fim do envio, do `TX_CLK` para o sistema | O mesmo mecanismo no sentido contrário |
| Palavras do buffer de envio | Memória de duas portas com clocks independentes; o conteúdo fica parado durante o envio |
| `ENETn_INT_N` | Sincronizador de dois estágios |

O reset do sistema (`i_rst` ou `SOFT_RESET`) é alongado por `reset_cycles` ciclos e sincronizado em cada domínio do PHY. Os dois lados da fila saem do reset juntos.

### 5.5. Interrupções

`o_irq` é um nível. O programa lê `IRQ_STATUS`, trata cada origem pendente e escreve nele os bits tratados.

## 6. Pinos da DE2-115

O nome do pino de cada PHY troca `n` por 0 (ENET0) ou 1 (ENET1). O jumper JP1 (ENET0) ou JP2 (ENET1) fica em MII (pinos 2 e 3), e o PHY precisa de um reset por hardware depois de trocar o jumper.

| Porta | Pino da placa | Tipo de E/S |
| :--- | :--- | :--- |
| `i_mii_rx_clk` | `ENETn_RX_CLK` | 2,5 V |
| `i_mii_rxd` | `ENETn_RX_DATA[3:0]` | 2,5 V |
| `i_mii_rx_dv` | `ENETn_RX_DV` | 2,5 V |
| `i_mii_rx_er` | `ENETn_RX_ER` | 2,5 V |
| `i_mii_tx_clk` | `ENETn_TX_CLK` | 2,5 V |
| `o_mii_txd` | `ENETn_TX_DATA[3:0]` | 2,5 V |
| `o_mii_tx_en` | `ENETn_TX_EN` | 2,5 V |
| `o_mii_tx_er` | `ENETn_TX_ER` | 2,5 V |
| `o_mdc` | `ENETn_MDC` | 2,5 V |
| `i_mdio`, `o_mdio_out`, `o_mdio_oe` | `ENETn_MDIO` | 2,5 V, via tristate do topo |
| `i_phy_int_n` | `ENETn_INT_N` | 2,5 V |
| `o_phy_rst_n` | `ENETn_RST_N` | 2,5 V |

Os clocks `RX_CLK` e `TX_CLK` entram direto nos registradores do periférico e exigem restrições de clock no `.sdc` da plataforma, com os grupos de clock do sistema, do `RX_CLK` e do `TX_CLK` declarados assíncronos entre si.

## 7. Exemplo de uso em C

```c
#include <stdint.h>

#define ETH_BASE   0x80010000u  /* endereço de base da instância na plataforma */
#define ETH(word)  (*(volatile uint32_t *)(ETH_BASE + 4u * (word)))

enum { CTRL = 0, STATUS = 1, IRQ_STATUS = 2, MAC_LO = 4, MAC_HI = 5,
       TX_LEN = 6, TX_CMD = 7, TX_DATA = 8, RX_LEN = 9, RX_DATA = 10,
       RX_CMD = 11, MDIO_CMD = 12, MDIO_DATA = 13 };

static void mdio_wait(void) { while (ETH(STATUS) & (1u << 2)) { } }

uint16_t phy_read(unsigned phy, unsigned reg) {
    ETH(MDIO_CMD) = (phy << 5) | reg;       /* leitura */
    mdio_wait();
    return (uint16_t)ETH(MDIO_DATA);
}

void eth_init(const uint8_t mac[6]) {
    ETH(MAC_LO) = mac[0] | mac[1] << 8 | mac[2] << 16 | (uint32_t)mac[3] << 24;
    ETH(MAC_HI) = mac[4] | mac[5] << 8;
    ETH(CTRL) = (1u << 0) | (1u << 2);      /* ENABLE e BROADCAST */
}

void eth_send(const uint8_t *frame, unsigned len) {
    while (ETH(STATUS) & 1u) { }            /* espera o envio anterior */
    ETH(TX_CMD) = 2u;                       /* ponteiro a zero */
    for (unsigned i = 0; i < len; i += 4) {
        uint32_t word = 0;
        for (unsigned b = 0; b < 4 && i + b < len; b++)
            word |= (uint32_t)frame[i + b] << (8 * b);
        ETH(TX_DATA) = word;
    }
    ETH(TX_LEN) = len;
    ETH(TX_CMD) = 1u;                       /* inicia */
}

unsigned eth_receive(uint8_t *buf) {
    if (!(ETH(STATUS) & 2u)) return 0;      /* nenhum quadro pronto */
    unsigned len = ETH(RX_LEN);
    for (unsigned i = 0; i < len; i += 4) {
        uint32_t word = ETH(RX_DATA);
        for (unsigned b = 0; b < 4 && i + b < len; b++)
            buf[i + b] = (uint8_t)(word >> (8 * b));
    }
    ETH(RX_CMD) = 1u;                       /* libera o buffer */
    return len;
}
```

## 8. Verificação

### 8.1. Testes de entidade

Cada bloco tem teste cocotb próprio, e o topo é exercitado contra um modelo de PHY no MII e no MDIO, com o CRC dos quadros de teste calculado pela biblioteca padrão do Python, independente do VHDL.

| Teste | O que cobre |
| :--- | :--- |
| `EthTx` | Quadros de 301 e 2048 bytes, preenchimento, intervalo mínimo entre quadros, clock de 10 Mbit/s e início recusado |
| `EthRx` | Tamanhos de 60 a 1514 bytes, filtro por endereço, promíscuo, FCS incorreto, erro de PHY, quadro curto, buffer ocupado e quadros consecutivos |
| `EthMdio` | Escrita, leitura de padrões extremos, PHY ausente e período do MDC |
| `EthRegisters` | Valores de reset, leitura de volta, interrupções, `INT_N`, `RESET_N` e reset por software |
| `EthMacTx`, `EthMacRx`, `EthRegs`, `EthRxStore`, `EthMdioMaster` | Cada bloco isolado |
| `EthCrc32` | Estado do registrador contra o CRC-32 da biblioteca padrão e o resíduo do FCS |
| `EthAsyncFifo` | Ordem e capacidade com razões de clock diferentes nos dois sentidos |
| `EthDpram`, `EthPulseCdc`, `EthResetStretch` | Memória, travessia de pulso e reset alongado |

### 8.2. Provas formais

As provas usam o SymbiYosys sobre a netlist que o GHDL sintetiza do VHDL.

| Entidade | Arquivo | Prova | Propriedade |
| :--- | :--- | :--- | :--- |
| `eth_crc32` | `eth_crc32_props.sv` | indução | O estado é o espelho de um modelo independente do CRC-32 (registrador não refletido, polinômio `0x04C11DB7`); `o_residue_ok` vale exatamente no resíduo; absorver o complemento de qualquer estado leva ao resíduo |
| `eth_async_fifo` | `eth_async_fifo_props.sv` | limitada, 30 passos, clocks livres | A ocupação nunca passa da profundidade nem fica negativa; sem `o_full` ainda há espaço e sem `o_empty` ainda há palavra; os ponteiros são Gray dos binários e mudam um bit por borda |
| `eth_regs` | `eth_regs_props.sv` | indução | Controle, máscara, pendências, endereço MAC, comprimento, ponteiro e estado do transmissor seguem um modelo ideal; a interrupção é pendência e habilitação; o pulso de início exige transmissor livre e comprimento diferente de zero |

Cada prova tem um cover e mutantes que precisam fazê-la falhar. As provas rodam por `formal/eth.sh`, chamado por `formal/run.sh`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

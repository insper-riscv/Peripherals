# usb_bridge

Periférico mapeado em memória que liga o barramento do SoC ao barramento paralelo de 16 bits do chip USB da placa. O chip implementa o USB (host e dispositivo); o periférico só executa os acessos de leitura e escrita nas quatro portas do chip, com temporização configurável, e reflete as interrupções do chip.

## 1. Função do componente no SoC

O programa fala com o chip por acessos de 16 bits a quatro portas, escolhidas por dois bits de endereço do chip. O periférico transforma cada leitura ou escrita do processador numa transação nos pinos, com chip selecionado, endereço, estrobo e dado, e guarda o dado lido para o programa pegar depois. Nenhuma pilha USB faz parte do periférico.

### 1.1. Chips e pinos

| Placa | Chip | Pinos do manual |
| :--- | :--- | :--- |
| DE2-115 (seções 3.5 e 4.17) | Cypress EZ-OTG CY7C67200, interface HPI | `OTG_DATA[15:0]`, `OTG_ADDR[1:0]`, `OTG_CS_N`, `OTG_RD_N`, `OTG_WR_N`, `OTG_RST_N`, `OTG_INT` |

A ponte também serve ao ISP1362 das revisões antigas da DE2, que tem os mesmos pinos de dado, endereço e estrobo, mais as saídas de interrupção do controlador host e do controlador de dispositivo, o pedido de DMA (`OTG_DC_DREQ`) e o reconhecimento de DMA (`OTG_DC_DACK`). Os pinos `OTG_FSPEED`, `OTG_LSPEED` e `OTG_RESET` não fazem parte da ponte.

### 1.2. As quatro portas

| Endereço do chip (`OTG_ADDR[1:0]`) | Porta no ISP1362 | Porta na interface HPI do CY7C67200 |
| ---: | :--- | :--- |
| 0 | Dado do controlador host | Dado (`HPI_DATA`) |
| 1 | Comando do controlador host | Caixa de correio (`HPI_MAILBOX`) |
| 2 | Dado do controlador de dispositivo | Endereço (`HPI_ADDRESS`) |
| 3 | Comando do controlador de dispositivo | Estado (`HPI_STATUS`) |

O endereço do chip é igual ao endereço de palavra da porta no periférico (janelas 0 a 3 do mapa de registradores).

## 2. Registradores

O endereço é o deslocamento em palavras dentro do periférico (quatro bits, janela de 64 bytes).

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `HC_DATA` | escrita pede escrita, leitura pede leitura | leitura devolve 0 | Porta 0 do chip |
| 1 | `HC_CMD` | escrita pede escrita, leitura pede leitura | leitura devolve 0 | Porta 1 do chip |
| 2 | `DC_DATA` | escrita pede escrita, leitura pede leitura | leitura devolve 0 | Porta 2 do chip |
| 3 | `DC_CMD` | escrita pede escrita, leitura pede leitura | leitura devolve 0 | Porta 3 do chip |
| 4 | `RDATA` | leitura | 0 | Dado de 16 bits do último acesso de leitura concluído; a leitura não tem efeito colateral |
| 5 | `CTRL` | leitura e escrita | 1 | Bit 0 `CHIP_RESET` mantém o chip em reset (`OTG_RST_N` em nível baixo); bit 1 `DACK` dirige `OTG_DC_DACK` |
| 6 | `STATUS` | leitura; escrita de 1 no bit 4 limpa o erro | 0 | Bit 0 `INT0`, bit 1 `INT1`, bit 2 `DREQ`, bit 3 `BUSY`, bit 4 `ERROR` |
| 7 | `IRQ_MASK` | leitura e escrita | 0 | Bit 0 habilita `INT0`, bit 1 habilita `INT1` na saída `o_irq` |
| 8 | `TIMING` | leitura e escrita | pelos generics | Bits 7:0 preparação, 15:8 pulso, 23:16 recuperação, em ciclos de clock |

Os bits não listados leem zero e a escrita neles é ignorada. Nas portas, só os 16 bits baixos do dado vão ao chip.

## 3. Comportamento

### 3.1. Acesso ao chip

Escrever numa porta pede uma escrita de 16 bits do dado naquela porta. Ler uma porta pede uma leitura; a própria leitura do processador devolve zero e o dado do chip fica em `RDATA` quando `BUSY` cai. O programa lê uma porta, espera `BUSY` em zero e lê `RDATA`.

Um pedido feito com `BUSY` em um é descartado e liga o bit `ERROR`, que fica ligado até o programa escrever um nele. O acesso em curso não é afetado.

### 3.2. Temporização nos pinos

Cada acesso passa por quatro etapas, e os pinos de saída vêm de registradores.

| Etapa | Duração em ciclos | Pinos |
| :--- | :--- | :--- |
| Preparação | `TIMING[7:0]` | `OTG_CS_N` em 0, endereço e dado estáveis, estrobos em 1 |
| Pulso | `TIMING[15:8]` | `OTG_RD_N` ou `OTG_WR_N` em 0 |
| Retenção | 1 | `OTG_CS_N` em 0, estrobos em 1, dado mantido |
| Recuperação | `TIMING[23:16]` | Todos inativos, antes do acesso seguinte |

Um campo com valor zero dura um ciclo. Os valores de reset de `TIMING` vêm dos generics. A saída de dado só fica habilitada nas escritas, da preparação até a retenção.

O dado de leitura entra por um sincronizador de dois estágios e é amostrado no último ciclo do pulso. Para o dado do chip chegar a tempo, o pulso precisa durar o tempo de acesso do chip, em ciclos, mais três ciclos de clock.

### 3.3. Interrupções e DMA

As entradas de interrupção do chip e o pedido de DMA passam por sincronizadores de dois estágios. `STATUS` mostra o nível de cada interrupção já normalizado para ativo em um (o generic `int_active_high` informa a polaridade do pino). A saída `o_irq` é de nível e vale um enquanto algum `INTn` estiver ativo com o bit correspondente de `IRQ_MASK` em um. O programa limpa a causa no próprio chip. Uma placa com um só pino de interrupção liga o bit 0 e deixa o bit 1 inativo.

### 3.4. Como o software lê o identificador do chip

Com o chip fora do reset (`CTRL` com o bit 0 em zero e o tempo de inicialização do chip cumprido), o programa segue o protocolo do chip. Os códigos de registrador de identificador e os valores esperados estão no datasheet de cada chip.

| Chip | Sequência |
| :--- | :--- |
| ISP1362, controlador host | Escrever o código do registrador de identificador do host em `HC_CMD`, pedir leitura de `HC_DATA`, esperar `BUSY` cair e ler `RDATA` |
| ISP1362, controlador de dispositivo | O mesmo com `DC_CMD` e `DC_DATA` |
| CY7C67200 pela HPI | Escrever o endereço interno em `DC_DATA` (porta 2, `HPI_ADDRESS`), pedir leitura de `HC_DATA` (porta 0, `HPI_DATA`), esperar e ler `RDATA` |

Exemplo em C, com a base do periférico definida pela plataforma:

```c
#include <stdint.h>

#define USB_BASE   0x40000000u
#define USB_REG(n) (*(volatile uint32_t *)(USB_BASE + 4u * (n)))

enum { HC_DATA, HC_CMD, DC_DATA, DC_CMD, RDATA, CTRL, STATUS, IRQ_MASK, TIMING };
#define STATUS_BUSY (1u << 3)

static void usb_wait(void) {
    while (USB_REG(STATUS) & STATUS_BUSY) { }
}

static uint16_t usb_read_reg(unsigned cmd_port, unsigned data_port, uint16_t code) {
    USB_REG(cmd_port) = code;
    usb_wait();
    (void)USB_REG(data_port);
    usb_wait();
    return (uint16_t)USB_REG(RDATA);
}

uint16_t usb_host_chip_id(uint16_t id_code) {
    USB_REG(CTRL) = 0;
    return usb_read_reg(HC_CMD, HC_DATA, id_code);
}
```

## 4. Interface

### 4.1. Generics

| Generic | Tipo | Padrão | Significado |
| :--- | :--- | :--- | :--- |
| `setup_cycles` | `natural` de 0 a 255 | 2 | Valor de reset da preparação |
| `pulse_cycles` | `natural` de 0 a 255 | 6 | Valor de reset do pulso |
| `recovery_cycles` | `natural` de 0 a 255 | 4 | Valor de reset da recuperação |
| `int_active_high` | `boolean` | `true` | As interrupções do chip são ativas em nível alto |

### 4.2. Portas

| Porta | Direção | Largura | Significado |
| :--- | :--- | ---: | :--- |
| `i_clk` | entrada | 1 | Clock do módulo |
| `i_rst` | entrada | 1 | Reset síncrono, ativo em `'1'` |
| `i_data_in` | entrada | `word_t` | Dado de escrita |
| `i_address` | entrada | 4 | Endereço de palavra |
| `i_write` | entrada | 1 | Pulso de escrita |
| `i_read` | entrada | 1 | Pulso de leitura |
| `o_data_out` | saída | `word_t` | Dado de leitura, zero sem `i_read` |
| `o_irq` | saída | 1 | Interrupção de nível |
| `o_otg_cs_n` | saída | 1 | `OTG_CS_N` |
| `o_otg_rd_n` | saída | 1 | `OTG_RD_N` |
| `o_otg_wr_n` | saída | 1 | `OTG_WR_N` |
| `o_otg_rst_n` | saída | 1 | `OTG_RST_N` |
| `o_otg_addr` | saída | 2 | `OTG_ADDR[1:0]` |
| `o_otg_data` | saída | 16 | Dado para `OTG_DATA[15:0]` |
| `o_otg_data_oe` | saída | 1 | Habilita a saída de `OTG_DATA`, para a camada de tristate do topo |
| `i_otg_data` | entrada | 16 | Valor de `OTG_DATA[15:0]` |
| `i_otg_int` | entrada | 2 | Interrupções do chip (`OTG_INT`; no ISP1362 as duas linhas) |
| `i_otg_dreq` | entrada | 1 | `OTG_DC_DREQ` |
| `o_otg_dack` | saída | 1 | `OTG_DC_DACK` |

## 5. Verificação

Os testes de entidade em cocotb usam um modelo do protocolo de acesso (comando seguido de dado, dois controladores) e cobrem reset, leitura e escrita de registrador nos dois controladores, temporização medida nos pinos, descarte com ocupado, interrupções nas duas polaridades e tráfego aleatório. A prova formal está em `formal/usb_bridge_props.sv` (ver [formal](../formal/formal.md)), com cinco mutantes do VHDL.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

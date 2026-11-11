# Camada física PS/2 (`ps2_host`)

## 1. O que é

O `ps2_host` é a camada física do lado do hospedeiro de um canal PS/2. Ele recebe quadros de um teclado ou de um mouse, envia comandos ao dispositivo e entrega ao restante do hardware apenas bytes e pulsos de estado. Cada instância é independente, sem estado compartilhado, e nenhum sinal é global.

## 2. Canais e cabo Y

A DE0-CV tem um conector PS/2 só. Com um dispositivo, ele usa o canal 0. Para teclado e mouse ao mesmo tempo, um cabo Y divide o conector, e o segundo dispositivo usa o canal 1, que o manual da placa reserva para esse fim.

| Canal | Dispositivo | Clock | Dados |
| :--- | :--- | :--- | :--- |
| 0 | Teclado | `PS2_CLK` (D3) | `PS2_DAT` (G2) |
| 1 | Mouse | `PS2_CLK2` (E2) | `PS2_DAT2` (G1) |

Cada canal tem a sua instância de `ps2_host`, e as duas convivem lado a lado.

## 3. Interface

| Porta | Sentido | Significado |
| :--- | :--- | :--- |
| `i_clk`, `i_rst_n` | entrada | Clock do sistema e reset ativo em nível baixo |
| `io_ps2_clk`, `io_ps2_dat` | bidirecional | Linhas open-drain do conector |
| `o_rx_data` (8 bits), `o_rx_valid` | saída | Byte recebido com paridade correta, um pulso de `o_rx_valid` por byte |
| `o_rx_error` | saída | Pulso em erro de paridade, de quadro, de reconhecimento ou de tempo |
| `i_tx_data` (8 bits), `i_tx_valid` | entrada | Comando a enviar ao dispositivo |
| `o_tx_ready` | saída | O transmissor aceita um novo byte |

| Generic | Padrão | Significado |
| :--- | ---: | :--- |
| `filter_cycles` | 8 | Ciclos que um nível das linhas precisa durar para passar no filtro de glitch |
| `inhibit_cycles` | 6000 | Ciclos com o clock em `0` antes de enviar (120 us a 50 MHz, com o mínimo de 100 us) |
| `timeout_cycles` | 1000000 | Ciclos sem borda de clock que abortam um quadro (20 ms a 50 MHz) |

Os padrões supõem um clock de 50 MHz. O reset deve durar pelo menos dois ciclos, para o sincronizador carregar o nível das linhas.

## 4. Entrada das linhas

Cada linha passa por um sincronizador de dois estágios e por um filtro de glitch, que só aceita um novo nível depois de `filter_cycles` ciclos seguidos. Os pinos são open-drain: o módulo só segura uma linha em `0` ou a solta, e o resistor de pull-up da placa leva a linha a `1`.

## 5. Recepção

O dispositivo gera o clock. O quadro tem 11 bits, amostrados a cada borda de descida do clock filtrado.

| Bit | Conteúdo |
| :--- | :--- |
| 0 | Início, sempre `0` |
| 1 a 8 | Dados, do menos para o mais significativo |
| 9 | Paridade ímpar |
| 10 | Parada, sempre `1` |

A paridade ímpar faz o total de bits `1` entre os dados e a paridade ser ímpar. Um quadro correto produz um pulso de `o_rx_valid` de um ciclo com o byte em `o_rx_data`. Um quadro com início, paridade ou parada inválidos produz um pulso de `o_rx_error`, e o módulo volta ao repouso. Um quadro parado por `timeout_cycles` ciclos também produz o pulso de erro e é abandonado.

## 6. Transmissão

Um byte é aceito no ciclo em que `i_tx_valid` e `o_tx_ready` valem `1`. O transmissor espera a linha estar livre e então segue os passos abaixo.

1. Segura o clock em `0` por `inhibit_cycles` ciclos.
2. Segura os dados em `0` (bit de início) e solta o clock.
3. A cada borda de descida do clock gerado pelo dispositivo, coloca na linha de dados um bit do byte (do menos significativo) e depois a paridade ímpar.
4. Solta a linha de dados e espera o dispositivo baixá-la como reconhecimento.

Se o reconhecimento faltar ou o clock parar por `timeout_cycles` ciclos, o módulo libera as linhas e produz um pulso de `o_rx_error`. `o_tx_ready` vale `0` enquanto um quadro chega ou o envio está em andamento.

## 7. Verificação

Os testes de entidade usam um testbench com duas instâncias de `ps2_host`, uma por canal, e exercitam quadros de make, break e estendidos do conjunto 2, erros de paridade, de parada e de início, quadro parado, glitch curto, comandos com e sem reconhecimento, adiamento do comando durante uma recepção e os dois canais ativos ao mesmo tempo sem interferência.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

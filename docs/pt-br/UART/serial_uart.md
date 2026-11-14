# UART serial

## 1. O que é

A UART serial mapeada em memória liga o barramento do núcleo a linhas físicas assíncronas. Duas filas síncronas separam a velocidade dos acessos do processador da duração dos quadros seriais. A fila de transmissão guarda bytes escritos pelo núcleo e a fila de recepção guarda bytes entregues pela camada física. O formato do quadro (paridade e bits de parada) e o controle de fluxo por hardware são opcionais e ficam desligados no reset, de modo que a UART começa como uma UART 8N1 só com RX e TX.

| Item | Valor inicial |
| :--- | :--- |
| Baud rate | 115200 |
| Clock | 50 MHz |
| Formato | 8 bits de dados, sem paridade e 1 bit de parada |
| Controle de fluxo | Ausente (generic `has_flow_control` falso) |
| Profundidade de TX | 16 bytes |
| Profundidade de RX | 16 bytes |
| Acesso mapeado | 1 ciclo, sem espera do barramento |

As profundidades de TX e RX são parâmetros independentes entre 1 e 255. Os parâmetros do gerador de baud permitem usar outro clock sem alterar a lógica das filas. A largura do barramento de dados é de pelo menos 32 bits.

## 2. Fluxo dos bytes

Uma escrita em `TX_DATA` adiciona o byte à cauda de TX. Quando o transmissor físico está livre, ele remove automaticamente o byte mais antigo e inicia um quadro. O processador pode continuar escrevendo enquanto houver espaço.

Cada quadro recebido adiciona um byte à cauda de RX. Uma leitura de `RX_DATA` devolve o byte mais antigo e o remove na borda que termina o acesso. Uma chegada simultânea a essa leitura reutiliza a posição liberada e não gera erro.

## 3. Registradores

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `TX_DATA` | Zero | Enfileira os bits 7:0 em TX |
| 1 | `RX_DATA` | Bits 7:0 do byte mais antigo e remoção ao final do acesso | Ignorada |
| 2 | `STATUS` | Estado, erros e níveis descritos abaixo | Um em um bit de erro o limpa |
| 3 | `CONTROL` | Habilitações, formato do quadro e fluxo, descritos abaixo | Grava todos os campos |

| Bits de `STATUS` | Nome | Significado |
| :--- | :--- | :--- |
| 0 | `RX_VALID` | Há pelo menos um byte na fila de recepção |
| 1 | `TX_READY` | Há pelo menos uma posição livre na fila de transmissão |
| 2 | `RX_OVERRUN` | Um byte recebido foi descartado porque RX estava cheia |
| 3 | `TX_DROPPED` | Uma escrita foi descartada porque TX estava cheia |
| 4 | `RX_FULL` | A fila de recepção está cheia |
| 5 | `TX_EMPTY` | Nenhum byte espera na fila de transmissão |
| 6 | `TX_IDLE` | TX está vazia e o transmissor físico terminou o último quadro |
| 7 | `FRAME_ERROR` | O bit de parada de um quadro recebido veio em zero |
| 15:8 | `RX_LEVEL` | Quantidade de bytes na fila de recepção |
| 23:16 | `TX_LEVEL` | Quantidade de bytes na fila de transmissão |
| 24 | `PARITY_ERROR` | O bit de paridade de um quadro recebido não confere com o byte |
| 25 | `CTS_ACTIVE` | Só leitura. A linha `i_uart_cts` está ativa (só com `has_flow_control`, senão zero) |
| 26 | `RTS_ACTIVE` | Só leitura. A linha `o_uart_rts` está ativa (só com `has_flow_control`, senão zero) |

| Bits de `CONTROL` | Nome | Significado |
| :--- | :--- | :--- |
| 0 | `RX_IRQ_ENABLE` | Interrupção por byte recebido |
| 1 | `TX_EMPTY_IRQ_ENABLE` | Interrupção por fila de transmissão vazia |
| 2 | `ERROR_IRQ_ENABLE` | Interrupção por `RX_OVERRUN` ou `TX_DROPPED` |
| 3 | `PARITY_ENABLE` | Acrescenta o bit de paridade depois dos dados, na transmissão e na recepção |
| 4 | `PARITY_ODD` | Paridade ímpar quando um, par quando zero (vale com `PARITY_ENABLE`) |
| 5 | `STOP_BITS_2` | Dois bits de parada na transmissão |
| 6 | `LINE_ERROR_IRQ_ENABLE` | Interrupção por `FRAME_ERROR` ou `PARITY_ERROR` |
| 7 | `FLOW_ENABLE` | Liga o controle de fluxo (só com `has_flow_control`, senão zero) |
| 15:8 | `RTS_THRESHOLD` | Limiar de RTS em bytes (só com `has_flow_control`, senão zero) |

`TX_READY` permite continuar produzindo bytes sem esperar o término do quadro atual. Um software que precisa garantir que o último bit chegou ao pino espera `TX_IDLE`.

## 4. Formato do quadro

O quadro padrão tem um bit de início, oito bits de dados do menos para o mais significativo e um bit de parada. Os campos de `CONTROL` alteram o formato nos dois sentidos.

| `PARITY_ENABLE` | `STOP_BITS_2` | Bits do quadro | Formato |
| :--- | :--- | ---: | :--- |
| 0 | 0 | 10 | 8N1 |
| 1 | 0 | 11 | 8E1 ou 8O1, conforme `PARITY_ODD` |
| 0 | 1 | 11 | 8N2 |
| 1 | 1 | 12 | 8E2 ou 8O2 |

A paridade par torna par o número de uns entre os dados e o bit de paridade, e a ímpar o torna ímpar. O receptor confere a paridade e o primeiro bit de parada, e amostra no meio de cada bit. Um segundo bit de parada só existe na transmissão, e o receptor o trata como a linha em repouso. O formato só deve mudar com a linha ociosa e com TX e RX vazias, porque um quadro em andamento usa o formato que valia no seu início.

Um byte recebido com erro entra na fila como qualquer outro. O erro fica nas flags `FRAME_ERROR` e `PARITY_ERROR`, que o software lê em `STATUS`, e não nasce junto do byte, porque o receptor só conhece o bit de paridade e o bit de parada depois de entregar o byte. Uma linha mantida em zero por mais que um quadro (condição de break) produz quadros de zeros com `FRAME_ERROR` repetido.

## 5. Erros e interrupção

`RX_OVERRUN`, `TX_DROPPED`, `FRAME_ERROR` e `PARITY_ERROR` são persistentes. Uma escrita de um em seu próprio bit de `STATUS` os limpa, e uma escrita de zero os preserva. Um novo erro no mesmo ciclo de uma limpeza tem prioridade e mantém o bit ativo.

Quando RX está cheia, o byte novo é descartado e todos os bytes antigos permanecem em ordem. Quando TX está cheia, a escrita nova é descartada sem alterar os bytes que já esperam.

A saída `o_irq` é de nível e vale a soma de quatro causas, cada uma com a sua habilitação, todas zeradas no reset.

| Causa | Condição | Deixa de valer quando |
| :--- | :--- | :--- |
| Recepção (`RX_IRQ_ENABLE`) | RX não está vazia | O software remove o último byte |
| Transmissor vazio (`TX_EMPTY_IRQ_ENABLE`) | TX está vazia | O software escreve em `TX_DATA` |
| Erro de fila (`ERROR_IRQ_ENABLE`) | `RX_OVERRUN` ou `TX_DROPPED` ativo | O software limpa o bit em `STATUS` |
| Erro de linha (`LINE_ERROR_IRQ_ENABLE`) | `FRAME_ERROR` ou `PARITY_ERROR` ativo | O software limpa o bit em `STATUS` |

Com TX vazia a causa de transmissor vazio vale logo ao ser habilitada, então o software a habilita só quando tem bytes a enviar e a desabilita ao terminar.

## 6. Controle de fluxo por hardware

Com o generic `has_flow_control` verdadeiro a UART tem duas linhas a mais, `i_uart_cts` (entrada) e `o_uart_rts` (saída). Com o generic falso a entrada é ignorada, a saída fica ativa e os campos `FLOW_ENABLE`, `RTS_THRESHOLD`, `CTS_ACTIVE` e `RTS_ACTIVE` não existem (leem zero e a escrita é ignorada). Nos dois casos o controle só age depois que o software liga `FLOW_ENABLE`, que vale zero no reset.

As duas linhas são de nível baixo ativo, a convenção dos sinais `RTS#` e `CTS#` no lado TTL de um transceptor RS-232. O manual da DE2-115 (seção 4.12) nomeia os pinos `UART_CTS` e `UART_RTS`, mas não diz a polaridade, que então não está confirmada no manual da placa. Um adaptador que use a polaridade oposta pede uma inversão no topo.

| Regra | Efeito |
| :--- | :--- |
| `i_uart_cts` inativo (alto) | O transmissor não inicia um novo quadro. O quadro em curso termina e os bytes esperam na fila de TX |
| `i_uart_cts` ativo (baixo) | Os bytes da fila saem em ordem |
| RX com `RTS_THRESHOLD` bytes ou mais | `o_uart_rts` fica inativo (alto) |
| RX com menos de `RTS_THRESHOLD` bytes | `o_uart_rts` fica ativo (baixo) |

`o_uart_rts` sai de um registrador e acompanha o nível da fila de recepção com um ciclo de atraso. `i_uart_cts` passa por dois registradores antes de valer, porque vem de fora do domínio de clock. O limiar vale `RTS_THRESHOLD` em bytes e, no reset, a metade da fila de recepção (no mínimo 1). Um limiar zero mantém `o_uart_rts` sempre inativo.

O outro lado pode terminar um quadro que já tinha começado quando `o_uart_rts` ficou inativo, e a recepção continua até o fim desse quadro. O limiar tem então de deixar pelo menos um byte de folga na fila, o que vale para qualquer limiar abaixo da profundidade da fila de recepção.

Na DE2-115 as linhas ligam o FPGA ao transceptor ZT3232 e ao conector DB9, nos pinos da tabela 4-18 do manual.

| Sinal | Pino do FPGA | Direção |
| :--- | :--- | :--- |
| `UART_RXD` | `PIN_G12` | Entrada |
| `UART_TXD` | `PIN_G9` | Saída |
| `UART_CTS` | `PIN_G14` | Entrada |
| `UART_RTS` | `PIN_J13` | Saída |

O cabo entre o conector DB9 e o computador pode ser direto ou cruzado, e o manual não diz qual par de pinos do conector cada sinal usa. O teste na placa com um terminal real confirma a ligação, e o terminal tem de ter o controle de fluxo por hardware (RTS e CTS) ligado.

## 7. UART nos cabeçalhos de expansão

A UART do periférico tem só RX e TX (e, com o generic, RTS e CTS). Nas placas sem transceptor RS-232 o topo estrutural liga a esses sinais pinos de um cabeçalho de expansão, sem mudar a entidade. Os pinos são de 3,3 V LVTTL e nunca se liga um conector RS-232 neles. Quem usa a UART fora da placa liga um adaptador USB-serial de 3,3 V (ou um transceptor de nível), com a regra de cruzar TX e RX, e liga também o terra.

| Placa | Cabeçalho | `o_uart_tx` | `i_uart_rx` | `o_uart_rts` | `i_uart_cts` | Fonte no manual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| DE0-CV | `GPIO_0` | `GPIO_0[0]` (N16) | `GPIO_0[1]` (B16) | `GPIO_0[7]` (K22) | `GPIO_0[8]` (M20) | Tabela 3-7 |
| DE0-Nano | `GPIO_0` | `GPIO_0[0]` (D3) | `GPIO_0[1]` (C3) | `GPIO_0[2]` (A2) | `GPIO_0[3]` (A3) | Seção 3.5, tabela 3-6 |
| DE10-Lite | Arduino | `ARDUINO_IO[1]` (AB6) | `ARDUINO_IO[0]` (AB5) | `ARDUINO_IO[2]` (AB7) | `ARDUINO_IO[3]` (AB8) | Seção 3.6, tabela 3-8 |
| DE0-Nano-SoC | Arduino | `ARDUINO_IO[1]` (AF13) | `ARDUINO_IO[0]` (AG13) | `ARDUINO_IO[2]` (AG10) | `ARDUINO_IO[3]` (AG9) | Seção 3.6.3, tabela 3-11 |
| DE10-Nano | Arduino | `ARDUINO_IO[1]` (AF13) | `ARDUINO_IO[0]` (AG13) | `ARDUINO_IO[2]` (AG10) | `ARDUINO_IO[3]` (AG9) | Seção 3.6.3, tabela 3-11 |

Nos cabeçalhos Arduino das quatro últimas placas o manual rotula `Arduino_IO0` como `RXD` e `Arduino_IO1` como `TXD`, e deixa `Arduino_IO2` e `Arduino_IO3` sem função, o que é a razão da escolha da tabela. Nas duas placas com cabeçalho `GPIO_0` a escolha de RX e TX nos dois primeiros pinos e de RTS e CTS em pinos livres é do projeto, não do manual. Na DE0-CV os pinos `GPIO_0[2]`, `GPIO_0[3]`, `GPIO_0[4]` e `GPIO_0[6]` ficam reservados a um chip externo de FLASH no catálogo da placa e não servem à UART. A DE2-115 tem a UART nos pinos da seção 6 e não precisa deste mapa.

O topo declara os quatro sinais como portas e os liga à UART por associação por nome, sem lógica própria.

```vhdl
u_uart : entity work.uart
    generic map (
        has_flow_control => true
    )
    port map (
        i_clk      => i_clk,
        i_rst      => i_rst,
        i_data_in  => bus_wdata,
        i_address  => bus_address,
        i_write    => bus_write,
        i_read     => bus_read,
        o_data_out => bus_rdata,
        o_irq      => uart_irq,
        i_uart_rx  => uart_rxd,
        o_uart_tx  => uart_txd,
        i_uart_cts => uart_cts,
        o_uart_rts => uart_rts
    );
```

Os sinais `uart_rxd`, `uart_txd`, `uart_cts` e `uart_rts` são as portas do topo ligadas aos pinos da tabela, e os mesmos pinos não entram em nenhum grupo de GPIO do SoC. Sem controle de fluxo o topo omite o generic e as duas portas.

O console da plataforma usa a UART pelo backend `pinos`, que repassa `has_flow_control`, `i_cts` e `o_rts` (veja `console.md`).

## 8. Interface para a integração

| Item | Valor |
| :--- | :--- |
| Entidade | `uart` |
| Generics | `data_width` (mínimo 32), `baud_freq`, `baud_limit`, `rx_fifo_depth`, `tx_fifo_depth`, `has_flow_control` (falso por padrão) |
| Portas de barramento | `i_clk`, `i_rst`, `i_data_in`, `i_address` (2 bits), `i_write`, `i_read`, `o_data_out`, `o_irq` |
| Portas de linha | `i_uart_rx`, `o_uart_tx`, `i_uart_cts` (valor padrão `'0'`, ativa), `o_uart_rts` |
| Registradores | `TX_DATA` 0, `RX_DATA` 1, `STATUS` 2, `CONTROL` 3 |

## 9. Exemplo em C

O arquivo `src/UART/serial/example/uart_flow.c` configura 8E1 com controle de fluxo e limiar de 8 bytes, envia uma linha e ecoa os bytes recebidos, contando os erros de quadro e de paridade. O endereço base da UART vem da plataforma e entra na compilação com `-DUART_BASE`, e o arquivo segue o C23 do repositório.

## 10. Verificação

Os testes de entidade exercitam reset, ordem, enchimento, esvaziamento, volta dos ponteiros, inserção e remoção simultâneas, níveis, interrupção, erros persistentes, quadros 8N1 e a temporização padrão de 115200 baud em 50 MHz.

| Teste | Arquivo | O que mostra |
| :--- | :--- | :--- |
| `UARTFormat` | `tests/python/unittests/UART/uart_format.py` | Quadros de transmissão com paridade par e ímpar e um ou dois bits de parada, volta (loopback) em todos os formatos, `PARITY_ERROR` e `FRAME_ERROR` persistentes que mantêm o byte, e a interrupção de erro de linha com a sua habilitação própria |
| `UARTFlow` | `tests/python/unittests/UART/uart_flow.py` | Registradores de fluxo, nenhum quadro com CTS inativo, quadro em curso que termina, RTS que acompanha o nível e o limiar do registrador, um terminal modelado que respeita o RTS sem perder byte, o mesmo terminal sem fluxo que perde, e a UART em loopback com RTS ligado ao seu CTS |

A prova formal usa `formal/uart_props.sv` para o formato do quadro (início, dados, paridade e parada na transmissão, e os erros de linha na recepção) e `formal/uart_flow_props.sv` para o controle de fluxo. Nenhum byte sai da fila de transmissão para o transmissor com o fluxo ligado e CTS inativo, e `o_uart_rts` é o registro de "fluxo ligado e nível de RX maior ou igual ao limiar". Com o fluxo desligado, CTS é ignorado e RTS fica ativo. As provas, os mutantes e os motores estão em `docs/pt-br/formal/formal.md`.

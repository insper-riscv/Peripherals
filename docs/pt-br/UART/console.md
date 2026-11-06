# Console

## 1. O que é

O console é a interface única de entrada e saída de texto do SoC. O software e o interconector enxergam um só periférico, e um generic escolhe qual dos dois blocos existentes o atende. O VHDL é `src/UART/console/console.vhd`.

| Backend | Bloco atrás da interface | Outra ponta | Quando usar |
| :--- | :--- | :--- | :--- |
| `jtag` (padrão) | [`jtag_uart`](jtag_uart.md) | Hospedeiro na cadeia JTAG, por um nó de Virtual JTAG | Toda placa com cadeia JTAG alcançável pelo Quartus, inclusive as que não têm UART (DE0-CV, DE0-Nano, DE10-Lite) |
| `pinos` | [`uart`](serial_uart.md) | Pinos `o_tx` e `i_rx` da placa | Placas com UART ou com adaptador em GPIO |

O console não tem lógica própria. Ele só escolhe a instância de acordo com o generic `backend` e aplica a polaridade dos pinos do backend `pinos`. Um valor de `backend` diferente de `jtag` e `pinos` interrompe a elaboração com erro.

## 2. Portas e generics

| Grupo | Portas | Backend |
| :--- | :--- | :--- |
| Barramento do periférico | `i_clk`, `i_rst`, `i_addr` (8 bits), `i_wdata`, `i_we`, `i_re`, `o_rdata`, `o_irq` | Os dois |
| Pinos | `i_rx` (padrão `'1'`), `o_tx` | `pinos`; no `jtag`, `o_tx` fica em repouso e `i_rx` é ignorada |
| Nó de Virtual JTAG | `i_tck`, `i_tdi`, `o_tdo`, `i_ir_in`, `i_state_cdr`, `i_state_sdr`, `i_state_udr`, `i_state_uir` | `jtag`; no `pinos`, `o_tdo` fica em zero e as entradas são ignoradas |

| Generic | Padrão | Efeito |
| :--- | :--- | :--- |
| `backend` | `"jtag"` | Escolhe o bloco |
| `baud_freq`, `baud_limit` | `16#240#`, `16#3AC9#` | Gerador de baud do `uart` |
| `rx_fifo_depth`, `tx_fifo_depth` | 16 | Filas do `uart` |
| `log2_depth` | 6 | Filas do `jtag_uart`, 64 bytes cada |
| `tx_invert`, `rx_invert` | `false` | Inverte o pino de transmissão ou de recepção do backend `pinos` |

A inversão existe para a polaridade resolvida pelo papel de E/S da placa (por exemplo um adaptador RS-232 sem conversor de nível que inverta o sinal). O periférico em si trabalha sempre com a linha em repouso em nível alto.

## 3. Contrato de software

Os dois backends respondem ao mesmo barramento e têm em comum a forma das palavras abaixo. O restante do mapa é do backend e está no documento do bloco.

| Palavra | Nome | Comum aos dois backends |
| ---: | :--- | :--- |
| 0 | TXDATA | A escrita dos bits 7:0 enfileira um byte para transmissão |
| 1 | RXDATA | A leitura devolve o byte mais antigo nos bits 7:0 e o remove da fila. O bit 8 vale 1 para indicar byte válido no `jtag` |
| 2 | STATUS | Específico do backend (seção 2 de cada documento de bloco) |
| 3 | CONTROL | Bits 0, 1 e 2 habilitam as interrupções de recepção, de transmissão vazia e de erro; zero no reset |

A interrupção `o_irq` é de nível, a soma das três causas habilitadas, nos dois backends. A plataforma liga `o_irq` a uma das duas fontes do PLIC, que continuam as mesmas: id 1 para a UART serial (`UART`) e id 2 para a UART sobre JTAG (`UART_JTAG`).

## 4. Ligação no topo

O Virtual JTAG é primitiva de fornecedor e não faz parte do console. O topo estrutural que usa o backend `jtag` instancia o `sld_virtual_jtag` e liga os seus sinais às portas do nó (a casca `jtag_uart_shell` faz isso para a Cyclone V). O topo que usa o backend `pinos` liga `i_rx` e `o_tx` aos pinos já normalizados pelo `board.yaml`. A plataforma escolhe o backend por generic do topo, e o driver de software do backend escolhido fica no `stdio` da plataforma.

## 5. Verificação

| Prova | Onde | O que mostra |
| :--- | :--- | :--- |
| Entidade `ConsoleJtag` | `tests/python/tests.json` | O console com `jtag` passa os mesmos testes de entidade do `jtag_uart` |
| Entidade `ConsolePins` e `ConsolePinsInverted` | `tests/python/unittests/UART/console_pins.py` | Reset, quadro 8N1 de transmissão, quadro de recepção, interrupção, com a polaridade normal e invertida |
| Formal `console` | `formal/console_props.sv` e `tests/vhdl/console_equiv.vhd` | Miter: a saída do console é igual à do bloco escolhido, com a polaridade como inversão explícita (limitada em ciclos) |
| Mutantes | `formal/run.sh` | Inversão de polaridade, bits de endereço e estrobe trocados são pegos pela prova |

Os dois blocos continuam com as suas próprias provas (`uart`, `uart_fifo` e `jtag_uart`), que o console não repete.

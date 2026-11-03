# UART sobre JTAG

## 1. O que é

Uma UART cuja outra ponta é um hospedeiro na JTAG em vez de uma linha serial: o core escreve bytes que o hospedeiro lê, e o hospedeiro escreve bytes que o core lê. É o periférico de id 4 (janela `0xC0000000`) do barramento externo do core. O VHDL é `src/UART/jtag/jtag_uart.vhd`, e a casca do Virtual JTAG da placa é `src/UART/jtag/cyclone-v/jtag_uart_shell.vhd`.

| Parte | Papel |
| :--- | :--- |
| Lado do core | Três registradores de palavra, um acesso por pulso de `we` ou `re` (seção 2) |
| Filas | De transmissão e de recepção, 64 bytes cada |
| Lado do hospedeiro | A lógica atrás de uma instância do Virtual JTAG (`sld_virtual_jtag` na placa, conduzida pelo testbench em simulação), no clock da JTAG (seção 3) |

O interconector que decodifica o endereço e dá o `ready` ao core está no Insper-RISC-V (`src/interconnect/`, ver o seu `ext_interconnect.md`).

## 2. Os registradores (lado do core)

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | TXDATA | 0 | Enfileira os bits 7:0 para o hospedeiro, descartados e sinalizados se a fila está cheia |
| 1 | RXDATA | Bit 8 = havia um byte esperando, bits 7:0 = esse byte (removido), 0 quando vazia | Ignorada |
| 2 | STATUS | Bits 7:0 lugares livres na fila de transmissão (0 a 64), bits 15:8 bytes na fila de recepção, bit 16 um byte foi descartado desde a última leitura (a leitura o limpa), bit 17 um hospedeiro já varreu desde o reset | Ignorada |

Uma escrita numa fila cheia nunca bloqueia o core. Um programa que não pode parar quando nenhum hospedeiro está conectado lê o bit 17 do STATUS: enquanto ele vale 0, ninguém escuta e o programa não imprime, e quando passa a valer 1 o programa espera um lugar livre, até um limite.

## 3. O lado do hospedeiro

A UART é a segunda instância do Virtual JTAG (índice de instância 1), ao lado da porta de depuração da SDRAM. O seu registrador de instrução tem 2 bits, e a instrução 1 seleciona um registrador de dados de 48 bits.

| Direção | Bits | Significado |
| :--- | :--- | :--- |
| Entrada | 8 | push: entregar ao core o byte abaixo |
| Entrada | 7:0 | O byte (só é aceito se push vale 1) |
| Saída | 31:0 | Até quatro bytes vindos do core, o primeiro nos bits 7:0 |
| Saída | 34:32 | Quantos deles são válidos |
| Saída | 35 | O push do comando foi descartado (fila de recepção cheia) |
| Saída | 36 | A varredura anterior foi descartada, porque o comando antes dela não tinha terminado |
| Saída | 47:40 | Bytes que ainda esperam na fila de transmissão |

Toda varredura aceita tira até quatro bytes da fila de transmissão. O clock da JTAG só roda durante uma varredura, então uma resposta é mostrada pela segunda varredura depois do seu comando (uma varredura mostra a resposta ao comando da varredura anterior à anterior) e só uma vez. Um hospedeiro que quer a saída continua varrendo, e um que quer enviar um byte liga push numa varredura.

## 4. Limites

| Item | Valor |
| :--- | :--- |
| Bytes por varredura, da placa para o hospedeiro | 4 |
| Bytes por varredura, do hospedeiro para a placa | 1 |
| Profundidade das filas | 64 bytes em cada sentido |
| Acesso de periférico | 1 ciclo do core mais a espera por `mem_advance` |

## 5. Verificação e um defeito corrigido

O comportamento é exercitado pelo barramento, pelo teste de sistema `ExtBus` do Insper-RISC-V (bytes em ordem, filas cheias, uma resposta mostrada uma vez e os flags de status). O bloco ainda não tem um teste de entidade próprio. O defeito que moldou o lado do hospedeiro está em [JTAG_UART_RESPOSTA_PERDIDA.md](../bugs/JTAG_UART_RESPOSTA_PERDIDA.md).

# flash_controller

Periférico mapeado em memória que comanda o chip de FLASH: o software escreve o endereço, enche o buffer de página e escreve o código do comando, e o controlador entrega o comando ao chip e mostra o estado dele.

## 1. Função do componente no SoC

Uma FLASH real muda de conteúdo por comandos (habilitar escrita, apagar setor, gravar página, proteger), não por stores. O controlador dá ao software a interface de registradores no estilo das FLASH seriais comuns e a liga ao chip modelado por `flash_cmd_port` (repositório Memory, documento [flash_cmd_port](https://github.com/insper-riscv/Memory/blob/main/docs/pt-br/rom/flash_cmd_port.md)). O pulso de invalidação das caches sai do chip, não do controlador.

| Lado | Sinais |
| :--- | :--- |
| Barramento do núcleo | `i_data_in`, `i_address`, `i_write`, `i_read`, `o_data_out` |
| Comando ao chip | `o_cmd_valid`, `o_cmd_op`, `o_cmd_addr` |
| Estado do chip | `i_busy`, `i_wel`, `i_refused` |
| Buffer de página lido pelo chip | `i_buf_idx`, `o_buf_data` |

## 2. Registradores

O endereço é o deslocamento em palavras dentro do periférico.

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `CMD` | Zero | Entrega ao chip o comando dos bits 2:0 do dado |
| 1 | `ADDR` | O endereço de byte do comando | Guarda os 32 bits como endereço do comando |
| 2 | `STATUS` | Bit 0 ocupado, bit 1 latch de escrita armado, bit 2 último apagar ou gravar recusado | Ignorada |
| 3 | `BUF_PTR` | Índice da palavra do buffer que o próximo `BUF_DATA` escreve | Define o índice (bits baixos do dado) |
| 4 | `BUF_DATA` | Zero | Escreve a palavra no buffer em `BUF_PTR` e soma um a `BUF_PTR`, que dá a volta no fim da página |
| 5 | `IRQ_ENABLE` | Bit 0 conclusão, bit 1 recusa | Define os dois bits; zero no reset |
| 6 | `IRQ_STATUS` | Bit 0 `DONE`, bit 1 `REFUSED` | Um em um bit o limpa (W1C) |
| 7 | Reservado | Zero | Ignorada |

Códigos de `CMD`:

| Código | Comando |
| :--- | :--- |
| 1 | Habilitar escrita |
| 2 | Apagar o setor que contém `ADDR` |
| 3 | Gravar a página que contém `ADDR` com o conteúdo do buffer |
| 4 | Proteger o setor que contém `ADDR` |
| 5 | Desproteger o setor |

## 3. Comportamento

### 3.1. Entrega do comando

A escrita em `CMD` levanta `o_cmd_valid` no mesmo ciclo, sem registrador no caminho, com `o_cmd_op` igual aos bits 2:0 do dado e `o_cmd_addr` igual ao registrador `ADDR`. O chip aceita o comando na borda que termina esse ciclo, e `STATUS` já mostra ocupado no ciclo seguinte. Uma leitura de `STATUS` logo depois da escrita em `CMD` nunca vê o estado anterior ao comando.

O chip ignora um comando que chega com ocupado em 1. O software espera `STATUS` com o bit 0 em zero antes de cada comando.

### 3.2. Buffer de página

O buffer tem uma página de `page_bytes` bytes. Seus bits ficam em 1 na configuração da FPGA, e o reset não o apaga. O software escreve as palavras da página com `BUF_DATA`, a partir de `BUF_PTR`, e depois manda o comando de gravar. As palavras que o software não escreve mantêm o conteúdo anterior do buffer, então uma página parcial escreve `0xFFFFFFFF` nas palavras que não deve alterar, porque a gravação faz o E bit a bit com o conteúdo da FLASH.

O chip lê o buffer por `i_buf_idx`, e `o_buf_data` traz a palavra uma borda depois, como a memória de armazenamento do chip.

### 3.3. Sequência de uma atualização de setor

1. Escrever `ADDR` com o endereço de um byte do setor.
2. Escrever `CMD` com 1 e depois com 2, esperando `STATUS` ocupado cair depois do segundo.
3. Para cada página do setor, escrever `ADDR`, encher o buffer, escrever `CMD` com 1 e depois com 3, e esperar o fim.
4. Ler `STATUS` e conferir que o bit 2 está em zero.

### 3.4. Interrupção

Dois eventos do chip ligam bits de `IRQ_STATUS`, mesmo com a habilitação desligada.

| Bit | Evento | Detecção |
| ---: | :--- | :--- |
| 0 `DONE` | O chip terminou um apagar ou gravar aceito | Queda de `i_busy` |
| 1 `REFUSED` | O chip recusou um apagar ou gravar | Subida de `i_refused`, que só cai com um novo habilitar escrita |

A saída `o_irq` vale um enquanto algum bit pendente estiver habilitado. O software limpa o evento escrevendo um no bit. Um evento no mesmo ciclo da limpeza vence e mantém o bit ativo.

## 4. Interface

### 4.1. Generics

| Generic | Tipo | Padrão | Significado |
| :--- | :--- | :--- | :--- |
| `page_bytes` | `positive` | 256 | Tamanho da página de gravar em bytes, potência de dois de 8 bytes em diante; é o tamanho do buffer |

### 4.2. Portas

| Porta | Direção | Largura | Significado |
| :--- | :--- | ---: | :--- |
| `i_clk` | entrada | 1 | Clock do módulo |
| `i_rst` | entrada | 1 | Reset, ativo em `'1'`; zera `ADDR` e `BUF_PTR` |
| `i_data_in` | entrada | 32 | Dado de escrita |
| `i_address` | entrada | 3 | Endereço de palavra |
| `i_write` | entrada | 1 | Pulso de escrita |
| `i_read` | entrada | 1 | Pulso de leitura |
| `o_data_out` | saída | 32 | Dado de leitura, zero sem `i_read` |
| `o_irq` | saída | 1 | Interrupção de nível, `(IRQ_STATUS and IRQ_ENABLE) /= 0` |
| `o_cmd_valid` | saída | 1 | Pulso que entrega um comando ao chip |
| `o_cmd_op` | saída | 3 | Código do comando |
| `o_cmd_addr` | saída | 32 | Endereço de byte do comando |
| `i_busy` | entrada | 1 | O chip está ocupado |
| `i_wel` | entrada | 1 | O latch de escrita do chip está armado |
| `i_refused` | entrada | 1 | O último apagar ou gravar foi recusado |
| `i_buf_idx` | entrada | $\log_2(\texttt{page\_bytes}) - 2$ | Índice da palavra do buffer lida pelo chip |
| `o_buf_data` | saída | 32 | Palavra do buffer, com leitura registrada |

## 5. Verificação

| Entrada de `tests/python/tests.json` | Módulo cocotb | O que cobre |
| :--- | :--- | :--- |
| `FlashController` | `tests.python.unittests.flash_controller.flash_controller` | Valores de reset; `ADDR` guarda a palavra inteira e só muda por escrita nele; o pulso de comando com o código e o endereço, só pela escrita em `CMD` e só no ciclo dela; `STATUS` nas oito combinações; `BUF_DATA` com avanço e volta de `BUF_PTR`; `BUF_PTR` definido por escrita; leitura do buffer uma borda depois; reset |

A prova formal está em `formal/flash_controller_props.sv` (ver [formal](../formal/formal.md)), com uma página de 16 bytes e nove mutantes do VHDL.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

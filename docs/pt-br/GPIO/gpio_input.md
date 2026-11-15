# GPIO só de entrada

🌐 [Português](../../pt-br/GPIO/gpio_input.md) · [English](../../en/GPIO/gpio_input.md)

## 1. O que é

Bloco de 1 a 32 pinos que a FPGA só lê (`gpio_input`). Cada pino de `i_pins` é uma entrada pura, sem tristate e sem saída, e o bloco entrega ao processador o nível sincronizado e uma interrupção opcional por borda ou por nível. Serve aos pinos que a placa liga a um circuito externo e que o Quartus recusa como pino bidirecional ou de saída, como as chaves DIP, o botão KEY[1] e os pinos de entrada dedicados `GPIO_*_IN` da DE0-Nano. Nessa placa o manual (seções 3.2, 3.5 e 3.6) lista esses pinos como entradas de 3,3 V, e o erro 169009 do Quartus recusa o `inout` do bloco `gpio` neles.

O bloco é o `gpio_group` com todos os pinos fixos em entrada e sem as portas do driver de pino, de modo que o mapa de registradores e o driver C do `gpio` valem sem mudança.

## 2. Interface

### 2.1. Generics

| Generic | Padrão | Descrição |
| :--- | ---: | :--- |
| `width` | 32 | Número de pinos, de 1 a 32 |
| `active_low` | zeros | Bit $p$ em 1 marca o pino $p$ como ativo em nível baixo; o programa lê o nível invertido |

### 2.2. Portas

| Porta | Sentido | Descrição |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock e reset síncrono, ativo em 1 |
| `i_data_in`, `o_data_out` | entrada e saída, `word_t` | Dados do barramento; a leitura é combinacional no endereço |
| `i_address` | entrada, 4 bits | Endereço de palavra dentro do bloco |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura |
| `o_irq` | saída | Vale 1 enquanto algum pino tem pendência |
| `i_pins` | entrada, `width` bits | Nível dos pinos físicos, assíncrono |

## 3. Registradores

O bloco ocupa 16 palavras (janela de 64 bytes), as mesmas do grupo do `gpio`, e os bits acima de `width` leem zero.

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `DIR` | Zero, a direção é fixa em entrada | Ignorada |
| 1 a 4 | `OUT_*` | O valor escrito, que não chega a pino algum | Guardada |
| 5 | `IRQ_MASK` | Máscara global por pino | Define a máscara |
| 6 | `RISE_MASK` | Máscara de subida | Define a máscara |
| 7 | `FALL_MASK` | Máscara de descida | Define a máscara |
| 8 | `IRQ_STAT` | Pino com interrupção pendente | A leitura limpa os bits lidos |
| 9 | `PINS` | Pinos sincronizados, com a polaridade aplicada | Ignorada |
| 10 | `LEVEL_MASK` | Modo de nível por pino | Define o modo |
| 11 a 15 | | Zero | Ignorada |

## 4. Entrada e interrupção

Cada pino passa por um sincronizador de dois estágios, e `PINS` lê o valor depois dele, dois ciclos de `i_clk` depois do pino. A condição de interrupção de cada pino depende de `LEVEL_MASK`, `RISE_MASK` e `FALL_MASK`, como no `gpio`, e só chega a `IRQ_STAT` e a `o_irq` com o bit do pino ligado em `IRQ_MASK`. Com todas as máscaras em zero, que é o valor do reset, o bloco só entrega o nível dos pinos e nenhuma interrupção sai.

| `LEVEL_MASK` | `RISE_MASK` | `FALL_MASK` | Condição do pino |
| :--- | :--- | :--- | :--- |
| 0 | 1 | 0 | Borda de subida da entrada sincronizada |
| 0 | 0 | 1 | Borda de descida |
| 0 | 1 | 1 | Qualquer mudança |
| 1 | 1 | 0 | Nível alto |
| 1 | 0 | 1 | Nível baixo |
| 1 | 1 | 1 | Sempre |

Num pino ativo em nível baixo as condições valem para o nível lógico depois da inversão, de modo que a borda de subida lógica é a descida elétrica.

## 5. Verificação

Os testes de entidade cobrem a leitura de `DIR`, a sincronização de `PINS`, as bordas de subida e de descida em pinos distintos, o modo de nível, a limpeza de `IRQ_STAT` pela leitura e a polaridade dos pinos ativos em nível baixo. O grupo que o bloco instancia tem as provas formais do `gpio`.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

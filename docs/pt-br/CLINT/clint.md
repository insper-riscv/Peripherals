# CLINT

🌐 [Português](../../pt-br/CLINT/clint.md) · [English](../../en/CLINT/clint.md)

## 1. O que é

O CLINT é o temporizador de máquina de um hart, mapeado em memória no leiaute do CLINT da SiFive, que o porte oficial do FreeRTOS espera. Ele entrega o `mtime` de 64 bits, o `mtimecmp` de 64 bits e o `msip`, e gera as interrupções de timer (`MTIP`) e de software (`MSIP`) de máquina.

| Parâmetro | Padrão | Significado |
| :--- | :--- | :--- |
| `tick_cycles` | 1 | Ciclos de clock por incremento do `mtime` |

O `TIMER` de uso geral segue como periférico independente. O `mtime` do CLINT é um contador próprio, com a frequência do clock dividida por `tick_cycles`, e o CSR `time` do núcleo é o sombreamento somente leitura dele, pela saída `o_mtime`. O contador de 64 bits é o `counter64` do Common-Components, instanciado com `width` igual a 64 e com a saída de estouro desligada.

## 2. Interface

Além das portas comuns dos periféricos, o CLINT tem duas saídas de interrupção. O endereço tem 14 bits de palavra, o que cobre os 64 KiB do mapa. O CLINT não tem `i_read`, porque a leitura não tem efeito colateral e `o_data_out` é combinacional no endereço.

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock e reset, ativo em 1 |
| `i_data_in`, `i_address` | entrada | Dado de escrita de `XLEN` bits (`word_t`) e endereço de palavra de 14 bits |
| `i_write` | entrada | Pulso de escrita |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço |
| `o_irq_timer` | saída | `MTIP` |
| `o_irq_software` | saída | `MSIP` |

## 3. Mapa de registradores

Todos os acessos são de 32 bits, na ordem little-endian, com a metade baixa no endereço menor. Um endereço fora do mapa lê zero e ignora a escrita.

| Deslocamento | Registrador | Acesso | Reset |
| :--- | :--- | :--- | :--- |
| `0x0000` | `msip` (bit 0) | L/E | 0 |
| `0x4000` | `mtimecmp` baixa | L/E | `0xFFFFFFFF` |
| `0x4004` | `mtimecmp` alta | L/E | `0xFFFFFFFF` |
| `0xBFF8` | `mtime` baixa | L/E | 0 |
| `0xBFFC` | `mtime` alta | L/E | 0 |

Só o bit 0 do `msip` é guardado, e os demais bits leem zero.

## 4. Contagem e leitura do `mtime`

A cada `tick_cycles` ciclos o `mtime` soma 1. A metade baixa soma 1 e, quando estava com todos os bits em 1, o vai-um fica registrado e a metade alta soma 1 no ciclo seguinte, de modo que nenhuma soma de 64 bits entra em um caminho combinacional. No ciclo com vai-um pendente a leitura da metade alta devolve a metade alta armazenada mais o vai-um, então o par lido é sempre o valor do contador ideal de 64 bits.

A leitura em três passos do porte (alta, baixa, alta) repete até as duas metades altas coincidirem, e o resultado é coerente. Uma escrita da metade baixa vence o incremento do próprio ciclo, e uma escrita da metade alta descarta o vai-um pendente.

## 5. Comparação e `MTIP`

$$MTIP_{t+1} = \left( mtime_t \ge mtimecmp_t \right)$$

A comparação é sem sinal, em 64 bits, e o resultado passa por um registrador de um ciclo. Com o reset, o `mtimecmp` vale todos os bits em 1 e o `MTIP` fica baixo. A saída `MSIP` é o bit 0 do `msip`.

## 6. Escrita segura do `mtimecmp`

O porte do FreeRTOS escreve o `mtimecmp` em três escritas de 32 bits.

| Passo | Escrita | Valor do `mtimecmp` depois |
| :--- | :--- | :--- |
| 1 | Metade baixa com `0xFFFFFFFF` | $\{hi_{antigo}, \mathtt{0xFFFFFFFF}\} \ge$ valor antigo |
| 2 | Metade alta com o valor final | $\{hi_{final}, \mathtt{0xFFFFFFFF}\} \ge$ valor final |
| 3 | Metade baixa com o valor final | Valor final |

Cada estado intermediário é maior ou igual ao valor antigo ou ao final, e com $mtime$ crescente isso garante que o `MTIP` não sobe no meio da sequência sem que o valor antigo ou o final o fizesse subir. Escrever a metade baixa primeiro com o valor final não tem essa garantia, e dispara uma interrupção que ainda não é devida quando a metade alta antiga é menor que a final.

## 7. Verificação

| Verificação | Cobertura |
| :--- | :--- |
| Testes de entidade `CLINT` e `ClintTick` | Reset, contagem, vai-um com leitura em três passos, comparação de 64 bits, igualdade, sequência de escrita do porte sem `MTIP` espúrio, queda do `MTIP` pendente, `msip`, endereços fora do mapa, divisor de ciclos e contador contra um modelo aleatório |
| Prova formal `clint` | As saídas e a leitura de cada endereço seguem o modelo ideal; na sequência de escrita do porte o `MTIP` só vale se o valor antigo ou o final já foi alcançado; covers de subida e descida do `MTIP`, do `MSIP` e do vai-um |

Os mutantes e o método estão em [formal.md](../formal/formal.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

# GPIO

🌐 [Português](../../pt-br/GPIO/gpio.md) · [English](../../en/GPIO/gpio.md)

## 1. O que é

Bloco de E/S de uso geral com partição adaptativa. O bloco reúne `pin_count` pinos bidirecionais em `group_count` grupos, e cada grupo tem o seu arquivo de registradores de 64 bytes (`gpio_group`), com direção, saída, entrada sincronizada e configuração de interrupção por pino. A partição, a direção fixa e a polaridade de cada pino chegam por generics, de modo que a mesma entidade serve a um LED por grupo (`solo`), a todas as chaves num registrador só (`all`) ou a uma partição escrita à mão. O bloco inteiro usa uma única janela do interconector.

| Entidade | Papel |
| :--- | :--- |
| `gpio` | Bloco com a partição, o seletor de grupo, a leitura e os pinos físicos |
| `gpio_group` | Arquivo de registradores de um grupo de 1 a 32 pinos |
| `gpio_cell` | Um pino, com direção, saída, entrada sincronizada e interrupção |
| `gpio_operation_decoder` | Endereço de palavra do grupo em habilitações de escrita e seletor de leitura |
| `gpio_pkg` | Funções de elaboração que leem as listas dos generics |

## 2. Interface do bloco `gpio`

### 2.1. Generics

Um vetor de números tem um campo de 8 bits por elemento, com o elemento $k$ nos bits $8k+7$ a $8k$ (o elemento 0 é o campo menos significativo). Os generics usam só inteiros e `std_logic_vector`, sem tipo da VHDL-2008 nem pacote genérico.

| Generic | Tipo | Padrão | Codificação |
| :--- | :--- | :--- | :--- |
| `pin_count` | `positive` de 1 a 255 | 32 | Pinos do bloco, numerados de 0 a `pin_count - 1` |
| `group_count` | `positive` de 1 a 255 | 1 | Número de grupos $G$ |
| `member_count` | `positive` de 1 a 255 | 32 | Total de índices listados em `group_members`, igual à soma dos tamanhos |
| `group_sizes` | `std_logic_vector(8 * group_count - 1 downto 0)` | `x"20"` | Campo $g$ é o número de pinos do grupo $g$, de 1 a 32 |
| `group_members` | `std_logic_vector(8 * member_count - 1 downto 0)` | pinos 0 a 31 | Índices de pino de todos os grupos em sequência, na ordem escrita; o bit $k$ dos registradores do grupo é o $k$-ésimo pino da lista do grupo |
| `pin_dirs` | `std_logic_vector(2 * pin_count - 1 downto 0)` | zeros | Código do pino $p$ nos bits $2p+1$ a $2p$ |
| `pin_active_low` | `std_logic_vector(pin_count - 1 downto 0)` | zeros | Bit $p$ em 1 é pino ativo em nível baixo |

| Código de `pin_dirs` | Direção do pino |
| :--- | :--- |
| `00` | Livre, o registrador `DIR` decide |
| `01` | Fixa em entrada |
| `10` | Fixa em saída |
| `11` | Recusado na elaboração |

Os tamanhos dos vetores dependem dos generics anteriores, então quem instancia o bloco passa todos os generics e escreve os vetores com a largura que os outros generics impõem. O exemplo abaixo é a partição `[[0,1,2,3],[5,6]]` de um papel com 7 pinos, todos livres e ativos em nível alto, com o pino 4 desligado.

```vhdl
u_leds : entity work.gpio
    generic map (
        pin_count      => 7,
        group_count    => 2,
        member_count   => 6,
        group_sizes    => x"02" & x"04",
        group_members  => x"06" & x"05" & x"03" & x"02" & x"01" & x"00",
        pin_dirs       => (others => '0'),
        pin_active_low => (others => '0')
    )
```

A concatenação lista o último elemento primeiro, porque o elemento 0 é o campo menos significativo.

### 2.2. Portas

| Porta | Sentido | Tipo | Função |
| :--- | :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | `std_logic` | Clock e reset, ativo em 1 |
| `i_data_in` | entrada | `word_t` | Dado de escrita |
| `i_address` | entrada | `std_logic_vector(block_addr_width(group_count) - 1 downto 0)` | Endereço de palavra dentro da janela |
| `i_write`, `i_read` | entrada | `std_logic` | Pulsos de escrita e de leitura |
| `o_data_out` | saída | `word_t` | Dado de leitura, combinacional no endereço |
| `o_irq` | saída | `std_logic` | Vale 1 enquanto algum grupo tem pendência |
| `io_gpio_pins` | inout | `std_logic_vector(pin_count - 1 downto 0)` | Pinos físicos |

## 3. Janela e endereço

O arquivo de registradores de cada grupo ocupa 64 bytes, e o grupo $g$ começa em $64g$ bytes a partir da base do bloco. O bloco ocupa uma janela de

$$
W = 2^{\lceil \log_2 (64 \cdot G) \rceil}
$$

bytes, que é $64 G$ arredondado para a potência de dois seguinte. A largura do endereço de palavra é

$$
\text{block\_addr\_width}(G) = 4 + \lceil \log_2 G \rceil
$$

bits, em que os 4 bits baixos escolhem a palavra do grupo e os bits altos escolhem o grupo. O interconector acerta o bloco quando `(addr and not (W - 1)) = base`, com `base` alinhada a $W$, e entrega ao bloco o endereço de byte sem os 2 bits baixos. Um grupo que não existe (índice maior ou igual a $G$ dentro da janela) lê zero e ignora a escrita.

| $G$ | Janela $W$ | Largura de `i_address` |
| ---: | ---: | ---: |
| 1 | 64 B | 4 |
| 2 | 128 B | 5 |
| 3 e 4 | 256 B | 6 |
| 10 | 1 KiB | 8 |
| 18 | 2 KiB | 9 |

## 4. Registradores de um grupo

Cada grupo tem 16 palavras. Os bits acima do tamanho do grupo leem zero e ignoram a escrita. Uma palavra fora da tabela lê zero e ignora a escrita.

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `DIR` | Direção de cada pino, 1 é saída; os pinos de direção fixa leem o valor fixo | Define a direção dos pinos livres |
| 1 | `OUT_LOAD` | Registrador de saída | Carrega a palavra inteira |
| 2 | `OUT_SET` | Registrador de saída | Liga os bits escritos com 1 |
| 3 | `OUT_CLR` | Registrador de saída | Limpa os bits escritos com 1 |
| 4 | `OUT_TGL` | Registrador de saída | Inverte os bits escritos com 1 |
| 5 | `IRQ_MASK` | Máscara global por pino | Define a máscara |
| 6 | `RISE_MASK` | Máscara de subida por pino | Define a máscara |
| 7 | `FALL_MASK` | Máscara de descida por pino | Define a máscara |
| 8 | `IRQ_STAT` | Pino com interrupção pendente | A leitura limpa os bits lidos |
| 9 | `PINS` | Pinos sincronizados | Ignorada |
| 10 | `LEVEL_MASK` | Modo de nível por pino | Define o modo |
| 11 a 15 | | Zero | Ignorada |

## 5. Pino desligado

Um pino que não está na lista de nenhum grupo fica desligado, sem registrador, sem leitura e sem interrupção.

| Direção do pino desligado | Nível do pino físico |
| :--- | :--- |
| Fixa em saída | Mantido no nível inativo, que é 0 para o pino ativo em nível alto e 1 para o ativo em nível baixo |
| Livre ou fixa em entrada | Alta impedância |

## 6. Interrupção

Cada pino tem seu bit de pendência em `IRQ_STAT`, que liga quando a condição do pino vale e `IRQ_MASK` está ligada. `o_irq` vale 1 enquanto algum bit de pendência de qualquer grupo estiver ligado. A leitura de `IRQ_STAT` de um grupo limpa só os bits desse grupo. Os eventos de um pino dependem do seu bit em `LEVEL_MASK`.

| `LEVEL_MASK` | `RISE_MASK` | `FALL_MASK` | Condição do pino |
| :--- | :--- | :--- | :--- |
| 0 | 1 | 0 | Borda de subida da entrada sincronizada |
| 0 | 0 | 1 | Borda de descida |
| 0 | 1 | 1 | Qualquer mudança |
| 1 | 1 | 0 | Nível alto |
| 1 | 0 | 1 | Nível baixo |
| 1 | 1 | 1 | Sempre (qualquer nível) |

No modo de nível a pendência religa a cada ciclo enquanto o nível valer, então a leitura de `IRQ_STAT` não encerra a causa. O software desabilita a máscara do pino ou remove o nível na origem. Todos os registradores de máscara e o modo valem zero no reset.

## 7. Polaridade e direção fixa

Com o bit de `pin_active_low` em 1, a `gpio_cell` inverte os dois sentidos do pino. O pino lido é invertido antes do sincronizador, de modo que `PINS`, as bordas e os níveis valem para o programa ativo em 1, e o registrador de saída é invertido antes do tristate. O programa vê e escreve sempre ativo em 1.

Num pino de direção fixa, o registrador interno de direção ainda aceita a escrita, mas o valor efetivo é o fixo, que `DIR` lê e que habilita ou solta o tristate. A direção fixa em saída mantém o pino sempre dirigido, inclusive durante o reset.

## 8. Verificação

Os testes de entidade cobrem as partições `solo`, `pairs`, explícita (`[[0,1,2,3],[5,6]]` com um pino desligado), um grupo com a ordem dos pinos invertida, `all`, um bloco misto com direções fixas, polaridades e um pino desligado em saída, a célula com direção fixa e o grupo de 32 pinos. A prova formal do bloco (`gpio_props.sv`) compara a leitura de `DIR` e de `OUT`, a leitura dos endereços sem registrador e o valor dirigido a cada pino com um modelo ideal, em duas partições, e a da célula (`gpio_cell_props.sv`) inclui a polaridade, o modo de nível e as duas direções fixas, cada uma com os seus mutantes.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

# GPIO

🌐 [Português](../../pt-br/GPIO/gpio.md) · [English](../../en/GPIO/gpio.md)

## 1. O que é

Bloco de E/S de uso geral com `data_width` pinos bidirecionais; `data_width` zero é permitido e deixa o bloco sem pino, sem registrador e sem interrupção. Cada pino é uma `gpio_cell` com direção, saída, entrada sincronizada e configuração de interrupção por pino. O decodificador `gpio_operation_decoder` traduz o endereço de palavra nas habilitações de escrita e no seletor de leitura.

## 2. Registradores

O endereço é de palavra, com 4 bits. Um endereço fora da tabela lê zero e ignora a escrita.

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `DIR` | Direção de cada pino, 1 é saída | Define a direção |
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

## 3. Interrupção

Cada pino tem seu bit de pendência em `IRQ_STAT`, que liga quando a condição do pino vale e `IRQ_MASK` está ligada. A saída `o_irq` vale 1 enquanto algum bit de pendência estiver ligado. Os eventos de um pino dependem do seu bit em `LEVEL_MASK`.

| `LEVEL_MASK` | `RISE_MASK` | `FALL_MASK` | Condição do pino |
| :--- | :--- | :--- | :--- |
| 0 | 1 | 0 | Borda de subida da entrada sincronizada |
| 0 | 0 | 1 | Borda de descida |
| 0 | 1 | 1 | Qualquer mudança |
| 1 | 1 | 0 | Nível alto |
| 1 | 0 | 1 | Nível baixo |
| 1 | 1 | 1 | Sempre (qualquer nível) |

No modo de nível a pendência religa a cada ciclo enquanto o nível valer, então a leitura de `IRQ_STAT` não encerra a causa. O software desabilita a máscara do pino ou remove o nível na origem. Todos os registradores de máscara e o modo valem zero no reset, o que mantém o comportamento de borda dos mapas anteriores.

## 4. Polaridade

O generic `active_low` (padrão falso) inverte os dois sentidos do pino dentro da `gpio_cell`. O pino lido é invertido antes do sincronizador, de modo que `PINS`, as bordas e os níveis de interrupção valem para o programa ativo em `1`, e o registrador de saída é invertido antes do buffer de três estados. O programa vê e escreve sempre ativo em `1`, e o topo só escolhe o generic conforme a placa.

## 5. Verificação

Testes de entidade do decodificador, da célula e do bloco cobrem o mapa, as bordas, o modo de nível por pino e a leitura zero dos endereços fora do mapa. A prova formal da célula (`gpio_cell_props.sv`) inclui o modo de nível, a polaridade `active_low` e os mutantes de cada um. Os testes cobrem ainda o bloco com `active_low` e o bloco de largura zero.

## 6. Driver C23

Crie cada instância com `rv32_gpio_new(base, quantidade_de_pinos)`. O construtor
não aloca memória nem escreve no hardware. Argumentos inválidos geram um handle
inválido, verificável por `rv32_gpio_valid`. Não inicialize a struct diretamente.
A quantidade de pinos vem da instância RTL, não do tamanho da janela MMIO.

```c
rv32_gpio_t gpio = rv32_gpio_new(RV32_GPIO_SWITCHES_BASE, 10);

rv32_gpio_pin_direction(gpio, 3, RV32_GPIO_OUTPUT_PIN);
rv32_gpio_pin_write(gpio, 3, true);
rv32_gpio_pin_toggle(gpio, 3);
```

Os pinos usam índices `size_t` a partir de zero. O driver valida o índice e gera
internamente `1u << pin`: pino 3 significa máscara `0x08`, não endereço `0x03`.
Set/clear/toggle usam os registradores atômicos do hardware. Direção e configuração
de IRQ preservam os outros bits, mas exigem serialização entre chamadores.
A API anterior de máscaras completas continua disponível para operações em grupo.

A leitura de pino retorna o valor sincronizado disponível naquele momento. Ela
não espera propagação. Um teste que escreve e verifica o pino deve fazer polling
com limite de tentativas; não use um `settle()` arbitrário em toda operação.
A leitura de IRQ limpa TODOS os eventos da instância. Use
`rv32_gpio_irq_contains(snapshot, pin)` para interpretar a captura sem máscaras
na aplicação; uma condição de nível persistente pode gerar outro evento.

O SDK copia os fontes para `vendor/GPIO` e gera os endereços-base com o resolvedor
do `platform.yaml`. Os offsets dos registradores são definidos pelo RTL e ficam
no arquivo C. Um driver atende GPIO, SWITCHES e KEYS.

Todos os periféricos agora possuem drivers com construtores: GPIO, TIMER, CLINT,
PLIC, UART (serial/JTAG), DISPLAY e FLASH. CLINT usa leitura coerente de 64 bits
e escrita segura do comparador; PLIC recebe o número da fonte, com zero reservado;
DISPLAY recebe o índice do dígito. UART exige backend e capacidade TX reais.
FLASH usa índice de palavra no buffer, comandos nomeados e confirmação W1C de IRQ.
Os headers de cada driver documentam limites e efeitos colaterais.

Execute `make driver-test` para MMIO em RAM e `make test` para os efeitos do RTL.
RAM não emula read-to-clear, W1C, FIFOs ou propagação dos pinos.

Use `.clang-format`: quatro espaços de indentação, funções em múltiplas linhas,
uma instrução por linha e linhas vazias entre funções e blocos lógicos.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

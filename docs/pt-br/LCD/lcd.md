# Controlador do LCD 16x2

🌐 [Português](../../pt-br/LCD/lcd.md) · [English](../../en/LCD/lcd.md)

## 1. O que é

Periférico de barramento que conduz o módulo LCD alfanumérico 16x2 da DE2-115, compatível com o controlador HD44780, pela interface paralela de 8 bits (seção 4.6 do manual da placa). O software escreve comandos e dados em registradores, uma fila de escrita absorve a rajada e uma camada física gera a temporização do barramento e espera o chip terminar cada operação. A inicialização do chip pode ser feita em hardware, por generic.

| Bloco | Função |
| :--- | :--- |
| `lcd_regs` | Decodificação do barramento, registradores, flags de erro e interrupção |
| `uart_fifo` | Fila de escrita de 9 bits (RS e byte), a mesma da UART |
| `lcd_phy` | Temporização de RS, RW, EN e dado, espera pelo flag de ocupado ou por atraso fixo |
| `lcd_init` | Sequência de inicialização opcional |
| `lcd` | Topo estrutural que liga os blocos e o sincronizador do flag de ocupado |

## 2. Pinos

| Porta | Sentido | Pino da placa | Descrição |
| :--- | :--- | :--- | :--- |
| `i_lcd_data` | entrada | `LCD_DATA[7:0]` | Valor dos pinos de dados; só o bit 7 é lido (flag de ocupado) |
| `o_lcd_data` | saída | `LCD_DATA[7:0]` | Valor conduzido nos pinos de dados |
| `o_lcd_data_oe` | saída | `LCD_DATA[7:0]` | Habilitação do driver, para a camada de três estados do topo da placa |
| `o_lcd_rs` | saída | `LCD_RS` | 0 comando, 1 dado |
| `o_lcd_rw` | saída | `LCD_RW` | 0 escrita, 1 leitura; fixo em 0 sem `has_rw` |
| `o_lcd_en` | saída | `LCD_EN` | Habilitação do chip |
| `o_lcd_on` | saída | `LCD_ON` | Alimentação do módulo, controlada por `CONTROL` |
| `o_lcd_blon` | saída | `LCD_BLON` | Luz de fundo, controlada por `CONTROL`; os módulos atuais da DE2-115 não têm luz de fundo |

O periférico não instancia buffer de fabricante. O topo da placa liga `o_lcd_data` aos pinos quando `o_lcd_data_oe` vale 1 e leva o valor dos pinos a `i_lcd_data`. O driver só fica ligado durante a escrita, com RW baixo, e o chip conduz o barramento só com RW e EN altos.

## 3. Registradores

O endereço é de palavra, com 3 bits, e o bloco ocupa 8 palavras. Os endereços 6 e 7 leem zero e ignoram a escrita.

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `COMMAND` | W | n/a | Bits 7:0 entram na fila com RS = 0; a leitura devolve zero |
| 1 | `DATA` | W | n/a | Bits 7:0 entram na fila com RS = 1; a leitura devolve zero |
| 2 | `STATUS` | R/W1C | `0x4` | Flags da tabela abaixo; escrever 1 em `DROPPED` ou `TIMEOUT` o limpa |
| 3 | `CONTROL` | R/W | `0x6` com `has_rw`, `0x4` sem | Bits da tabela abaixo |
| 4 | `DELAY` | R/W | 50 µs em ciclos | Bits 23:0, ciclos de espera depois de um comando comum ou de um dado |
| 5 | `DELAY_LONG` | R/W | 2 ms em ciclos | Bits 23:0, ciclos de espera depois de limpar a tela (`0x01`) ou de levar o cursor ao início (`0x02`, `0x03`) |

`STATUS`.

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `BUSY` | Há inicialização, fila não vazia ou operação em andamento no barramento |
| 1 | `FIFO_FULL` | A fila está cheia |
| 2 | `FIFO_EMPTY` | A fila está vazia |
| 3 | `INIT_BUSY` | A inicialização em hardware está em andamento |
| 4 | `DROPPED` | Uma escrita foi descartada por fila cheia; fica aceso até a escrita de 1 |
| 5 | `TIMEOUT` | O flag de ocupado não baixou dentro do tempo limite; fica aceso até a escrita de 1 |
| 15:8 | `FIFO_LEVEL` | Quantidade de palavras na fila |

`CONTROL`.

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `EMPTY_IRQ_ENABLE` | Habilita a interrupção de fila vazia |
| 1 | `POLL_ENABLE` | Espera pelo flag de ocupado em vez de usar `DELAY`; só existe com `has_rw`, e sem ele o bit lê 0 e ignora a escrita |
| 2 | `LCD_ON` | Nível do pino `LCD_ON` |
| 3 | `BACKLIGHT_ON` | Nível do pino `LCD_BLON` |

A saída `o_irq` é de nível e vale 1 com a fila vazia, a habilitação ligada e a inicialização concluída. Ela cai com a escrita de uma palavra e volta quando a camada física retira a última da fila. O acesso ao barramento termina em um ciclo e a leitura não tem efeito colateral (a porta `i_read` existe só por uniformidade com os outros periféricos).

## 4. Temporização

### 4.1. Escrita

Cada operação executa as fases abaixo, com as durações dadas por generics em nanossegundos e convertidas em ciclos do clock de `clk_freq_hz`, arredondadas para cima e com no mínimo um ciclo.

| Fase | Generic | Padrão | Mínimo do chip |
| :--- | :--- | ---: | ---: |
| RS, RW e dado antes de EN | `setup_ns` | 100 ns | 40 ns (dado 80 ns) |
| EN alto | `pulse_ns` | 300 ns | 230 ns |
| RS, RW e dado depois de EN | `hold_ns` | 100 ns | 10 ns |

A soma dos três padrões respeita o ciclo mínimo de EN de 500 ns. O chip captura o dado na descida de EN.

### 4.2. Espera pelo fim da operação

Depois da escrita o chip fica ocupado. A camada física espera de uma entre duas formas.

| Modo | Quando | Como |
| :--- | :--- | :--- |
| Flag de ocupado | `has_rw` e `POLL_ENABLE` ligado | Repete leituras com RW = 1 e RS = 0 e amostra o bit 7 do dado no último ciclo do pulso de EN, até ele valer 0 ou o tempo `busy_timeout_us` acabar (então `TIMEOUT` acende e a camada segue adiante) |
| Atraso fixo | Sem `has_rw` ou com `POLL_ENABLE` desligado | Espera `DELAY` ciclos depois de comandos comuns e de dados, e `DELAY_LONG` ciclos depois de limpar a tela e de levar o cursor ao início |

O bit 7 passa por um sincronizador de dois estágios. O pulso de EN deve durar mais que o atraso de dados do chip (160 ns) somado aos dois ciclos do sincronizador; os 300 ns padrão cobrem isso a partir de 50 MHz, e para clocks mais lentos aumente `pulse_ns`.

### 4.3. Inicialização em hardware

Com `auto_init` ligado, depois do reset o periférico espera `power_up_us` e envia, com atraso fixo e sem ler o ocupado, os comandos da tabela. Escritas do software durante a sequência esperam na fila e saem depois dela; `INIT_BUSY` vale 1 e a interrupção fica em 0 até o fim.

| Passo | Byte | Espera depois |
| ---: | :--- | :--- |
| 1 | `0x30` | 5 ms |
| 2 e 3 | `0x30` | 200 µs |
| 4 | `0x38` (8 bits, duas linhas, fonte 5x8) | `exec_us` |
| 5 | `0x0C` (display ligado, cursor desligado) | `exec_us` |
| 6 | `0x01` (limpar) | `exec_long_us` |
| 7 | `0x06` (entry mode: cursor à direita) | `exec_us` |

## 5. Parâmetros

| Generic | Padrão | Descrição |
| :--- | ---: | :--- |
| `data_width` | 32 | Largura do barramento, no mínimo 24 |
| `clk_freq_hz` | 50000000 | Frequência do clock |
| `fifo_depth` | 16 | Profundidade da fila, até 255 |
| `has_rw` | verdadeiro | O pino `LCD_RW` é ligado ao periférico |
| `auto_init` | falso | Liga a inicialização em hardware |
| `setup_ns`, `pulse_ns`, `hold_ns` | 100, 300, 100 | Tempos do barramento |
| `power_up_us` | 20000 | Espera de energização antes da inicialização |
| `exec_us` | 50 | Valor de reset de `DELAY` e espera da inicialização |
| `exec_long_us` | 2000 | Valor de reset de `DELAY_LONG` e espera de limpar na inicialização |
| `busy_timeout_us` | 10000 | Tempo limite da espera pelo flag de ocupado |

Os tempos do chip citados neste documento (40 ns, 230 ns, 10 ns, 160 ns, ciclo de 500 ns, 37 µs por comando, 1,52 ms para limpar, 15 ms de energização, 4,1 ms e 100 µs de acordar) vêm do que se conhece do HD44780 e não foram conferidos no datasheet, que não está em `Docs`; os padrões têm folga sobre eles.

## 6. Sequência de uso

Com `auto_init` desligado, o software espera 20 ms depois da energização e envia a sequência. Em C, com espera pelo ocupado:

```c
#define LCD_COMMAND (*(volatile uint32_t *)(LCD_BASE + 0x00))
#define LCD_DATA    (*(volatile uint32_t *)(LCD_BASE + 0x04))
#define LCD_STATUS  (*(volatile uint32_t *)(LCD_BASE + 0x08))
#define LCD_FIFO_FULL (1u << 1)
#define LCD_BUSY      (1u << 0)

static void lcd_put(volatile uint32_t *reg, uint8_t byte)
{
    while (LCD_STATUS & LCD_FIFO_FULL) { }
    *reg = byte;
}

void lcd_print(const char *text)
{
    lcd_put(&LCD_COMMAND, 0x38);
    lcd_put(&LCD_COMMAND, 0x0C);
    lcd_put(&LCD_COMMAND, 0x01);
    lcd_put(&LCD_COMMAND, 0x06);
    while (*text) { lcd_put(&LCD_DATA, (uint8_t)*text++); }
    lcd_put(&LCD_COMMAND, 0xC0);   /* início da segunda linha */
    while (LCD_STATUS & LCD_BUSY) { }
}
```

Com `auto_init` ligado, o laço de `lcd_print` começa direto em `LCD_DATA`, pois as escritas esperam a inicialização na fila.

## 7. Verificação

Os testes cocotb usam um modelo comportamental do HD44780 com DDRAM de 128 posições, cursor, limpar, entry mode e flag de ocupado. O modelo confere os tempos do barramento, recusa escrita com o chip ocupado, exige 15 ms de energização e exige que não haja conflito no barramento de dados. As provas formais cobrem a camada física (conflito, setup, hold, pulso, duração da operação, tempo limite) e os registradores (controle, flags de erro, interrupção, leitura); a fila é a `uart_fifo`, provada com a UART.

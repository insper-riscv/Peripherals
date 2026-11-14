# ADC interno do MAX 10

🌐 [Português](../../pt-br/ADC/max10_adc.md) · [English](../../en/ADC/max10_adc.md)

## 1. O que é

Periférico (`max10_adc`) que dá ao processador o conversor analógico-digital interno do MAX 10, de 12 bits, pelo núcleo `altera_modular_adc` do Quartus. Na DE10-Lite o conversor lê as seis entradas analógicas do conector Arduino (A0 a A5) e as duas entradas do cabeçalho 1x2 não montado, e o núcleo também lê o sensor de temperatura do chip.

O periférico envolve a interface Avalon-ST do núcleo, comando e resposta por canal, com registradores. Um sequenciador percorre os canais de uma máscara, um registrador por canal guarda a última amostra com os flags de conversão, um período configurável repete a varredura e uma interrupção avisa o fim de cada varredura.

O núcleo do conversor é IP do fornecedor, e o GHDL não tem o modelo dele. Os testes de entidade usam um modelo comportamental do núcleo, em `tests/vhdl`, e a placa usa o IP que o script de geração produz.

## 2. Interface

### 2.1. Generics

| Generic | Padrão | Descrição |
| :--- | ---: | :--- |
| `clk_freq` | 100000000 | Frequência de `i_clk` em Hz |
| `scan_freq` | 1000 | Frequência de varredura em Hz que o período tem ao sair do reset |

### 2.2. Portas

| Porta | Sentido | Descrição |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock e reset síncrono, ativo em 1 |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura do barramento |
| `i_address` | entrada, 5 bits | Endereço de palavra do registrador |
| `i_data_in`, `o_data_out` | entrada e saída, `word_t` | Dados do barramento; a saída vale zero fora de uma leitura |
| `o_irq` | saída | Interrupção em nível |
| `o_cmd_valid`, `o_cmd_channel`, `o_cmd_sop`, `o_cmd_eop`, `i_cmd_ready` | saída e entrada | Interface Avalon-ST de comando do núcleo: canal de 5 bits, início e fim do pacote da varredura |
| `i_rsp_valid`, `i_rsp_channel`, `i_rsp_data` | entrada | Interface Avalon-ST de resposta do núcleo: canal de 5 bits e amostra de 12 bits |

## 3. Registradores

O endereço é de palavra, com 5 bits. Um endereço fora da tabela lê zero e ignora a escrita.

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | leitura e escrita | 0 | Bit 0 `ENABLE`, bit 1 `CONTINUOUS`, bit 2 `IRQ`; o bit 3 `START` é um pulso de escrita e lê como zero |
| 1 | `MASK` | leitura e escrita | 0 | Canais da varredura, um bit por canal, bits 0 a 17 |
| 2 | `PERIOD` | leitura e escrita | `clk_freq / scan_freq` | Ciclos de `i_clk` entre dois inícios de varredura no modo contínuo |
| 3 | `STATUS` | leitura e escrita de 1 para limpar | 0 | Estado, ver a tabela de bits |
| 8 a 25 | `CH0` a `CH17` | leitura | 0 | Resultado do canal, ver a tabela de bits |

### 3.1. Bits de `CTRL`

| Bit | Nome | Efeito |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Liga o sequenciador; desligado, nenhum início é aceito (a varredura em curso termina) |
| 1 | `CONTINUOUS` | Repete a varredura a cada `PERIOD` ciclos |
| 2 | `IRQ` | Habilita a interrupção de fim de varredura |
| 3 | `START` | Pede uma varredura única, aceita com `ENABLE` ligado e o sequenciador livre |

### 3.2. Bits de `STATUS`

| Bit | Nome | Descrição |
| ---: | :--- | :--- |
| 0 | `BUSY` | Varredura em curso |
| 1 | `DONE` | Varredura terminada; fica ligado até ser limpo |
| 2 | `LATE` | Um início, manual ou por período, chegou com a varredura anterior ainda em curso e foi descartado; fica ligado até ser limpo |

Escrever 1 num dos bits 1 e 2 limpa o bit. Um evento no mesmo ciclo da escrita prevalece. Quando `BUSY` volta a 0, `DONE` já vale 1.

### 3.3. Registrador de canal

| Bit | Nome | Descrição |
| ---: | :--- | :--- |
| 11:0 | `DATA` | Última amostra do canal, de 0 a 4095 |
| 12 | `VALID` | Há um resultado novo, ainda não lido |
| 13 | `OVERRUN` | Uma amostra nova substituiu um resultado que não tinha sido lido |

A leitura do registrador devolve a amostra e os dois flags e limpa os flags. Uma amostra que chega no mesmo ciclo da leitura fica como resultado novo, com `OVERRUN` em 0.

## 4. Comportamento

### 4.1. Numeração dos canais

O número do canal é o do comando do núcleo `altera_modular_adc` de um bloco ADC.

| Canal | Entrada |
| ---: | :--- |
| 0 | Entrada analógica dedicada (`ANAIN1` no primeiro bloco) |
| 1 a 8 | Pinos de função dupla (`ADC1IN1` a `ADC1IN8` no primeiro bloco) |
| 9 a 16 | Só existem em dispositivos com mais pinos de ADC; o manual da DE10-Lite não os usa |
| 17 | Sensor de temperatura do chip |

O número 17 do sensor de temperatura e a recalibração (comando 31, não usada) vêm do código-fonte do núcleo instalado com o Quartus. A leitura do sensor muda o clock de amostragem do conversor para 50 kHz durante a conversão, e por isso o canal 17 demora mais que os demais.

### 4.2. Varredura

Um início com o sequenciador livre trava a máscara de `MASK` e percorre os canais marcados, do menor número ao maior. Para cada canal o sequenciador mantém o comando válido até o núcleo erguer o ready, espera a resposta com o número de canal pedido e entrega a amostra ao registrador do canal. O primeiro comando da varredura leva `startofpacket` e o último leva `endofpacket`.

O núcleo ergue o ready por um ciclo ao fim da conversão, junto da resposta ou antes dela. Uma resposta sem comando aceito, ou com outro número de canal, é ignorada. Uma varredura de máscara vazia termina sem comando, com `DONE` ligado.

Uma varredura em curso não é interrompida. Mudar `MASK` durante a varredura vale só para a seguinte, e o núcleo que nunca responde deixa `BUSY` em 1 até o reset do periférico.

### 4.3. Taxa de varredura

Com `CONTINUOUS` e `ENABLE` ligados, uma varredura começa a cada `PERIOD` ciclos de `i_clk`, ou seja, na frequência

$$f_{\text{varredura}} = \frac{f_{\text{clk}}}{\text{PERIOD}}$$

O primeiro início sai logo que o modo contínuo é ligado. Com um período menor que a duração da varredura, as varreduras se seguem sem intervalo e `LATE` fica ligado. `PERIOD` igual a 0 ou a 1 tem o mesmo efeito. O período de reset é `clk_freq / scan_freq`, nunca menor que 1.

### 4.4. Interrupção

`o_irq` é de nível e vale `DONE` e `IRQ`. Escrever 1 no bit `DONE` de `STATUS` a baixa.

## 5. Núcleo do conversor no Quartus

### 5.1. Arquivos

| Arquivo | Papel |
| :--- | :--- |
| `src/ADC/soc/max10_adc.vhd` | Registradores, período e interrupção |
| `src/ADC/soc/max10_adc_sequencer.vhd` | Sequenciador da varredura, com a interface Avalon-ST |
| `src/ADC/soc/max10_adc_consts.vhd` | Endereços, bits e número de canais |
| `src/ADC/max10/max10_adc_ip.vhd` | Instância fina do IP gerado, como `component` |
| `src/ADC/max10/max10_adc_pll.v` | PLL de 10 MHz do conversor, megafunção `altpll` |
| `src/ADC/max10/max10_adc_shell.vhd` | Topo estrutural da placa: PLL, IP e periférico |
| `src/ADC/max10/ip/max10_adc_core.tcl` | Script do Platform Designer que cria o sistema do IP |
| `src/ADC/max10/ip/generate.sh` | Gera o IP com `qsys-script` e `qsys-generate` |

### 5.2. Geração do IP

O IP é o núcleo `altera_modular_adc` na variante autônoma (`CORE_VAR` 3), que expõe só as interfaces Avalon-ST de comando e resposta, mais o clock, o reset e o clock do PLL com o sinal de travamento. O script usa o primeiro bloco ADC, o clock do conversor de 10 MHz, 1 MHz de taxa de amostragem, os canais 1 a 8 e o sensor de temperatura.

```bash
QUARTUS_ROOTDIR=/opt/altera_lite/25.1std/quartus src/ADC/max10/ip/generate.sh build/adc-ip
```

A saída é `build/adc-ip/max10_adc_core/synthesis/max10_adc_core.qip`, que o projeto Quartus inclui com `QIP_FILE`. O Quartus Prime Lite 25.1 gera o IP em VHDL no topo e Verilog nos submódulos.

### 5.3. Primitivas de fabricante

O IP gerado e a megafunção `altpll` não têm entidade visível ao VHDL do projeto, e entram como `component`, no padrão do `sld_virtual_jtag`. O `max10_adc_ip.vhd` declara e instancia o componente `max10_adc_core`, com o nome e as portas que o gerador escreve. O `max10_adc_pll.v` instancia a `altpll` em Verilog, porque a mesma instanciação em VHDL deixa os contadores do PLL em zero no `quartus_map` 25.1 (erro 14024), e o `max10_adc_shell.vhd` o instancia como `component`.

Os nomes `max10_adc_core` e `max10_adc_pll` não constam da lista `vendor_primitives.yaml` do `riscv-tools` (hoje `altsyncram`, `sld_virtual_jtag` e `sdram_platform_pll`), e por isso os arquivos da pasta `max10/` ficam fora da análise do GHDL e fora das regras de estilo dos componentes.

### 5.4. Verificação de síntese

O script `tests/quartus/check_max10_adc_synthesis.sh` gera o IP e roda a síntese do `max10_adc_shell` para o `10M50DAF484C7G`, sem atribuição de pinos.

```bash
tests/quartus/check_max10_adc_synthesis.sh /tmp/max10-adc-synth
```

A síntese usa um bloco ADC e um PLL. O fitter também conclui, com a ressalva de que nenhum pino tem atribuição.

## 6. Ligação à DE10-Lite

### 6.1. Entradas analógicas

O manual da DE10-Lite (seção 3.7, figura 3-20) liga as entradas analógicas ao bloco ADC1 do MAX 10 pelo barramento `ADC1IN[8..1]`, vindo do circuito de entrada analógica que reduz os 5,0 V do Arduino aos 2,5 V do conversor. Os pinos `ADC1IN` são pinos analógicos dedicados do dispositivo, o manual não lhes dá número de pino do FPGA e eles não têm atribuição no `.qsf`.

| Entrada Arduino | Barramento do manual | Pino do dispositivo | Canal do núcleo | Mapeamento |
| :--- | :--- | :--- | ---: | :--- |
| A0 (`ADC_IN0`) | `ADC_IN[0]` | `ADC1IN1` | 1 | Inferido da ordem dos barramentos `ADC_IN[7..0]` e `ADC1IN[8..1]` da figura 3-20 |
| A1 (`ADC_IN1`) | `ADC_IN[1]` | `ADC1IN2` | 2 | idem |
| A2 (`ADC_IN2`) | `ADC_IN[2]` | `ADC1IN3` | 3 | idem |
| A3 (`ADC_IN3`) | `ADC_IN[3]` | `ADC1IN4` | 4 | idem |
| A4 (`ADC_IN4`) | `ADC_IN[4]` | `ADC1IN5` | 5 | idem |
| A5 (`ADC_IN5`) | `ADC_IN[5]` | `ADC1IN6` | 6 | idem |
| Cabeçalho 1x2, não montado | `ADC_IN[6]`, `ADC_IN[7]` | `ADC1IN7`, `ADC1IN8` | 7, 8 | idem |

O núcleo gerado para a DE10-Lite que acompanha o Quartus (programa universitário, seis canais, máscara de pinos 63) usa os canais 1 a 6 para essas seis entradas, o que confirma o mapeamento. A entrada dedicada `ANAIN1` (canal 0) não consta do manual da placa como ligada a nada, e o uso do canal 0 não está confirmado.

O clock do conversor é o `ADC_CLK_10`, pino `N5`, 3,3-V LVTTL, 10 MHz (seção 3.2, tabela 3-2), ligado aos PLL1 e PLL3 do FPGA. A fonte de referência do conversor (`refsel`) é a do núcleo do programa universitário, e o manual não a especifica; não confirmado.

### 6.2. Conversão para tensão

O resultado de 12 bits representa 0 a 2,5 V na entrada do conversor, e o circuito de entrada divide a tensão do Arduino por 2 (seção 5.6 do manual). A tensão no pino do Arduino é

$$V_{\text{pino}} = \frac{\text{DATA}}{4095} \times 5{,}0\ \text{V}$$

## 7. Exemplo em C

O programa varre A0 a A5 uma vez, espera o fim e imprime a tensão de cada pino em milivolts. A base da janela do periférico vem da plataforma.

```c
#include <stdint.h>
#include <stdio.h>

#define ADC_BASE       0x10003000u  /* base da janela do periférico na plataforma */
#define ADC_REG(n)     (*(volatile uint32_t *)(ADC_BASE + 4u * (n)))
#define ADC_CTRL       ADC_REG(0)
#define ADC_MASK       ADC_REG(1)
#define ADC_PERIOD     ADC_REG(2)
#define ADC_STATUS     ADC_REG(3)
#define ADC_CHANNEL(n) ADC_REG(8u + (n))

#define CTRL_ENABLE    (1u << 0)
#define CTRL_START     (1u << 3)
#define ST_BUSY        (1u << 0)
#define ST_DONE        (1u << 1)
#define CH_DATA        0xFFFu
#define CH_VALID       (1u << 12)

#define FIRST_CHANNEL  1u            /* A0 é o canal 1 do núcleo (ADC1IN1) */
#define ARDUINO_PINS   6u
#define SCAN_TRIES     100000u

static uint32_t arduino_mask(void) {
    return ((1u << ARDUINO_PINS) - 1u) << FIRST_CHANNEL;
}

static int scan_once(void) {
    ADC_MASK = arduino_mask();
    ADC_CTRL = CTRL_ENABLE;
    ADC_STATUS = ST_DONE;                 /* limpa o fim da varredura anterior */
    ADC_CTRL = CTRL_ENABLE | CTRL_START;

    for (uint32_t i = 0; i < SCAN_TRIES; i++) {
        uint32_t status = ADC_STATUS;
        if (!(status & ST_BUSY) && (status & ST_DONE)) {
            return 0;
        }
    }
    return -1;
}

int main(void) {
    if (scan_once() != 0) {
        puts("o ADC nao respondeu");
        return 1;
    }

    for (uint32_t pin = 0; pin < ARDUINO_PINS; pin++) {
        uint32_t word = ADC_CHANNEL(FIRST_CHANNEL + pin);
        if (!(word & CH_VALID)) {
            continue;
        }
        /* 12 bits para 0 a 2,5 V no conversor, o dobro no pino do Arduino. */
        uint32_t millivolts = (word & CH_DATA) * 5000u / 4095u;
        printf("A%u = %u mV\n", (unsigned)pin, (unsigned)millivolts);
    }
    return 0;
}
```

Para amostrar sem parar, grave `PERIOD` com `clk_freq / frequência` e `CTRL` com `ENABLE`, `CONTINUOUS` e `IRQ`; a rotina de interrupção lê os registradores de canal, que limpam o `VALID`, e escreve `ST_DONE` em `STATUS`. Para ler a temperatura do chip, marque o bit 17 em `MASK`; a conversão do valor do sensor em graus Celsius vem do guia do conversor do MAX 10, que não está em `Docs` (não confirmado).

## 8. Verificação

Os testes de entidade rodam o periférico contra um modelo comportamental do núcleo, com resposta junto do ready e um ciclo depois dele, e o sequenciador sozinho contra respostas conduzidas à mão. Cobrem os valores de reset, a leitura dos registradores, a ordem dos canais com `startofpacket` e `endofpacket`, os flags `VALID` e `OVERRUN`, a leitura que os limpa, o período exato entre varreduras, `LATE`, a varredura de máscara vazia, o início sem `ENABLE` e a interrupção.

A prova formal do sequenciador usa o ready e a resposta livres e prova que cada comando é do menor canal ainda sem amostra da máscara travada no início, que o comando fica válido até o ready, que uma amostra só vem da resposta do canal pedido a um comando aceito e que o fim da varredura vem com todos os canais amostrados, com mutantes de cada regra. O detalhe está em [formal.md](../formal/formal.md).

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

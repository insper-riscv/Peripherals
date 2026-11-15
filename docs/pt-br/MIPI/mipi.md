# Receptor de câmera MIPI CSI-2

🌐 [Português](../../pt-br/MIPI/mipi.md) · [English](../../en/MIPI/mipi.md)

## 1. Referência

A Arduino MKR Vidor 4000 (ABX00022) tem um conector de câmera MIPI ligado a pinos LVDS do FPGA 10CL016YU256C8G (Cyclone 10 LP). O esquemático da placa termina cada par diferencial com um resistor de 100 ohms (R38, R39 e R40) e não traz rede de decodificação dos estados de baixo consumo do D-PHY. Os pinos abaixo vêm do catálogo de placas do Insper-RISC-V (`boards/mkr-vidor-4000/pins.yaml`), que os leu do arquivo de pinos do projeto de referência da Arduino (`vidor_s_pins.qsf`, VidorBitstream) e os conferiu com o esquemático.

| Sinal | Pino | Padrão elétrico | Sentido, visto do FPGA | Função |
| :--- | :--- | :--- | :--- | :--- |
| `iMIPI_D[0]` e `iMIPI_D[0](n)` | L2 e L1 | LVDS | entrada | Lane de dados 0 |
| `iMIPI_D[1]` e `iMIPI_D[1](n)` | J2 e J1 | LVDS | entrada | Lane de dados 1 |
| `iMIPI_CLK` e `iMIPI_CLK(n)` | M2 e M1 | LVDS | entrada | Lane de clock |
| `bMIPI_SDA` e `bMIPI_SCL` | P2 e P1 | 2,5 V | bidirecional | Controle I2C da câmera (outro periférico) |
| `bMIPI_GP[0]` e `bMIPI_GP[1]` | M7 e P9 | 3,3 V LVTTL | bidirecional | Uso geral do conector, sem função fixada aqui |

O comportamento esperado do lado do FPGA (duas lanes, amostragem nas duas bordas do clock da lane de clock, byte de sincronismo `0xB8` precedido de zeros, imagem RAW8 de tipo de dado 42 e controle por I2C) segue o IP `MIPI_RX_ST` do VidorBitstream, lido como referência de fatos de hardware sem cópia de código. O formato dos pacotes (cabeçalho, ECC e CRC-16) é o do MIPI CSI-2, e a camada física é a do MIPI D-PHY, ambas especificações do MIPI Alliance. Os fatos da placa vêm do datasheet e do esquemático ABX00022 da Arduino.

## 2. O que é

O periférico recebe de uma, duas ou quatro lanes do D-PHY, em alta velocidade, os pacotes do CSI-2. Ele acha o byte de sincronismo de cada lane, alinha os bytes das lanes, confere o ECC do cabeçalho e o CRC-16 de cada linha, separa a carga útil e grava um recorte do quadro numa memória de dois clocks que o processador lê pelo barramento. Os bytes da carga útil entram na memória como chegam (RAW8, por exemplo, fica em bytes de Bayer); a conversão de cor é do software.

O periférico recebe a entrada já amostrada nas duas bordas do clock da câmera, dois bits por lane e por ciclo, o que é função do registrador DDR de entrada da plataforma (`mipi_ddr_in`, com um modelo de simulação e um invólucro do megafunction `altddio_in`). Ele não decodifica os estados de baixo consumo do D-PHY e não configura a câmera, que o software programa por I2C com o periférico I2C da plataforma.

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `lanes` | 2 | Quantidade de lanes de dados, 1, 2 ou 4 |
| `fb_line_bytes` | 256 | Bytes por linha da memória do quadro, múltiplo de 4 |
| `fb_lines` | 128 | Linhas da memória do quadro |
| `default_dt` | 42 (`0x2A`, RAW8) | Tipo de dado das linhas guardadas depois do reset |

A memória tem $\lceil fb\_line\_bytes \cdot fb\_lines / 4 \rceil$ palavras de 32 bits. Uma linha mais larga que `fb_line_bytes` perde os bytes finais, e as linhas depois da última de `fb_lines` são descartadas. Um quadro VGA RAW8 de $640 \times 480$ ocupa cerca de 300 kB e não cabe nos blocos de memória do 10CL016, então o recorte e o passo de linhas escolhem a parte guardada.

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset síncrono, ativo em 1 |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura do processador |
| `i_address` | entrada | Endereço de palavra de 4 bits |
| `i_data_in`, `o_data_out` | entrada, saída | Dado de escrita e de leitura (`word_t`); os registradores usam os 32 bits baixos |
| `o_irq` | saída | Interrupção em nível, ativa em 1 |
| `i_mipi_clk` | entrada | Clock da lane de clock (`iMIPI_CLK`), assíncrono em relação a `i_clk` |
| `i_mipi_early` | entrada | Bit mais antigo do par de cada lane, amostrado por `mipi_ddr_in` (um bit por lane) |
| `i_mipi_late` | entrada | Bit mais novo do par de cada lane, amostrado por `mipi_ddr_in` (um bit por lane) |

A lane $n$ do periférico é a lane $n$ do conector, e o byte $k$ de um pacote vem da lane $k \bmod lanes$.

## 4. Camada de lane

Cada lane guarda os últimos 24 bits recebidos. Com a lane livre, ela procura o byte `0xB8` (bits `00011101` enviados do menos significativo) precedido de pelo menos 8 bits em zero, nas duas fases possíveis do byte em relação ao par de bits. Achado o sincronismo, a lane entrega um byte alinhado a cada quatro ciclos de `i_mipi_clk`, e só se destrava quando a camada de pacotes manda. A busca de sincronismo não roda durante um pacote, de modo que um `0xB8` dentro dos dados não afeta o alinhamento.

## 5. Camada de pacotes

### 5.1. Cabeçalho

O cabeçalho tem 4 bytes: identificador de dado (canal virtual nos bits 7 e 6, tipo de dado nos bits 5 a 0), contagem de palavras de 16 bits (byte baixo primeiro) e ECC de 6 bits. O ECC é o de Hamming do CSI-2 sobre os 24 primeiros bits, e um cabeçalho com ECC diferente do calculado é descartado, sem correção de bit, porque o tamanho do pacote é desconhecido. O periférico ignora o canal virtual e usa só o tipo de dado.

### 5.2. Tipos de pacote

| Tipo de dado | Pacote | Tratamento |
| :--- | :--- | :--- |
| 0x00 | Início de quadro (curto) | Começa a captura pedida |
| 0x01 | Fim de quadro (curto) | Termina a captura |
| 0x02 e 0x03 | Início e fim de linha (curtos) | Ignorados |
| 0x04 a 0x0F | Outros curtos | Ignorados |
| 0x10 a 0x3F | Longos | Guardados se o tipo de dado é o escolhido em `CONFIG`, ignorados nos outros |

Um pacote curto tem só o cabeçalho, e a contagem de palavras leva o dado de 16 bits (número do quadro ou da linha). Um pacote longo traz a carga útil de `contagem de palavras` bytes e, depois dela, o CRC-16 do CSI-2.

### 5.3. CRC

O CRC-16 é o de polinômio $x^{16} + x^{12} + x^5 + 1$, valor inicial `0xFFFF`, bits do menos significativo, calculado só sobre a carga útil e enviado com o byte baixo primeiro. Uma linha com CRC errado é guardada mesmo assim e conta no contador de erros de CRC.

### 5.4. Fim do pacote e defasagem

O tamanho do pacote vem do cabeçalho, e no fim dele as lanes se destravam e a busca de sincronismo recomeça. O último grupo de um pacote pode ter menos bytes que lanes. A defasagem aceita entre as lanes é de até 3 ciclos de `i_mipi_clk`. Se só parte das lanes se alinha e as demais não se alinham em 8 ciclos, a busca recomeça.

## 6. Captura de um quadro

Com o receptor habilitado, o software escreve `START`, e a captura espera um pacote de início de quadro. Cada linha do tipo de dado escolhido entra na memória a partir do canto superior esquerdo, uma linha de memória por linha guardada, e o pacote de fim de quadro termina a captura. O passo de linhas $s$ guarda uma linha a cada $s$ entre as linhas do tipo escolhido, começando pela primeira.

| Situação | Resultado |
| :--- | :--- |
| Fim de quadro com ao menos uma linha guardada | Quadro pronto (`READY`) e contador de quadros somado |
| Início de quadro no meio da captura, ou fim de quadro sem linha guardada | Captura encerrada sem quadro pronto, com `ERROR` |
| Linha com bytes além de `fb_line_bytes`, ou linha além de `fb_lines` | Bytes e linhas descartados, somados no contador de descartes de `ERRORS` |
| Cabeçalho com ECC errado | Pacote perdido, somado no contador de ECC de `ERRORS`, com `ERROR` |
| Linha com CRC errado | Linha guardada, somada no contador de CRC de `ERRORS`, com `ERROR` |

A configuração (`CONFIG`) só aceita escrita com a captura parada. Escrever 0 em `ENABLE` encerra a captura e reinicia o domínio do clock da câmera na borda seguinte de `i_mipi_clk`.

## 7. Mapa de registradores

Os acessos são de 32 bits, e o endereço é de palavra. Um endereço fora do mapa lê zero e ignora a escrita.

| Endereço | Registrador | Acesso | Reset | Descrição |
| :--- | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | L/E | 0 | Controle |
| 1 | `STATUS` | L/E (escrever 1 limpa) | 0 | Estado |
| 2 | `FRAME_COUNT` | L | 0 | Quadros completos capturados desde o reset |
| 3 | `CONFIG` | L/E | `0x012A` | Tipo de dado e passo de linhas |
| 4 | `GEOMETRY` | L | pelos generics | Linhas nos bits 31 a 16 e bytes por linha nos bits 15 a 0 |
| 5 | `RD_ADDR` | L/E | 0 | Ponteiro de palavra da leitura da memória do quadro |
| 6 | `RD_DATA` | L | 0 | Palavra apontada, com incremento do ponteiro a cada leitura |
| 7 | `LAST_FRAME` | L | 0 | Linhas guardadas no último quadro (bits 15 a 0) e contagem de palavras da última linha (bits 31 a 16) |
| 8 | `ERRORS` | L/E (escrever zera) | 0 | Contadores de ECC (bits 7 a 0), CRC (bits 15 a 8) e descartes (bits 23 a 16), saturados em 255 |
| 9 | `INFO` | L | pelos generics | Quantidade de lanes nos bits 3 a 0 |

### 7.1. `CTRL`

| Bit | Nome | Descrição |
| :--- | :--- | :--- |
| 0 | `START` | Escrever 1 com `ENABLE` em 1 e a captura parada pede um quadro; lê sempre 0 |
| 1 | `FRAME_IE` | Interrupção enquanto `READY` vale 1 |
| 2 | `ERROR_IE` | Interrupção enquanto `ERROR` vale 1 |
| 3 | `ENABLE` | Habilita o receptor; em 0, o domínio do clock da câmera fica em reset |

`ENABLE` deve ser escrito antes de `START`, em acessos separados.

### 7.2. `STATUS`

| Bit | Nome | Descrição |
| :--- | :--- | :--- |
| 0 | `BUSY` | Captura em andamento, da escrita de `START` ao fim de quadro |
| 1 | `READY` | Quadro pronto; permanece em 1 até escrever 1 no bit ou iniciar outra captura |
| 2 | `ERROR` | Erro de ECC, de CRC ou quadro incompleto; permanece em 1 até escrever 1 no bit |
| 3 | `SEEN` | Ao menos um cabeçalho com ECC correto chegou desde que `ENABLE` foi escrito em 1 |

### 7.3. `CONFIG`

| Bits | Campo | Descrição |
| :--- | :--- | :--- |
| 5:0 | `dt` | Tipo de dado das linhas guardadas |
| 15:8 | `y_step` | Passo de linhas; zero vale um |

### 7.4. Leitura da memória do quadro

Cada palavra de `RD_DATA` tem quatro bytes de memória, o byte de endereço mais baixo nos bits 7 a 0. A palavra $w$ cobre os bytes $4w$ a $4w + 3$ do quadro, e a linha $r$ começa na palavra $r \cdot fb\_line\_bytes / 4$. Escrever em `RD_ADDR` um valor maior que a última palavra é ignorado, e a leitura da última palavra leva o ponteiro de volta a 0.

## 8. Interrupção

$$o\_irq = (FRAME\_IE \wedge READY) \vee (ERROR\_IE \wedge ERROR)$$

A saída é de nível e cai quando o software escreve 1 no bit correspondente de `STATUS`.

## 9. Clocks e restrições

`i_clk` e `i_mipi_clk` são assíncronos entre si. O pedido de captura e a habilitação atravessam por sincronizadores de dois estágios no sentido do clock da câmera, e o fim da captura, os erros e o estado `SEEN` atravessam no sentido contrário, os eventos por toggle. O resultado da captura, o tipo de dado e o passo de linhas são vetores parados quando o toggle os revela, e o arquivo de restrições da placa deve cortá-los com `set_false_path`. O clock do sistema deve ser mais rápido que um doze avos de `i_mipi_clk`, para que dois erros seguidos não se confundam num toggle só.

A taxa de cada lane é o dobro da frequência de `i_mipi_clk`, e a lógica do periférico roda em `i_mipi_clk`. A frequência máxima que a lógica fecha na placa é assunto de análise de temporização na plataforma.

## 10. Limites

| Item | Situação |
| :--- | :--- |
| Estados de baixo consumo do D-PHY | Não são vistos; o receptor depende de zeros e de `0xB8` para achar o início de cada rajada e do tamanho do pacote para achar o fim |
| Correção de ECC | Não há; um cabeçalho com ECC errado derruba o pacote |
| Canal virtual | Ignorado |
| Formatos | Os bytes da carga útil entram sem conversão; RAW10, RAW12 e formatos compactados ficam empacotados na memória |
| Quadro inteiro | Só o recorte do canto superior esquerdo, com passo de linhas; a memória é de blocos do FPGA |
| Pacote interrompido no meio | O receptor espera o tamanho do cabeçalho; `ENABLE` em 0 reinicia |
| Capacidade elétrica dos pinos | O D-PHY em alta velocidade chega a pinos LVDS do FPGA, como no projeto de referência da Arduino; a compatibilidade dos níveis com a câmera usada não foi verificada em bancada |

## 11. Exemplo em C

O programa habilita o receptor, captura um quadro e lê a primeira linha. A base da janela vem do cabeçalho gerado a partir do `platform.yaml`.

```c
#include <stdint.h>
#include <stdio.h>

enum { MIPI_CTRL, MIPI_STATUS, MIPI_FRAME_COUNT, MIPI_CONFIG, MIPI_GEOMETRY,
       MIPI_RD_ADDR, MIPI_RD_DATA };

enum : uint32_t {
    CTRL_START = 1u << 0,
    CTRL_ENABLE = 1u << 3,
    STAT_BUSY = 1u << 0,
    STAT_READY = 1u << 1,
};

void capture_first_line(volatile uint32_t *mipi) {
    mipi[MIPI_CTRL] = CTRL_ENABLE;
    mipi[MIPI_CTRL] = CTRL_ENABLE | CTRL_START;
    while (mipi[MIPI_STATUS] & STAT_BUSY) {
    }
    if (!(mipi[MIPI_STATUS] & STAT_READY)) {
        return;
    }
    uint32_t line_bytes = mipi[MIPI_GEOMETRY] & 0xFFFFu;
    mipi[MIPI_RD_ADDR] = 0;
    for (uint32_t word = 0; word < line_bytes / 4; word++) {
        printf("%08x\n", (unsigned)mipi[MIPI_RD_DATA]);
    }
    mipi[MIPI_STATUS] = STAT_READY;
}
```

## 12. Verificação

Os testes de entidade cobrem a lane (as duas fases do byte, todos os deslocamentos de bit, preâmbulo, `0xB8` nos dados e destravamento), a camada de pacotes (pacotes curtos, cargas úteis de tamanhos de 0 a 33 bytes com 1, 2 e 4 lanes, CRC e ECC errados, o vetor de referência do ECC, defasagem entre as lanes e recomeço da busca), o controle da captura (quadro, recorte, passo de linhas, filtro de tipo de dado, abortos e eventos) e os registradores (estado, contadores, bloqueio da configuração e ponteiro). O teste do bloco completo gera quadros CSI-2 em bits, com defasagem e fase diferentes a cada pacote, e os lê pelo barramento com 1, 2 e 4 lanes. Os testes são de simulação, e o periférico não foi exercitado numa câmera real. O sistema de verificação formal do repositório não tem provas para este periférico.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

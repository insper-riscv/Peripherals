# Controlador de cartão SD no modo nativo

🌐 [Português](../../pt-br/SD/sd_native.md) · [English](../../en/SD/sd_native.md)

## 1. O que é

Periférico de barramento que conduz um cartão SD ou micro SD pelo modo nativo, com uma ou quatro linhas de dados, o modo em que o cartão alcança a sua taxa máxima de transferência. O software escreve o argumento e o comando, o periférico envia o quadro de 48 bits com CRC7, recebe e confere a resposta e, quando o comando leva um bloco, transfere os 512 bytes entre o cartão e um buffer de bloco com o CRC16 de cada linha. O modo SPI do mesmo cartão está em [sd_spi.md](sd_spi.md).

O periférico é composto por sete blocos.

| Bloco | Função |
| :--- | :--- |
| `sd_clock_gen` | Gera `SD_CLK` por divisor e os pulsos que antecedem cada borda; o clock só roda sob pedido |
| `sd_cmd` | Controle da linha `CMD`: envia o comando, recebe as respostas curta (48 bits) e longa (136 bits), confere CRC7, índice e bit de fim, e espera o fim do ocupado em `DAT0` |
| `sd_data` | Controle das linhas `DAT[3:0]`: lê ou escreve o bloco de 512 bytes com uma ou quatro linhas, calcula e confere o CRC16 de cada linha, recebe o estado de CRC e espera o fim do ocupado |
| `sd_crc7` | Registrador serial do CRC7 de polinômio $x^7 + x^3 + 1$, usado pelo `sd_cmd` |
| `sd_crc16` | Registrador serial do CRC16 de polinômio $x^{16} + x^{12} + x^5 + 1$, uma instância por linha de dados |
| `sd_block_buffer` | Memória de 128 palavras de 32 bits com uma porta de escrita e uma de leitura, implementada em memória de bloco |
| `sd_native` | Topo com os registradores, as marcas persistentes, a janela do buffer, a sincronização das entradas e a interrupção |

## 2. Pinos e placas

O socket da DE0-CV e o da DE2-115 ligam o cartão ao FPGA em 3,3 V, com as quatro linhas de dados, o comando e o clock. O manual da DE0-CV (seção 3.8) diz que o socket oferece os modos SPI e SD de 4 bits, e o da DE2-115 (seção 4.19) lista os mesmos sinais. As placas não têm pino de detecção de cartão (a DE2-115 tem apenas o de proteção contra escrita, `SD_WP_N`).

| Porta do periférico | Sentido | Função | Pino da DE0-CV | Pino da DE2-115 |
| :--- | :--- | :--- | :--- | :--- |
| `o_sd_clk` | saída | Clock do cartão | `SD_CLK` (`PIN_H11`) | `SD_CLK` (`PIN_AE13`) |
| `o_sd_cmd`, `o_sd_cmd_oe`, `i_sd_cmd` | saída, habilitação, entrada | Comando e resposta | `SD_CMD` (`PIN_B11`) | `SD_CMD` (`PIN_AD14`) |
| `o_sd_dat(0)`, `o_sd_dat_oe(0)`, `i_sd_dat(0)` | saída, habilitação, entrada | Dado 0, que também acusa ocupado | `SD_DATA0` (`PIN_K9`) | `SD_DAT[0]` (`PIN_AE14`) |
| `o_sd_dat(1)`, `o_sd_dat_oe(1)`, `i_sd_dat(1)` | saída, habilitação, entrada | Dado 1 | `SD_DATA1` (`PIN_D12`) | `SD_DAT[1]` (`PIN_AF13`) |
| `o_sd_dat(2)`, `o_sd_dat_oe(2)`, `i_sd_dat(2)` | saída, habilitação, entrada | Dado 2 | `SD_DATA2` (`PIN_E12`) | `SD_DAT[2]` (`PIN_AB14`) |
| `o_sd_dat(3)`, `o_sd_dat_oe(3)`, `i_sd_dat(3)` | saída, habilitação, entrada | Dado 3 | `SD_DATA3` (`PIN_C11`) | `SD_DAT[3]` (`PIN_AC14`) |

O topo da plataforma liga cada pino bidirecional ao seu trio de portas com um buffer tristate, de modo que o pino vale o valor de saída quando a habilitação vale 1 e fica em alta impedância quando vale 0. Com uma linha de dados só `DAT0` é habilitada, e as demais ficam como entradas.

$$ \text{pino} = \begin{cases} \text{o\_sd\_cmd} & \text{se o\_sd\_cmd\_oe} = 1 \\ Z & \text{caso contrário} \end{cases} $$

## 3. Parâmetros e portas

| Parâmetro | Padrão | Significado |
| :--- | ---: | :--- |
| `clock_hz` | 50000000 | Frequência do clock do módulo, em hertz |
| `init_clk_hz` | 400000 | Frequência de `SD_CLK` depois do reset; a identificação do cartão exige no máximo 400 kHz |
| `default_timeout` | 2500000 | Valor de `TIMEOUT` depois do reset, em clocks do cartão |
| `input_sync_stages` | 1 | Flip-flops em série nas linhas de entrada; cada estágio a mais exige um divisor mínimo maior |

O divisor de reset vale

$$ \text{DIVIDER}_{reset} = \left\lceil \frac{\text{clock\_hz}}{2 \cdot \text{init\_clk\_hz}} \right\rceil - 1 $$

e a frequência do clock do cartão é

$$ f_{SD\_CLK} = \frac{\text{clock\_hz}}{2 \cdot (\text{DIVIDER} + 1)} $$

Com `clock_hz` de 50 MHz, o divisor 0 dá os 25 MHz do modo de velocidade padrão. A leitura das linhas de entrada usa um único estágio de registro, porque o cartão muda os dados logo depois da borda de subida de `SD_CLK` e o periférico os amostra na borda de subida seguinte, mais de meio período depois. Com `input_sync_stages` igual a $n$, o divisor mínimo passa a ser $n - 1$.

As portas do barramento são `i_clk`, `i_rst` (síncrono, nível alto), `i_write`, `i_read`, `i_address` (4 bits, endereço de palavra), `i_data_in`, `o_data_out` e `o_irq`, mais as portas de pino da seção 2. Os registradores têm 32 bits e a janela do bloco ocupa 13 palavras.

## 4. Registradores

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | ---: | :--- |
| 0 | `ARG` | R/W | 0 | Argumento de 32 bits do próximo comando |
| 1 | `CMD` | R/W | 0 | A escrita inicia um comando (bits abaixo); a leitura devolve o último valor aceito |
| 2 | `RESP0` | R | 0 | Resposta curta, os 32 bits do argumento (R1, R3, R6, R7); resposta longa, bits 39 a 8 do CID ou CSD |
| 3 | `RESP1` | R | 0 | Resposta curta, bits 5 a 0 com o índice da resposta; resposta longa, bits 71 a 40 |
| 4 | `RESP2` | R | 0 | Resposta longa, bits 103 a 72 |
| 5 | `RESP3` | R | 0 | Resposta longa, bits 127 a 104 nos bits 23 a 0 |
| 6 | `STATUS` | R/W1C | `0xF20` com as linhas em repouso | Estado e marcas de fim (tabela abaixo) |
| 7 | `ERROR` | R/W1C | 0 | Erros persistentes (tabela abaixo) |
| 8 | `CONTROL` | R/W | 0 | Clock, largura do barramento e habilitação das interrupções |
| 9 | `DIVIDER` | R/W | seção 3 | Bits 15 a 0, divisor de `SD_CLK`; vale a partir do próximo meio período |
| 10 | `TIMEOUT` | R/W | `default_timeout` | Bits 23 a 0, prazo de espera por dado e por ocupado, em clocks do cartão |
| 11 | `DATA` | R/W | 0 | Palavra do buffer apontada por `PTR`; cada leitura ou escrita avança `PTR` |
| 12 | `PTR` | R/W | 0 | Bits 6 a 0, palavra do buffer apontada; a escrita aponta a palavra e dá a volta depois da 127 |

Bits de `CMD`. O quadro do comando usa o índice, o argumento de `ARG` e o CRC7 calculado pelo periférico.

| Bits | Nome | Significado |
| ---: | :--- | :--- |
| 5 a 0 | `INDEX` | Índice do comando |
| 7 a 6 | `RESPONSE` | Formato esperado, 0 nenhuma, 1 curta com CRC7 e índice conferidos (R1, R1b, R6, R7), 2 curta sem conferência (R3), 3 longa de 136 bits (R2) |
| 8 | `WAIT_BUSY` | Depois da resposta, espera `DAT0` voltar a 1 (R1b) |
| 9 | `DATA_EN` | O comando leva um bloco de 512 bytes, transferido pelo controle de dados |
| 10 | `DATA_WRITE` | Sentido do bloco, 0 lê do cartão para o buffer e 1 escreve do buffer no cartão |

Uma escrita em `CMD` com um comando ou uma transferência em andamento é recusada e marca `DROPPED` em `ERROR`. Bits de `STATUS`; escrever 1 num bit W1C o limpa, e um evento novo no mesmo ciclo tem prioridade sobre a limpeza.

| Bit | Nome | Acesso | Significado |
| ---: | :--- | :--- | :--- |
| 0 | `CMD_BUSY` | R | Há um comando em andamento |
| 1 | `DATA_BUSY` | R | Há uma transferência de bloco em andamento ou à espera da resposta do comando |
| 2 | `CMD_DONE` | W1C | O comando terminou, com ou sem erro; um novo comando limpa a marca |
| 3 | `DATA_DONE` | W1C | A transferência terminou, com ou sem erro; também sobe quando uma resposta recusada cancela o bloco |
| 4 | `CARD_BUSY` | R | `DAT0` está em nível baixo, o cartão está ocupado |
| 5 | `CMD_LINE` | R | Nível da linha `CMD` |
| 11 a 8 | `DAT_LINES` | R | Níveis de `DAT3` a `DAT0` |
| 18 a 16 | `WRITE_TOKEN` | R | Estado de CRC devolvido pelo cartão na última escrita de bloco |

Bits de `ERROR`, todos W1C.

| Bit | Nome | Origem |
| ---: | :--- | :--- |
| 0 | `CMD_TIMEOUT` | A resposta não chegou em 64 clocks, ou `DAT0` ficou ocupado além de `TIMEOUT` depois de uma resposta R1b |
| 1 | `CMD_CRC` | O CRC7 da resposta não confere |
| 2 | `CMD_INDEX` | O índice da resposta é diferente do índice do comando |
| 3 | `CMD_FRAME` | O bit de transmissão ou o bit de fim da resposta tem valor errado |
| 4 | `DATA_TIMEOUT` | O bit de início do bloco não chegou em `TIMEOUT` clocks, o estado de CRC não chegou em 16 clocks, ou o ocupado passou de `TIMEOUT` |
| 5 | `DATA_CRC` | O CRC16 de alguma linha do bloco lido não confere |
| 6 | `DATA_FRAME` | O bit de início ou o de fim do bloco, ou o do estado de CRC, tem valor errado |
| 7 | `WRITE_CRC` | O cartão devolveu o estado de CRC 101, erro de CRC nos dados |
| 8 | `WRITE_ERROR` | O cartão devolveu um estado de CRC diferente de 010 e de 101 |
| 9 | `DROPPED` | Uma escrita em `CMD` foi recusada por haver operação em andamento |

Bits de `CONTROL`.

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `CLK_ENABLE` | Mantém `SD_CLK` rodando, para os 74 clocks da inicialização |
| 1 | `WIDE_BUS` | Os blocos usam as quatro linhas; com 0, só `DAT0` |
| 2 | `CMD_IRQ_ENABLE` | Interrupção enquanto `CMD_DONE` vale 1 |
| 3 | `DATA_IRQ_ENABLE` | Interrupção enquanto `DATA_DONE` vale 1 |
| 4 | `ERROR_IRQ_ENABLE` | Interrupção enquanto algum bit de `ERROR` vale 1 |
| 8 | `ABORT` | A escrita de 1 interrompe o comando e a transferência em andamento e solta as linhas; o bit não é guardado |

A saída `o_irq` é de nível e é a soma lógica das três causas habilitadas, e cada uma só cai quando o software limpa a marca correspondente.

## 5. Protocolo

### 5.1. Quadro de comando

O comando tem 48 bits enviados pela linha `CMD`, o mais significativo primeiro, com os bits de `CMD` saindo na borda de descida de `SD_CLK` e o cartão os amostrando na de subida.

| Bits | Campo | Valor |
| ---: | :--- | :--- |
| 47 | Início | 0 |
| 46 | Transmissão | 1, sentido do mestre para o cartão |
| 45 a 40 | Índice | Índice do comando |
| 39 a 8 | Argumento | Conteúdo de `ARG` |
| 7 a 1 | CRC7 | Resto da divisão dos 40 primeiros bits por $x^7 + x^3 + 1$, valor inicial zero |
| 0 | Fim | 1 |

Depois do bit de fim o periférico solta a linha. Passam então 8 clocks antes de o comando terminar, e com `WAIT_BUSY` o periférico ainda espera `DAT0` voltar a 1.

### 5.2. Respostas

A resposta chega pela linha `CMD`, e o periférico espera o bit de início por no máximo 64 clocks depois do comando.

| Formato | Bits | Conteúdo | Conferência |
| :--- | ---: | :--- | :--- |
| R1, R1b, R6, R7 (`RESPONSE` 1) | 48 | Início 0, transmissão 0, índice de 6 bits, argumento de 32 bits, CRC7, fim 1 | CRC7 sobre os 40 primeiros bits, índice igual ao do comando, transmissão e fim |
| R3 (`RESPONSE` 2) | 48 | Início 0, transmissão 0, seis bits em 1, argumento (o OCR), sete bits em 1, fim 1 | Só a transmissão e o fim, pois o CRC7 e o índice não têm valor definido |
| R2 (`RESPONSE` 3) | 136 | Início 0, transmissão 0, seis bits em 1, 120 bits do CID ou CSD, CRC7 do registrador, fim 1 | CRC7 sobre os 120 bits do CID ou CSD, transmissão e fim |

Nas respostas curtas `RESP0` guarda o argumento e `RESP1` guarda o índice nos bits 5 a 0. Na longa, as quatro palavras guardam os bits 127 a 8 do registrador, sem o CRC7 nem o bit de fim.

### 5.3. Bloco de dados

Um bloco tem 512 bytes. Com quatro linhas cada clock leva um nibble, o nibble mais significativo do byte primeiro, com `DAT3` no bit mais significativo do nibble, e cada linha tem o seu CRC16. Com uma linha cada clock leva um bit de `DAT0`.

| Fase | Quatro linhas | Uma linha |
| :--- | :--- | :--- |
| Início | 1 clock com `DAT[3:0]` em 0 | 1 clock com `DAT0` em 0 |
| Dados | 1024 clocks | 4096 clocks |
| CRC16 | 16 clocks, o CRC de cada linha, o bit mais significativo primeiro | 16 clocks de `DAT0` |
| Fim | 1 clock com `DAT[3:0]` em 1 | 1 clock com `DAT0` em 1 |

O CRC16 de cada linha cobre os bits que passaram por ela, com polinômio $x^{16} + x^{12} + x^5 + 1$ e valor inicial zero. O primeiro byte do bloco ocupa os bits 7 a 0 da palavra 0 do buffer, o segundo os bits 15 a 8, e assim por diante.

Na leitura o cartão envia o bloco depois da resposta, e o periférico espera o bit de início por `TIMEOUT` clocks. Na escrita o periférico espera 4 clocks depois da resposta, envia o bloco, solta as linhas e recebe em `DAT0` o estado de CRC, com início 0, três bits e fim 1, até 16 clocks depois do bloco.

| Estado de CRC | Significado | Efeito |
| :--- | :--- | :--- |
| 010 | Bloco aceito | Nenhum erro |
| 101 | Erro de CRC nos dados | `WRITE_CRC` |
| 110 | Erro de gravação | `WRITE_ERROR` |

Depois do estado de CRC o periférico espera 2 clocks e aguarda `DAT0` voltar a 1, o fim da gravação, por no máximo `TIMEOUT` clocks.

### 5.4. Temporização

| Espera | Valor | Uso |
| :--- | ---: | :--- |
| Frequência de identificação | até 400 kHz | Do reset até a escolha da largura e da velocidade |
| Frequência de transferência | até 25 MHz | Divisor 0 com o clock de 50 MHz |
| Clocks antes do CMD0 | pelo menos 74 e 1 ms | O software liga `CLK_ENABLE` pelo tempo necessário |
| Resposta (NCR) | no máximo 64 clocks | Prazo do bit de início da resposta |
| Entre comandos (NCC) | pelo menos 8 clocks | Intervalo que o periférico acrescenta ao fim de cada comando |
| Resposta ao bloco escrito (NWR) | pelo menos 2 clocks | O periférico espera 4 |
| Estado de CRC | 2 clocks depois do bloco | O periférico aceita até 16 |

## 6. Uso pelo software

### 6.1. Sequência de inicialização

A sequência é a da especificação para um cartão SDHC ou SDXC, com `CMD` escrito já com os bits de formato.

| Passo | Ação | Resposta esperada |
| ---: | :--- | :--- |
| 1 | Com `DIVIDER` no valor de reset, ligar `CLK_ENABLE`, esperar 1 ms e desligar | Pelo menos 74 clocks com `CMD` em 1 |
| 2 | CMD0 com argumento 0, sem resposta | Nenhuma |
| 3 | CMD8 com `0x000001AA`, resposta 1 | Eco `0x1AA` em `RESP0` |
| 4 | Repetir CMD55 com argumento 0 (resposta 1) e ACMD41 com `0x40FF8000` (resposta 2) até o bit 31 de `RESP0` valer 1 | Bit 30 (CCS) em 1 para endereço por setor |
| 5 | CMD2 com resposta 3 | CID nas quatro palavras de resposta |
| 6 | CMD3 com resposta 1 | `RESP0` bits 31 a 16 com o RCA |
| 7 | CMD7 com o RCA nos bits 31 a 16 e `WAIT_BUSY` | Cartão no estado de transferência |
| 8 | CMD55 com o RCA e ACMD6 com argumento 2, depois `WIDE_BUS` em `CONTROL` | Quatro linhas de dados |
| 9 | Escrever o divisor de transferência em `DIVIDER` | `SD_CLK` na velocidade final |

### 6.2. Leitura e escrita de um setor

Para ler, o software escreve `ARG` com o número do setor e `CMD` com CMD17, resposta 1 e `DATA_EN`, espera `CMD_DONE` e `DATA_DONE`, confere `ERROR`, aponta `PTR` para 0 e lê 128 palavras de `DATA`. Para escrever, aponta `PTR` para 0, escreve 128 palavras em `DATA`, escreve `ARG` com o setor e `CMD` com CMD24, resposta 1, `DATA_EN` e `DATA_WRITE`, espera as duas marcas e confere `ERROR` e o `WRITE_TOKEN` de `STATUS`. Durante `DATA_BUSY` o software não acessa `DATA`, pois o controle de dados é o dono do buffer. Cada comando de bloco leva um único bloco de 512 bytes.

### 6.3. Exemplo em C

O exemplo inicializa o cartão, lê um setor e o regrava, com C23 e polling. A constante `SD_BASE` recebe o endereço do bloco na plataforma, e `delay_us` é a espera da plataforma.

```c
#include <stdbool.h>
#include <stdint.h>

/* Base do periférico, definida pela plataforma. */
#define SD_BASE ((volatile uint32_t *)0x40000000u)

/* Espera da plataforma, em microssegundos. */
extern void delay_us(uint32_t microseconds);

enum {
    ARG, CMD, RESP0, RESP1, RESP2, RESP3, STATUS, ERROR,
    CONTROL, DIVIDER, TIMEOUT, DATA, PTR
};
enum {
    CMD_DONE = 1u << 2,
    DATA_DONE = 1u << 3,
    TOKEN_SHIFT = 16,
    TOKEN_MASK = 0x7u,
    TOKEN_ACCEPTED = 0x2u
};
enum { CLK_ENABLE = 1u << 0, WIDE_BUS = 1u << 1 };
enum {
    RSP_NONE = 0u << 6, RSP_R1 = 1u << 6, RSP_R3 = 2u << 6, RSP_R2 = 3u << 6,
    WAIT_BUSY = 1u << 8, DATA_EN = 1u << 9, DATA_WRITE = 1u << 10
};

#define SD_FAST_DIVIDER 0u /* 25 MHz com o clock de 50 MHz. */
#define SD_WORDS 128u

/* Espera todos os bits de mask em STATUS. */
static void sd_wait(uint32_t mask)
{
    while ((SD_BASE[STATUS] & mask) != mask) {
    }
}

/* Lê e limpa ERROR; devolve zero quando tudo correu bem. */
static uint32_t sd_take_errors(void)
{
    uint32_t errors = SD_BASE[ERROR];
    SD_BASE[ERROR] = errors;
    return errors;
}

/* Envia um comando e devolve os erros. */
static uint32_t sd_command(uint32_t index, uint32_t argument, uint32_t flags)
{
    SD_BASE[ARG] = argument;
    SD_BASE[CMD] = index | flags;
    sd_wait(CMD_DONE);
    SD_BASE[STATUS] = CMD_DONE;
    return sd_take_errors();
}

/* Envia o CMD55 e depois o comando de aplicação. */
static uint32_t sd_app_command(uint32_t rca, uint32_t index, uint32_t argument,
                               uint32_t flags)
{
    uint32_t errors = sd_command(55, rca << 16, RSP_R1);
    return errors | sd_command(index, argument, flags);
}

/* Inicializa um cartão SDHC e o deixa no estado de transferência com quatro
 * linhas. Devolve true em caso de sucesso. */
bool sd_init(void)
{
    SD_BASE[CONTROL] = CLK_ENABLE; /* 74 clocks ou mais com CMD em 1 */
    delay_us(1000);
    SD_BASE[CONTROL] = 0;

    if (sd_command(0, 0, RSP_NONE) != 0) { /* CMD0 */
        return false;
    }
    if (sd_command(8, 0x1AA, RSP_R1) != 0 || (SD_BASE[RESP0] & 0xFFF) != 0x1AA) {
        return false; /* CMD8 */
    }

    uint32_t ocr = 0;
    for (int attempt = 0; attempt < 1000 && (ocr & 0x80000000u) == 0; attempt++) {
        if (sd_app_command(0, 41, 0x40FF8000u, RSP_R3) != 0) { /* ACMD41 */
            return false;
        }
        ocr = SD_BASE[RESP0];
        delay_us(1000);
    }
    if ((ocr & 0xC0000000u) != 0xC0000000u) { /* pronto e CCS */
        return false;
    }

    if (sd_command(2, 0, RSP_R2) != 0) { /* CMD2, CID em RESP0 a RESP3 */
        return false;
    }
    if (sd_command(3, 0, RSP_R1) != 0) { /* CMD3 */
        return false;
    }
    uint32_t rca = SD_BASE[RESP0] >> 16;
    if (sd_command(7, rca << 16, RSP_R1 | WAIT_BUSY) != 0) { /* CMD7 */
        return false;
    }
    if (sd_app_command(rca, 6, 2, RSP_R1) != 0) { /* ACMD6, quatro linhas */
        return false;
    }
    SD_BASE[CONTROL] = WIDE_BUS;
    SD_BASE[DIVIDER] = SD_FAST_DIVIDER;
    return true;
}

/* Lê o setor de 512 bytes em buffer. Devolve true se não houve erro. */
bool sd_read_sector(uint32_t sector, uint32_t buffer[static SD_WORDS])
{
    SD_BASE[ARG] = sector;
    SD_BASE[CMD] = 17 | RSP_R1 | DATA_EN;
    sd_wait(CMD_DONE | DATA_DONE);
    SD_BASE[STATUS] = CMD_DONE | DATA_DONE;
    if (sd_take_errors() != 0) {
        return false;
    }
    SD_BASE[PTR] = 0;
    for (uint32_t i = 0; i < SD_WORDS; i++) {
        buffer[i] = SD_BASE[DATA];
    }
    return true;
}

/* Grava o setor de 512 bytes de buffer. Devolve true se o cartão o aceitou. */
bool sd_write_sector(uint32_t sector, const uint32_t buffer[static SD_WORDS])
{
    SD_BASE[PTR] = 0;
    for (uint32_t i = 0; i < SD_WORDS; i++) {
        SD_BASE[DATA] = buffer[i];
    }
    SD_BASE[ARG] = sector;
    SD_BASE[CMD] = 24 | RSP_R1 | DATA_EN | DATA_WRITE;
    sd_wait(CMD_DONE | DATA_DONE);
    uint32_t token = (SD_BASE[STATUS] >> TOKEN_SHIFT) & TOKEN_MASK;
    SD_BASE[STATUS] = CMD_DONE | DATA_DONE;
    return sd_take_errors() == 0 && token == TOKEN_ACCEPTED;
}
```

## 7. Origem das informações

A especificação SD Physical Layer não está nos documentos do repositório, e o que este periférico implementa vem do conhecimento do autor sobre ela, sem conferência com o texto da especificação. Os dados que vieram dos manuais das placas são os nomes e os pinos da seção 2 e a menção aos modos SPI e SD de 4 bits da DE0-CV.

| Informação | Origem |
| :--- | :--- |
| Quadro de comando de 48 bits, polinômios do CRC7 e do CRC16, formatos R1, R1b, R2, R3, R6 e R7 | Especificação SD, de memória |
| Valores conhecidos de CRC (CMD0 `0x4A`, CMD8 `0x43`, CMD17 `0x2A`, CMD55 `0x32`, ACMD41 `0x3B`, 512 bytes `0xFF` com `0x7FA1`) | Especificação SD, de memória, conferidos contra o cálculo independente do teste |
| Sequência CMD0, CMD8, ACMD41, CMD2, CMD3, CMD7, ACMD6, bit de CCS e do OCR, argumento `0x1AA` | Especificação SD, de memória |
| Esperas de 74 clocks, 400 kHz, 25 MHz, NCR 64, NCC 8, NWR 2 e estado de CRC | Especificação SD, de memória; os valores de projeto (8, 4, 16 e 2 clocks) são do periférico |
| Estados de CRC 010, 101 e 110 e o ocupado em `DAT0` | Especificação SD, de memória |
| Pinos, tensão e modos do socket | Manuais da DE0-CV e da DE2-115 em `Docs` |
| Teste em cartão real | Não confirmado; a verificação usa só o modelo de cartão do teste |

## 8. Verificação

O teste de entidade liga o periférico a um modelo de cartão SD no modo nativo que responde ao CMD0, CMD8, CMD55, ACMD41, CMD2, CMD3, CMD7, ACMD6, CMD13, CMD17 e CMD24, com o CRC7 e o CRC16 calculados por divisão polinomial de inteiros, de forma independente do registrador de deslocamento do VHDL. O modelo confere o CRC7 de cada comando, os 74 clocks iniciais e o CRC16 de cada linha do bloco escrito, e aceita falhas injetadas (resposta ausente, CRC ou índice errado, bloco corrompido ou ausente, estado de CRC 101 e 110, ocupado preso). Os casos cobrem o reset, os registradores, o período de `SD_CLK` e a parada em repouso, a inicialização completa até a leitura e a gravação de um setor com quatro linhas e com uma, os divisores 0 a 2, o prazo sem cartão, cada conferência da resposta, a detecção de ocupado em `DAT0`, cada erro de dados, o comando recusado, o aborto e as interrupções. Os testes dos dois CRC e do gerador de clock rodam à parte, e o dos CRC compara o registrador com valores conhecidos e com mensagens aleatórias.

A prova formal verifica o CRC7 e o CRC16 contra a divisão polinomial e contra um valor conhecido, o resto zero de uma mensagem seguida do próprio CRC, e o controle de comando: o quadro de 48 bits com o CRC7, o prazo de resposta, a aceitação e a recusa de cada formato de resposta curta, a espera de ocupado e o aborto, com mutantes que ela precisa reprovar.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

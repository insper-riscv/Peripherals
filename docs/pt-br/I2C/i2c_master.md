# Mestre I2C

🌐 [Português](../../pt-br/I2C/i2c_master.md) · [English](../../en/I2C/i2c_master.md)

## 1. O que é

Mestre I2C de uso geral (`i2c_master`) para um barramento de dois fios, SCL e SDA, com os pinos em dreno aberto. Serve a qualquer escravo do barramento, e na DE2-115 serve a EEPROM de 32 Kbit, o codec de áudio WM8731 e o decodificador de TV ADV7180. O processador escreve um comando por ação de barramento (início, parada, envio ou recepção de um byte) e acompanha o fim pelo bit de ocupado ou pela interrupção.

O mestre gera as condições de início, de repetição de início e de parada, envia e recebe bytes com a fase de ACK, espera o escravo que estica o clock, detecta a arbitragem perdida e sinaliza o NACK. Não há FIFO: um registrador de comando e um bit de ocupado dão uma interface de um byte por vez, simples de usar em laço de polling e fácil de provar.

## 2. Interface

### 2.1. Generics

| Generic | Padrão | Descrição |
| :--- | ---: | :--- |
| `clk_freq` | 100000000 | Frequência de `i_clk` em Hz |
| `scl_freq` | 100000 | Frequência de SCL em Hz que o divisor tem ao sair do reset; 400000 dá o modo rápido |

### 2.2. Portas

| Porta | Sentido | Descrição |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock e reset síncrono, ativo em 1 |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura do barramento |
| `i_address` | entrada, 3 bits | Endereço de palavra do registrador |
| `i_data_in`, `o_data_out` | entrada e saída, `word_t` | Dados do barramento; a saída vale zero fora de uma leitura |
| `o_irq` | saída | Interrupção em nível |
| `o_scl_low`, `o_sda_low` | saída | Valem 1 quando o mestre puxa a linha para baixo |
| `i_scl`, `i_sda` | entrada | Nível lido de cada pino, sincronizado por dois flip-flops dentro do bloco |

## 3. Registradores

O endereço é de palavra, com 3 bits. Um endereço fora da tabela lê zero e ignora a escrita.

| Palavra | Nome | Acesso | Reset | Descrição |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | leitura e escrita | 0 | Bit 0 `ENABLE`, bit 1 `IRQ_DONE`, bit 2 `IRQ_ERR`; o bit 3 `ABORT` é um pulso de escrita e lê como zero |
| 1 | `DIVIDER` | leitura e escrita | Calculado dos generics | Divisor de 16 bits; valores abaixo de 2 são gravados como 2 |
| 2 | `CMD` | escrita | não se aplica | Comando; lê zero |
| 3 | `TX` | leitura e escrita | 0 | Byte que o próximo comando de envio transmite |
| 4 | `RX` | leitura | 0 | Último byte recebido |
| 5 | `STATUS` | leitura e escrita de 1 para limpar | 0 | Estado, ver a tabela de bits |

### 3.1. Bits de `CMD`

Um comando executa, nesta ordem, o início, o byte e a parada que seus bits pedem.

| Bit | Nome | Efeito |
| ---: | :--- | :--- |
| 0 | `START` | Gera início (ou repetição de início se o mestre já tem a transação aberta) |
| 1 | `STOP` | Gera parada ao fim do comando |
| 2 | `READ` | Recebe um byte para `RX` |
| 3 | `WRITE` | Envia o byte de `TX` |
| 4 | `NACK` | Com `READ`, responde NACK ao byte recebido; com 0, responde ACK |

Um comando é recusado, sem tocar o barramento e com o bit `REJECTED` ligado, quando o mestre está desligado ou ocupado, quando não traz nenhum bit de ação, quando pede `READ` e `WRITE` juntos ou quando não traz `START` e não há transação aberta.

### 3.2. Bits de `STATUS`

| Bit | Nome | Descrição |
| ---: | :--- | :--- |
| 0 | `BUSY` | Comando em execução |
| 1 | `BUS_ACTIVE` | O mestre deu um início e ainda não deu a parada |
| 2 | `DONE` | Comando terminado, inclusive por arbitragem perdida; fica ligado até ser limpo |
| 3 | `NACK` | O byte enviado, endereço ou dado, recebeu NACK; fica ligado até ser limpo |
| 4 | `ARB_LOST` | O mestre perdeu a arbitragem; fica ligado até ser limpo |
| 5 | `REJECTED` | Um comando foi recusado; fica ligado até ser limpo |

Escrever 1 num dos bits 2 a 5 limpa o bit. Um evento no mesmo ciclo da escrita prevalece. Quando `BUSY` volta a 0, `DONE` já vale 1.

## 4. Comportamento

### 4.1. Temporização

Cada bit de SCL dura cinco passos, três com SCL baixo e dois com SCL alto, e um passo dura `DIVIDER + 1` ciclos de `i_clk`:

$$ f_{scl} = \frac{f_{clk}}{5 \cdot (DIVIDER + 1)} $$

Com `clk_freq` de 100 MHz, o divisor de reset vale 199 para 100 kHz e 49 para 400 kHz. A proporção de 3 para 2 entre SCL baixo e alto cumpre os tempos mínimos das duas velocidades. O início e a parada usam mais passos (SCL alto por três passos antes de SDA cair, e depois da parada SDA solto por um passo), o que respeita os tempos de preparação e de retenção do modo padrão.

O divisor mínimo é 2, o que dá três ciclos por passo e deixa a leitura do pino atravessar o sincronizador antes de ser amostrada. Em hardware real, escolha o divisor de modo que um passo seja bem maior que o tempo de subida da linha.

### 4.2. Esticamento de clock

Depois de soltar SCL, o mestre só avança quando lê SCL em 1, e fica parado enquanto o escravo a segura em 0. Se o escravo nunca a soltar, o comando não termina; o software sai dessa situação escrevendo `ABORT` em `CTRL`, que solta as duas linhas e cancela o comando.

### 4.3. Arbitragem e NACK

O mestre confere SDA quando solta a linha. Ele perde a arbitragem ao enviar um bit 1 e ler SDA em 0, ao soltar SDA antes de um início ou de uma parada e ler 0. Nesse caso solta as duas linhas, encerra o comando e liga `ARB_LOST` e `DONE`. Um byte enviado cujo bit de ACK é lido em 1 liga `NACK`, e o comando segue até o fim, inclusive a parada pedida.

### 4.4. Interrupção

$$ o\_irq = (DONE \cdot IRQ\_DONE) + (NACK + ARB\_LOST + REJECTED) \cdot IRQ\_ERR $$

A saída é de nível e cai quando o software limpa os bits de `STATUS`.

## 5. Ligação aos pinos

O bloco entrega só `o_scl_low`, `o_sda_low`, `i_scl` e `i_sda`. O topo da plataforma liga o buffer de três estados de cada linha, que vale 0 quando `o_*_low` vale 1 e fica em alta impedância quando vale 0, e devolve o nível do pino em `i_scl` e `i_sda`. As linhas precisam de resistor de pull-up externo ou interno do pino.

| Placa | Barramento | Pinos do manual | Escravos |
| :--- | :--- | :--- | :--- |
| DE2-115 | EEPROM | `EEP_I2C_SCLK` (PIN_D14) e `EEP_I2C_SDAT` (PIN_E14) | EEPROM de 32 Kbit, endereço 0xA0 para escrita e 0xA1 para leitura |
| DE2-115 | Áudio e vídeo | `I2C_SCLK` (PIN_B7) e `I2C_SDAT` (PIN_A8) | Codec WM8731 e decodificador ADV7180, que dividem o mesmo barramento |

A DE0-CV não tem barramento I2C nos pinos do manual. Os dois barramentos da DE2-115 são independentes e pedem uma instância de `i2c_master` cada.

## 6. Ler e escrever uma EEPROM

### 6.1. Parâmetros da família

| Capacidade | Endereço de byte | Observação |
| :--- | :--- | :--- |
| 2 Kbit (256 bytes) | 1 byte | |
| 4 Kbit a 16 Kbit | 1 byte | Os bits altos do endereço entram nos bits do endereço do dispositivo, ver o datasheet do chip |
| 32 Kbit a 64 Kbit | 2 bytes, o mais significativo primeiro | |

O tamanho da página de escrita vem do datasheet do chip (potência de dois). Uma escrita que cruza o limite da página volta ao início dela e sobrescreve bytes. O endereço de dispositivo 7 bits vale 0x50 nas placas citadas (byte de endereço 0xA0 na escrita e 0xA1 na leitura).

### 6.2. Sequências

Escrita de página:

1. `TX` recebe o byte de endereço do dispositivo com bit de escrita e `CMD` recebe `START | WRITE`.
2. Para cada byte de endereço (um ou dois), `TX` recebe o byte e `CMD` recebe `WRITE`.
3. Para cada dado, `TX` recebe o byte e `CMD` recebe `WRITE`, e o último leva `WRITE | STOP`.
4. Espera o ciclo interno de escrita por polling de ACK, repetindo `START | WRITE` com o byte de endereço do dispositivo e `STOP` até o byte ser aceito (sem `NACK`). Enquanto o chip escreve, ele responde NACK ao endereço.

Leitura aleatória:

1. `START | WRITE` com o byte de endereço de escrita, e os bytes de endereço com `WRITE`, sem `STOP`.
2. `START | WRITE` com o byte de endereço de leitura (repetição de início).
3. Para cada byte, `CMD` recebe `READ`, o byte sai de `RX`, e o último byte leva `READ | NACK | STOP`.

### 6.3. Exemplo em C

```c
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define I2C_BASE       0x10002000u  /* base da janela do periférico na plataforma */
#define I2C_REG(n)     (*(volatile uint32_t *)(I2C_BASE + 4u * (n)))
#define I2C_CTRL       I2C_REG(0)
#define I2C_DIVIDER    I2C_REG(1)
#define I2C_CMD        I2C_REG(2)
#define I2C_TX         I2C_REG(3)
#define I2C_RX         I2C_REG(4)
#define I2C_STATUS     I2C_REG(5)

#define CTRL_ENABLE    (1u << 0)
#define CMD_START      (1u << 0)
#define CMD_STOP       (1u << 1)
#define CMD_READ       (1u << 2)
#define CMD_WRITE      (1u << 3)
#define CMD_NACK       (1u << 4)
#define ST_BUSY        (1u << 0)
#define ST_NACK        (1u << 3)
#define ST_ARB_LOST    (1u << 4)
#define ST_REJECTED    (1u << 5)

#define EEPROM_WRITE   0xA0u
#define EEPROM_READ    0xA1u
#define EEPROM_TWO_ADDRESS_BYTES true   /* 32 Kbit a 64 Kbit; false para 2 Kbit */
#define POLL_TRIES     1000u

/* Espera o fim do comando e devolve o estado, com os bits de erro já lidos. */
static uint32_t i2c_wait(void) {
    uint32_t status;
    do {
        status = I2C_STATUS;
    } while (status & ST_BUSY);
    return status;
}

/* Executa um comando de envio e informa se o escravo respondeu ACK. */
static bool i2c_send(uint32_t flags, uint8_t byte) {
    I2C_STATUS = ST_NACK | ST_ARB_LOST | ST_REJECTED;
    I2C_TX = byte;
    I2C_CMD = flags | CMD_WRITE;
    return (i2c_wait() & (ST_NACK | ST_ARB_LOST | ST_REJECTED)) == 0;
}

void i2c_init(void) {
    I2C_CTRL = CTRL_ENABLE;          /* 100 kHz com o divisor de reset */
}

/* Envia o endereço de dispositivo e o endereço de byte, sem parada. */
static bool eeprom_set_address(uint16_t address) {
    bool ok = i2c_send(CMD_START, EEPROM_WRITE);
    if (EEPROM_TWO_ADDRESS_BYTES) {
        ok = ok && i2c_send(0, (uint8_t)(address >> 8));
    }
    return ok && i2c_send(0, (uint8_t)address);
}

/* Espera o ciclo de escrita por polling de ACK. */
static bool eeprom_wait_ready(void) {
    for (uint32_t i = 0; i < POLL_TRIES; i++) {
        bool ready = i2c_send(CMD_START | CMD_STOP, EEPROM_WRITE);
        if (ready) {
            return true;
        }
    }
    return false;
}

/* Escreve até uma página; o chamador não cruza o limite da página. */
bool eeprom_write_page(uint16_t address, const uint8_t *data, size_t length) {
    if (length == 0) {
        return false;
    }
    bool ok = eeprom_set_address(address);
    for (size_t i = 0; ok && i < length; i++) {
        ok = i2c_send(i + 1 == length ? CMD_STOP : 0, data[i]);
    }
    if (!ok) {
        I2C_CMD = CMD_STOP;
        i2c_wait();
        return false;
    }
    return eeprom_wait_ready();
}

/* Leitura aleatória de length bytes a partir de address. */
bool eeprom_read(uint16_t address, uint8_t *data, size_t length) {
    if (!eeprom_set_address(address) || !i2c_send(CMD_START, EEPROM_READ)) {
        I2C_CMD = CMD_STOP;
        i2c_wait();
        return false;
    }
    for (size_t i = 0; i < length; i++) {
        bool last = i + 1 == length;
        I2C_CMD = CMD_READ | (last ? (CMD_NACK | CMD_STOP) : 0u);
        i2c_wait();
        data[i] = (uint8_t)I2C_RX;
    }
    return true;
}
```

No polling, o comando leva `START` e `STOP` juntos, de modo que a parada sai mesmo quando o chip recusa o endereço.

## 7. Verificação

Os testes de entidade rodam o mestre contra um modelo comportamental de EEPROM em Python, com endereçamento de 1 e de 2 bytes, escrita de página com retorno ao início da página, ciclo de escrita com NACK, esticamento de clock e um segundo mestre que ganha a arbitragem. Cobrem o período de SCL, as condições de início, repetição de início e parada, o NACK de endereço, a recusa de comandos, o aborto, as interrupções e o divisor de reset de cada frequência. A prova formal verifica os registradores, as leituras, a interrupção e a liberação das linhas do topo, e o pulso de fim, as linhas e a arbitragem da máquina de linha, com mutantes de cada um.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

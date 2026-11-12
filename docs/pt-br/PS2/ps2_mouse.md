# Mouse PS/2

🌐 [Português](../../pt-br/PS2/ps2_mouse.md) · [English](../../en/PS2/ps2_mouse.md)

## 1. O que é

Periférico de barramento que conduz um mouse PS/2 de três botões e entrega ao programa o deslocamento acumulado em X e Y, o estado dos botões e uma interrupção opcional. A entidade `ps2_mouse` fala bytes com a camada física `ps2_host` (um canal PS/2) e não guarda estado fora da instância, de modo que várias instâncias, cada uma com seu `ps2_host`, convivem no mesmo projeto, por exemplo o teclado no canal 0 e o mouse no canal 1.

A entidade é composta por quatro blocos de função única.

| Bloco | Função |
| :--- | :--- |
| `ps2_mouse_decoder` | Sequência de inicialização, montagem dos pacotes de 3 bytes e ressincronização |
| `ps2_axis_accumulator` | Soma saturada do deslocamento de um eixo, zerada na leitura (uma instância por eixo) |
| `ps2_mouse_operation_decoder` | Tradução do endereço de palavra em seletor de leitura e pulsos de limpeza |
| `ps2_mouse` | Topo estrutural com os bits de status, a habilitação da interrupção e o multiplexador de leitura |

## 2. Registradores

O endereço é de palavra, com 3 bits, e o bloco ocupa 8 palavras (32 bytes). Os endereços de 5 a 7 leem zero e ignoram a escrita.

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `STATUS` | Bits de status da tabela abaixo; a leitura limpa os bits 0 a 2 | Ignorada |
| 1 | `DX` | Deslocamento acumulado em X, 16 bits em complemento de dois com extensão de sinal; a leitura zera o acumulador | Ignorada |
| 2 | `DY` | Deslocamento acumulado em Y (positivo para cima), no mesmo formato de `DX` | Ignorada |
| 3 | `BUTTONS` | Bit 0 esquerdo, bit 1 direito, bit 2 meio, no nível do último pacote | Ignorada |
| 4 | `CONTROL` | Bit 0 habilita a interrupção; o bit 1 lê zero | Bit 0 define a habilitação; escrever 1 no bit 1 reinicia o mouse |

Bits de `STATUS`.

| Bit | Nome | Significado |
| ---: | :--- | :--- |
| 0 | `NEW` | Chegou pelo menos um pacote desde a última leitura |
| 1 | `OVERFLOW` | Um pacote trouxe estouro de eixo ou um acumulador saturou desde a última leitura |
| 2 | `ERROR` | Houve erro de quadro, resposta inesperada, byte fora de sincronia ou silêncio desde a última leitura |
| 3 | `STREAMING` | A inicialização terminou e o mouse envia pacotes (nível atual, não é limpo pela leitura) |

Um pacote que chega no mesmo ciclo da leitura de um registrador não se perde, porque o valor lido é o anterior e o novo fica acumulado ou sinalizado.

## 3. Protocolo

### 3.1. Inicialização

Após o reset, o decodificador envia os comandos abaixo e confere cada resposta.

| Passo | Envia | Espera |
| ---: | :--- | :--- |
| 1 | `0xFF` (reset) | `0xFA` (ACK) |
| 2 | nada | `0xAA` (autoteste concluído) |
| 3 | nada | `0x00` (identificador do mouse) |
| 4 | `0xF4` (habilita streaming) | `0xFA` (ACK) |

Uma resposta diferente da esperada, um erro de quadro ou o silêncio por `init_timeout_cycles` ciclos de clock geram o bit `ERROR` e reiniciam a sequência pelo passo 1. O autoteste de um mouse leva centenas de milissegundos, e o padrão de `init_timeout_cycles` cobre um segundo a 100 MHz. A escrita de 1 no bit 1 de `CONTROL` também reinicia a sequência.

### 3.2. Pacotes

No modo streaming cada movimento chega em três bytes.

| Byte | Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 0 | estouro Y | estouro X | sinal Y | sinal X | 1 | meio | direito | esquerdo |
| 1 | `X[7:0]` | | | | | | | |
| 2 | `Y[7:0]` | | | | | | | |

O deslocamento de cada eixo é o valor de 9 bits $\{\text{sinal}, \text{byte}\}$ em complemento de dois, de $-256$ a $255$. Com o bit de estouro do eixo ligado o deslocamento é cortado em $255$ ou $-256$, conforme o sinal, e o bit `OVERFLOW` liga.

Um primeiro byte com o bit 3 em zero não pode iniciar um pacote. O byte é descartado, o bit `ERROR` liga e o decodificador espera um novo primeiro byte, o que ressincroniza o fluxo. Um pacote parado entre bytes por `packet_timeout_cycles` ciclos de clock, ou interrompido por erro de quadro, é descartado do mesmo modo.

### 3.3. Acumuladores

Cada pacote soma o deslocamento ao acumulador do eixo, que satura em $-32768$ e $32767$ em vez de dar a volta. A saturação liga `OVERFLOW`. A leitura de `DX` ou de `DY` entrega o valor e zera o acumulador do eixo correspondente.

## 4. Interrupção

A saída `o_irq` vale 1 enquanto o bit `NEW` estiver ligado e a habilitação em `CONTROL` também estiver. A leitura de `STATUS` encerra a causa. A saída é de nível, própria para uma fonte do PLIC.

## 5. Canal 1 e cabo Y

A DE0-CV tem um único conector PS/2. Com um dispositivo só, ele usa o canal 0, `PS2_CLK` (pino D3) e `PS2_DAT` (pino G2). Para o teclado e o mouse funcionarem ao mesmo tempo, um cabo Y divide o conector em duas portas, e o mouse usa o canal 1, `PS2_CLK2` (pino E2) e `PS2_DAT2` (pino G1), que o manual da placa reserva para isso (Tabela 3-11).

Cada canal tem o seu `ps2_host` e o seu periférico. As instâncias não compartilham sinais nem estado, então o mouse no canal 1 não interfere no teclado do canal 0.

## 6. Integração

### 6.1. Conexão do canal

No topo da placa, um `ps2_host` liga as linhas do conector ao `ps2_mouse` pela interface de bytes.

| `ps2_host` | `ps2_mouse` | Observação |
| :--- | :--- | :--- |
| `i_clk` | `i_clk` | Clock do sistema |
| `i_rst_n` | inverso de `i_rst` | O `ps2_host` reseta em nível baixo e o `ps2_mouse` em nível alto |
| `o_rx_data`, `o_rx_valid`, `o_rx_error` | `i_rx_data`, `i_rx_valid`, `i_rx_error` | Bytes recebidos do mouse |
| `i_tx_data`, `i_tx_valid` | `o_tx_data`, `o_tx_valid` | Comando enviado ao mouse |
| `o_tx_ready` | `i_tx_ready` | O transmissor aceita um byte |

O `o_tx_valid` vale 1 por um único ciclo, e só no ciclo em que `i_tx_ready` vale 1, o que serve tanto a um transmissor que lê o byte no pulso quanto a um que usa o aperto de mão pronto e válido.

### 6.2. Portas de topo e janela

| Item | Valor |
| :--- | :--- |
| Linhas do conector (portas bidirecionais do `ps2_host`) | `io_ps2_clk` no pino E2 (`PS2_CLK2`) e `io_ps2_dat` no pino G1 (`PS2_DAT2`) |
| Janela de registradores | 8 palavras (32 bytes), endereço de palavra de 3 bits, cinco registradores usados |
| Barramento | `i_data_in`, `i_address`, `i_write`, `i_read`, `o_data_out` de 32 bits, como os demais periféricos |
| Interrupção | `o_irq`, ativa em 1, para uma fonte do PLIC |

### 6.3. Parâmetros

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `data_width` | 32 | Largura do barramento de dados |
| `init_timeout_cycles` | 100000000 | Silêncio aceito durante a inicialização, em ciclos de clock |
| `packet_timeout_cycles` | 5000000 | Silêncio aceito no meio de um pacote, em ciclos de clock |

## 7. Verificação

Os testes de entidade conduzem a interface de bytes com um modelo do `ps2_host` escrito no teste. Cobrem a sequência de inicialização, as respostas erradas e o silêncio, o envio só com o transmissor pronto, os pacotes com sinal e estouro, a acumulação e a saturação, a ressincronização, o erro de quadro e o silêncio no meio do pacote, a limpeza na leitura, a interrupção, a reinicialização e os endereços fora do mapa. O acumulador tem testes próprios, que incluem a soma no mesmo ciclo da limpeza.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

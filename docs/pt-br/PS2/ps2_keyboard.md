# Teclado PS/2 (`ps2_keyboard`)

## 1. O que é

O teclado PS/2 mapeado em memória liga um teclado ao barramento do núcleo. Ele instancia o `ps2_host` (ver [ps2_host.md](ps2_host.md)), guarda os bytes de scancode numa fila síncrona e deixa o software enviar comandos ao teclado. Cada instância é independente, então teclado e mouse convivem num cabo Y, cada um no seu canal.

| Item | Valor |
| :--- | :--- |
| Conjunto de scancodes | Conjunto 2 (make, break com prefixo `0xF0`, estendido com prefixo `0xE0`) |
| Canal da DE0-CV | 0: `PS2_CLK` (D3) e `PS2_DAT` (G2) |
| Profundidade da fila | 16 bytes (parâmetro `rx_fifo_depth`, de 1 a 255) |
| Bloco de registradores | 4 palavras (16 bytes), `i_address` de 2 bits |
| Acesso mapeado | 1 ciclo, sem espera do barramento |

## 2. Portas de topo e integração

| Porta | Sentido | Ligação |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock do sistema e reset ativo em nível alto |
| `i_data_in`, `i_address` (2 bits), `i_write`, `i_read`, `o_data_out` | barramento | Slot de 4 palavras no interconector |
| `o_irq` | saída | Fonte de interrupção de nível para o PLIC |
| `io_ps2_clk` | bidirecional | Pino `PS2_CLK` (D3) |
| `io_ps2_dat` | bidirecional | Pino `PS2_DAT` (G2) |

Os generics `filter_cycles`, `inhibit_cycles` e `timeout_cycles` seguem o `ps2_host` e têm como padrão um clock de 50 MHz. Com outro clock, o topo ajusta os três para manter 160 ns de filtro, 100 us ou mais de inibição e 20 ms de limite.

## 3. Registradores

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `DATA` | Bits 7:0 do byte mais antigo e remoção ao final do acesso | Ignorada |
| 1 | `STATUS` | Estado, erros e nível descritos abaixo | Um em um bit de erro o limpa |
| 2 | `COMMAND` | Zero | Envia os bits 7:0 ao teclado |
| 3 | `CONTROL` | Bit 0 `RX_IRQ_ENABLE`, bit 1 `ERROR_IRQ_ENABLE` | Os dois bits habilitam as causas de interrupção |

| Bits de `STATUS` | Nome | Significado |
| :--- | :--- | :--- |
| 0 | `RX_VALID` | Há pelo menos um byte na fila |
| 1 | `TX_READY` | O transmissor aceita um comando |
| 2 | `RX_OVERFLOW` | Um byte recebido foi descartado porque a fila estava cheia |
| 3 | `RX_ERROR` | Quadro com paridade, início ou parada inválidos, quadro interrompido ou comando sem reconhecimento |
| 4 | `RX_FULL` | A fila está cheia |
| 5 | `TX_DROPPED` | Uma escrita em `COMMAND` foi descartada porque o transmissor estava ocupado |
| 15:8 | `RX_LEVEL` | Quantidade de bytes na fila |

Os bits 2, 3 e 5 são persistentes. Uma escrita de um no próprio bit os limpa, e uma escrita de zero os preserva. Um evento novo no mesmo ciclo de uma limpeza tem prioridade.

## 4. Fluxo

Cada quadro correto do teclado entra na cauda da fila, e uma leitura de `DATA` devolve o byte mais antigo e o remove. Uma tecla pressionada gera o byte de make; ao soltar, o prefixo `0xF0` seguido do mesmo byte; teclas estendidas começam com `0xE0`. Com a fila cheia o byte novo é descartado e os antigos permanecem em ordem.

Um comando (por exemplo `0xFF` de reset ou `0xED` seguido do argumento dos LEDs) é escrito em `COMMAND` quando `TX_READY` vale um. O teclado responde com bytes (como `0xFA`) que chegam pela fila. Uma escrita com o transmissor ocupado é descartada e marca `TX_DROPPED`.

## 5. Interrupção

A saída `o_irq` é de nível e vale a soma de duas causas, cada uma com a sua habilitação, zeradas no reset.

| Causa | Condição | Deixa de valer quando |
| :--- | :--- | :--- |
| Recepção (`RX_IRQ_ENABLE`) | A fila não está vazia | O software remove o último byte |
| Erro (`ERROR_IRQ_ENABLE`) | `RX_OVERFLOW` ou `RX_ERROR` ativo | O software limpa o bit em `STATUS` |

## 6. Verificação

Os testes de entidade exercitam o estado de reset, a entrega em ordem de make, break e estendido, o overflow que preserva os bytes antigos, o erro de paridade e sua recuperação, os comandos de reset e de LEDs com reconhecimento, o descarte com o transmissor ocupado e a interrupção com e sem habilitação.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

# UART serial

## 1. O que é

A UART serial mapeada em memória liga o barramento do núcleo a linhas físicas 8N1. Duas filas síncronas separam a velocidade dos acessos do processador da duração dos quadros seriais. A fila de transmissão guarda bytes escritos pelo núcleo e a fila de recepção guarda bytes entregues pela camada física.

| Item | Valor inicial |
| :--- | :--- |
| Baud rate | 115200 |
| Clock | 50 MHz |
| Formato | 8 bits de dados, sem paridade e 1 bit de parada |
| Profundidade de TX | 16 bytes |
| Profundidade de RX | 16 bytes |
| Acesso mapeado | 1 ciclo, sem espera do barramento |

As profundidades de TX e RX são parâmetros independentes entre 1 e 255. Os parâmetros do gerador de baud permitem usar outro clock sem alterar a lógica das filas.

## 2. Fluxo dos bytes

Uma escrita em `TX_DATA` adiciona o byte à cauda de TX. Quando o transmissor físico está livre, ele remove automaticamente o byte mais antigo e inicia um quadro. O processador pode continuar escrevendo enquanto houver espaço.

Cada quadro recebido adiciona um byte à cauda de RX. Uma leitura de `RX_DATA` devolve o byte mais antigo e o remove na borda que termina o acesso. Uma chegada simultânea a essa leitura reutiliza a posição liberada e não gera erro.

## 3. Registradores

| Palavra | Nome | Leitura | Escrita |
| ---: | :--- | :--- | :--- |
| 0 | `TX_DATA` | Zero | Enfileira os bits 7:0 em TX |
| 1 | `RX_DATA` | Bits 7:0 do byte mais antigo e remoção ao final do acesso | Ignorada |
| 2 | `STATUS` | Estado, erros e níveis descritos abaixo | Um em um bit de erro o limpa |
| 3 | `CONTROL` | Bit 0 igual a `RX_IRQ_ENABLE` | Bit 0 habilita a interrupção de RX |

| Bits de `STATUS` | Nome | Significado |
| :--- | :--- | :--- |
| 0 | `RX_VALID` | Há pelo menos um byte na fila de recepção |
| 1 | `TX_READY` | Há pelo menos uma posição livre na fila de transmissão |
| 2 | `RX_OVERRUN` | Um byte recebido foi descartado porque RX estava cheia |
| 3 | `TX_DROPPED` | Uma escrita foi descartada porque TX estava cheia |
| 4 | `RX_FULL` | A fila de recepção está cheia |
| 5 | `TX_EMPTY` | Nenhum byte espera na fila de transmissão |
| 6 | `TX_IDLE` | TX está vazia e o transmissor físico terminou o último quadro |
| 15:8 | `RX_LEVEL` | Quantidade de bytes na fila de recepção |
| 23:16 | `TX_LEVEL` | Quantidade de bytes na fila de transmissão |

`TX_READY` permite continuar produzindo bytes sem esperar o término do quadro atual. Um software que precisa garantir que o último bit chegou ao pino espera `TX_IDLE`.

## 4. Erros e interrupção

`RX_OVERRUN` e `TX_DROPPED` são persistentes. Uma escrita de um em seu próprio bit de `STATUS` os limpa, e uma escrita de zero os preserva. Um novo erro no mesmo ciclo de uma limpeza tem prioridade e mantém o bit ativo.

Quando RX está cheia, o byte novo é descartado e todos os bytes antigos permanecem em ordem. Quando TX está cheia, a escrita nova é descartada sem alterar os bytes que já esperam.

A interrupção vale um quando `RX_IRQ_ENABLE` está ativo e RX não está vazia. Ela permanece ativa até o software remover o último byte ou desabilitá-la.

## 5. Verificação

Os testes de entidade exercitam reset, ordem, enchimento, esvaziamento, volta dos ponteiros, inserção e remoção simultâneas, níveis, interrupção, erros persistentes, quadros 8N1 e a temporização padrão de 115200 baud em 50 MHz.

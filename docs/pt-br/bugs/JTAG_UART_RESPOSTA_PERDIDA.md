# A UART sobre JTAG perdeu bytes e executou um comando depois de um reset

## 1. Resumo

A primeira versão da UART sobre JTAG deixava o hospedeiro ler a resposta de um comando no início da varredura seguinte. Duas falhas apareceram em simulação, ambas com a mesma causa: o clock da JTAG só roda enquanto uma varredura está em andamento.

| | |
| :--- | :--- |
| Sintoma | Bytes que o core enviou nunca chegavam ao hospedeiro, ou apareciam duas vezes. Depois de um reset do core, um byte de antes do reset aparecia na fila de recepção |
| Causa | A resposta e o flag de pronto cruzam para o clock da JTAG por flip-flops que só avançam nas bordas do clock da JTAG, e o clock ficava parado entre as varreduras |
| Correção | A lógica da varredura guarda a resposta num registrador próprio ao fim de uma varredura, mostra-a uma vez na captura seguinte, e o lado do core descarta um comando que estava pendente no reset |
| Teste | Os testes de transmissão (bytes em ordem, a fila cheia, uma resposta mostrada uma vez) falhavam antes da correção, e os testes de recepção falhavam depois de um reset |

## 2. O mecanismo

1. Toda varredura aceita executa um comando no lado do core: tira até quatro bytes da fila de transmissão e os escreve num registrador de resposta.
2. O lado do core termina em nanossegundos e inverte um flag de pronto. Esse flag chega ao clock da JTAG por dois flip-flops, que só se movem quando o clock da JTAG pulsa.
3. A varredura seguinte captura a sua resposta na primeira borda de clock. Nesse ponto o flag de pronto ainda não cruzou, então a captura mostra a resposta anterior, ou nenhuma.
4. O comando dessa varredura seguinte então executa e sobrescreve o registrador de resposta. A resposta que nunca foi capturada se perde, e uma resposta capturada duas vezes mostra os seus bytes duas vezes.

A segunda falha tem a mesma raiz. O lado da JTAG não é reiniciado junto com o core: um comando emitido antes do reset e ainda não executado continua diferente do flag de pronto depois dele, então o lado do core o executou como se o hospedeiro o tivesse acabado de enviar.

## 3. A correção

1. Ao fim de uma varredura, quando o flag de pronto já cruzou (a varredura tem muitas bordas do clock da JTAG, então ele sempre cruzou), a lógica da varredura copia a resposta para um registrador próprio, antes de emitir o comando seguinte. A captura da varredura seguinte lê esse registrador e limpa os seus bytes, para uma resposta ser mostrada uma vez.
2. O custo é uma varredura de latência: uma varredura mostra a resposta ao comando da varredura anterior à anterior. Um hospedeiro que continua varrendo não perde nada.
3. No reset, o lado do core iguala o seu flag de pronto ao flag de comando que enxerga, então um comando que estava pendente antes do reset não é executado.

## 4. Como evitar

Um valor que cruza para um clock que não roda livremente só vale depois de esse clock pulsar. Não o capture, e não deixe a sua fonte mudar, até saber que o cruzamento terminou, e antes disso tire uma cópia no lado lento. Todo estado do lado lento que não é reiniciado junto com o lado rápido precisa de uma regra explícita para o que um reset faz com uma transferência em andamento.

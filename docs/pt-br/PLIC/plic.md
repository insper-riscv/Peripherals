# PLIC

🌐 [Português](../../pt-br/PLIC/plic.md) · [English](../../en/PLIC/plic.md)

## 1. Referência

O PLIC implementa a especificação RISC-V Platform-Level Interrupt Controller, versão 1.0.0 (`riscv-plic-1.0.0`), no recorte de um hart e um contexto, o do modo máquina. A especificação define as fontes numeradas a partir de 1, as prioridades, o limiar por contexto, o claim e o complete, e o gateway de cada fonte. A saída `o_meip` é o pedido de interrupção externa de máquina (`MEIP`) do núcleo. O controlador simples `ext_irq_controller` é a alternativa de prioridade fixa, sem prioridades nem limiar.

## 2. O que é

O PLIC reúne as linhas de interrupção de nível dos periféricos e entrega ao núcleo um único `MEIP`. Cada fonte tem uma prioridade, um bit de habilitação e um gateway. O contexto tem um limiar. O núcleo não tem modo supervisor, por isso existe só o contexto 0.

| Generic | Padrão | Significado |
| :--- | :--- | :--- |
| `n_sources` | 8 | Número de fontes, de 1 a 1023. A fonte 0 não existe |
| `priority_bits` | 3 | Largura da prioridade e do limiar, de 1 a 32. Com 3 bits as prioridades vão de 1 a 7 |
| `addr_width` | 20 | Largura do endereço de palavra, de 20 a 31, dada pela janela da plataforma |

A prioridade 0 nunca interrompe. A janela de endereços tem no mínimo `0x200008` bytes, o que corresponde a `addr_width` igual a 20. A base e o tamanho da janela vêm do `platform.yaml`, e `addr_width` é o logaritmo do tamanho da janela em palavras.

## 3. Interface

| Porta | Sentido | Função |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | entrada | Clock e reset síncrono, ativo em 1 |
| `i_sources` | entrada | Linhas de nível das fontes, o bit $n$ é a fonte $n$, ativas em 1, síncronas a `i_clk` |
| `i_data_in`, `i_address` | entrada | Dado de escrita de 32 bits e endereço de palavra de `addr_width` bits |
| `i_write`, `i_read` | entrada | Pulsos de escrita e de leitura |
| `o_data_out` | saída | Dado de leitura, combinacional no endereço |
| `o_meip` | saída | `MEIP`, 1 quando existe uma fonte candidata |

A leitura do registrador de claim tem efeito colateral, e as demais leituras não têm.

## 4. Mapa de registradores

Os acessos são de 32 bits. Os deslocamentos são em bytes a partir da base da janela, e o endereço de palavra é o deslocamento dividido por 4. Um endereço fora do mapa lê zero e ignora a escrita.

| Deslocamento | Registrador | Acesso | Reset |
| :--- | :--- | :--- | :--- |
| `0x000000 + 4*id` | Prioridade da fonte `id`, `priority_bits` bits | L/E | 0 |
| `0x001000 + 4*k` | Pendentes das fontes $32k$ a $32k+31$ | L | 0 |
| `0x002000 + 4*k` | Habilitação do contexto 0 das fontes $32k$ a $32k+31$ | L/E | 0 |
| `0x200000` | Limiar do contexto 0, `priority_bits` bits | L/E | 0 |
| `0x200004` | Claim (leitura) e complete (escrita) do contexto 0 | L/E | 0 |

O bit 0 da primeira palavra de pendência e de habilitação é a fonte 0, que não existe, e lê zero. O mesmo vale para os bits acima de `n_sources`. Os bits altos da prioridade e do limiar, acima de `priority_bits`, leem zero.

## 5. Gateway

Cada fonte tem um gateway de nível. Quando a linha vale 1 e a fonte não está em atendimento, o pedido fica pendente e a fonte passa a ser mascarada. O pendente só cai com o claim, mesmo que a linha caia antes. Depois do claim a fonte continua mascarada até o complete, mesmo que a linha continue em 1, de modo que o handler recebe um pedido por atendimento. Depois do complete, uma linha ainda em 1 gera um novo pedido no ciclo seguinte.

## 6. Arbitragem, claim e complete

Uma fonte é candidata quando está pendente, habilitada e com prioridade estritamente maior que o limiar. A vencedora é a candidata de maior prioridade, e na igualdade vence o menor identificador. Então

$$o\_meip = \bigvee_{n=1}^{n\_sources} \left( pend_n \wedge en_n \wedge prio_n > thr \right)$$

A leitura do claim devolve o identificador da vencedora, ou 0 sem candidata, e limpa o pendente dela. A leitura sem candidata não altera nada. A escrita no claim com um identificador de uma fonte existente e habilitada desmascara essa fonte. Um identificador 0, fora de `1..n_sources`, de fonte não habilitada ou de outra fonte que não a escrita não altera nenhum gateway. A escrita não confere se o identificador é o último reclamado, como a especificação define.

## 7. Temporização

`o_meip` e a leitura do claim são combinacionais sobre os registradores de pendência, habilitação, prioridade e limiar, sem caminho das entradas `i_sources` até a saída. Uma linha que sobe aparece em `o_meip` um ciclo depois, quando o gateway registra o pedido.

## 8. Verificação

| Verificação | Cobertura |
| :--- | :--- |
| Testes de entidade `PLIC`, `PlicOneSource`, `PlicWide` e `PlicMax` | Reset, registradores com larguras extremas (1 fonte e 1 bit; 70 fontes e 8 bits com janela maior; 1023 fontes e 32 bits), prioridade zero, limiar estrito, habilitação, desempate por id, regras do complete, gateways independentes, claim sem candidata, todas as fontes e 3000 ciclos aleatórios contra um modelo de referência |
| Testes de entidade `PlicGateway` e `PlicArbiter` | O gateway contra o modelo de pendente e atendimento, e o árbitro em todas as máscaras de pendência e habilitação, com limiares e prioridades aleatórias |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

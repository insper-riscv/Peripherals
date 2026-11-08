# 1. E/S de Placa (contrato K8)

## 1. Escopo

Os periféricos de E/S de uso da placa (GPIO e display de 7 segmentos) enxergam vetores por papel, com a largura dada por generic. Este contrato define os papéis, onde a polaridade é resolvida e o que acontece quando a placa não tem o papel. O barramento que leva os registradores ao núcleo é o contrato K6, descrito no `ext_interconnect.md` do Insper-RISC-V.

## 2. Papéis

| Papel | Largura | Polaridade no lado do programa | Fonte |
| :--- | :--- | :--- | :--- |
| `leds` | $n_{led}$ | Ativo em `'1'` | `board.yaml`, `io.leds` |
| `switches` | $n_{sw}$ | `'1'` na posição alta | `io.switches` |
| `keys` | $n_{key}$ | Ativo em `'1'` quando pressionada | `io.keys` |
| `display` | $n_{dig} \times 7$ | Dígito escrito em hexadecimal, sem polaridade | `io.display` |

## 3. Polaridade

A placa pode ligar um LED, uma tecla ou um segmento em lógica invertida, e cada periférico resolve a polaridade do próprio pino por um generic, de modo que o programa vê sempre o mesmo sentido.

| Periférico | Generic | Padrão | Efeito |
| :--- | :--- | :--- | :--- |
| `gpio` | `active_low` | falso | Inverte os dois sentidos do pino dentro da `gpio_cell`. O programa lê e escreve ativo em `'1'` |
| `seg_display` | `active_low` | verdadeiro | Escolhe o nível que acende o segmento em `o_hex`. Verdadeiro acende em `'0'`, como nas placas DE |

O topo gerado escolhe o valor desses generics conforme a placa e o periférico não conhece a polaridade da placa além do próprio generic.

## 4. Largura e papel ausente

A largura de cada vetor é um generic do periférico, e o valor padrão vem do pacote gerado a partir do `board.yaml`. Um papel ausente na placa tem largura zero, e o periférico que o usa é omitido do SoC. O vetor de largura zero não gera porta no topo.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

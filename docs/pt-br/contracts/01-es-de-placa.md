# 1. E/S de Placa (contrato K8)

## 1. Escopo

Os periféricos de E/S de uso da placa (GPIO e display de 7 segmentos) enxergam vetores por papel, com a largura dada por generic. Este contrato define os papéis, a polaridade que o periférico vê e o que acontece quando a placa não tem o papel. O barramento que leva os registradores ao núcleo é o contrato K6, descrito no `ext_interconnect.md` do Insper-RISC-V.

## 2. Papéis

| Papel | Largura | Polaridade vista pelo periférico | Fonte |
| :--- | :--- | :--- | :--- |
| `leds` | $n_{led}$ | Ativo em `'1'` | `board.yaml`, `io.leds` |
| `switches` | $n_{sw}$ | `'1'` na posição alta | `io.switches` |
| `keys` | $n_{key}$ | Ativo em `'1'` quando pressionada | `io.keys` |
| `display` | $n_{dig} \times 7$ | Ativo em `'1'` por segmento | `io.display` |

## 3. Polaridade

A placa pode ligar um LED, uma tecla ou um segmento em lógica invertida. O topo gerado normaliza a polaridade de cada papel para a da tabela antes de entregá-la ao periférico e depois de recebê-la dele. O periférico nunca vê a polaridade da placa e não tem generic para ela.

## 4. Largura e papel ausente

A largura de cada vetor é um generic do periférico, e o valor padrão vem do pacote gerado a partir do `board.yaml`. Um papel ausente na placa tem largura zero, e o periférico que o usa é omitido do SoC. O vetor de largura zero não gera porta no topo.

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).

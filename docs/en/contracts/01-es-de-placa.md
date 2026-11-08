# 1. Board I/O (contract K8)

## 1. Scope

The board I/O peripherals (GPIO and the 7-segment display) see vectors by role, with the width given by a generic. This contract defines the roles, the polarity the peripheral sees and what happens when the board does not have the role. The bus that carries the registers to the core is contract K6, described in the `ext_interconnect.md` of Insper-RISC-V.

## 2. Roles

| Role | Width | Polarity seen by the peripheral | Source |
| :--- | :--- | :--- | :--- |
| `leds` | $n_{led}$ | Active at `'1'` | `board.yaml`, `io.leds` |
| `switches` | $n_{sw}$ | `'1'` in the high position | `io.switches` |
| `keys` | $n_{key}$ | Active at `'1'` when pressed | `io.keys` |
| `display` | $n_{dig} \times 7$ | Active at `'1'` per segment | `io.display` |

## 3. Polarity

The board may wire an LED, a key or a segment in inverted logic. The generated top normalizes the polarity of each role to the one in the table before handing it to the peripheral and after receiving it from the peripheral. The peripheral never sees the polarity of the board and has no generic for it.

## 4. Width and absent role

The width of each vector is a generic of the peripheral, and the default value comes from the package generated from `board.yaml`. A role absent from the board has width zero, and the peripheral that uses it is omitted from the SoC. The zero-width vector generates no port on the top.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).

# 1. Board I/O (contract K8)

## 1. Scope

The board I/O peripherals (GPIO and the 7-segment display) see vectors by role, with the width given by a generic. This contract defines the roles, where the polarity is resolved and what happens when the board does not have the role. The bus that carries the registers to the core is contract K6, described in the `ext_interconnect.md` of Insper-RISC-V.

## 2. Roles

| Role | Width | Polarity on the program side | Source |
| :--- | :--- | :--- | :--- |
| `leds` | $n_{led}$ | Active at `'1'` | `board.yaml`, `io.leds` |
| `switches` | $n_{sw}$ | `'1'` in the high position | `io.switches` |
| `keys` | $n_{key}$ | Active at `'1'` when pressed | `io.keys` |
| `display` | $n_{dig} \times 7$ | Digit written in hexadecimal, no polarity | `io.display` |

## 3. Polarity

The board may wire an LED, a key or a segment in inverted logic, and each peripheral resolves the polarity of its own pin through a generic, so the program always sees the same sense.

| Peripheral | Generic | Default | Effect |
| :--- | :--- | :--- | :--- |
| `gpio` | `pin_active_low`, one bit per pin | zeros | Inverts both directions of the pin inside the `gpio_cell`. The program reads and writes active at `'1'` |
| `seg_display` | `active_low` | true | Picks the level that lights a segment on `o_hex`. True lights at `'0'`, as on the DE boards |

The generated top picks the value of these generics according to the board and the peripheral knows no board polarity beyond its own generic.

## 4. Width and absent role

The width of each vector is a generic of the peripheral (`pin_count` in the `gpio` and `digits` in the `seg_display`), with the value coming from `board.yaml`. The partition of the pins and of the digits into groups, the fixed direction and the polarity of each pin also arrive as generics, described in `docs/en/GPIO/gpio.md` and `docs/en/display/seg_display.md`. A role absent from the board leaves the peripheral that uses it out of the SoC.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).

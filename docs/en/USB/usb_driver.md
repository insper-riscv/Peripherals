# C driver for the USB bridge and the CY7C67200 HPI

C23 library that operates the DE2-115 USB chip through the `usb_bridge` peripheral: accesses to the four HPI ports, reading and writing the chip memory, mailbox, reset and code loading. It includes no USB stack (enumeration, mass-storage or keyboard host), which depends on the chip firmware and on the datasheet.

## 1. Location and rationale

The C drivers of [Peripherals #47](https://github.com/insper-riscv/Peripherals/pull/47) follow `src/<peripheral>/<layer>/driver/c/` with `driver.yaml`, `rv32_<name>.h`, `rv32_<name>.c`, `rv32_<name>_platform.h` and `examples/main.c.in`. This driver follows the same structure in `src/USB/soc/driver/c/`, so the SDK finds it through `driver.yaml` with no change. It fits there because the driver only knows the nine words of the bridge, not the platform top, and the base comes from the generated `rv32_usb_platform.h`.

| File | Content |
| :--- | :--- |
| `rv32_usb.h` | Public API, with the confidence mark of each group |
| `rv32_usb.c` | Bridge, HPI, code loading and BIOS commands |
| `rv32_usb_unverified.c` | BIOS values from memory, all unconfirmed, isolated in one file |
| `rv32_usb_platform.h` | Platform base and wait budget (zero until the generator fills them) |
| `tests/c/usb_hpi.c` | Host test against the bridge and chip model |

## 2. Confidence levels

The CY7C67200 datasheet and programming guide are not in `Docs`. The DE2-115 manual (section 4.17) only cites both documents. Each statement of the driver has one of the levels below, and the header marks the level on each group.

| Level | Meaning | Items |
| :--- | :--- | :--- |
| C0 | Confirmed by the DE2-115 manual or by the bridge RTL | CY7C67200 chip in HPI mode; the HPI gives access to the chip internal memory and has a bidirectional mailbox (manual 4.17); `OTG_*` pins of table 4-25; the nine bridge words, `STATUS` and the two-phase read through `RDATA` (`usb_consts.vhd`, `usb_regs.vhd`) |
| C1 | HPI protocol known, no local source | The four chip addresses are data, mailbox, address and status (the naming comes from the bridge doc, the manual does not give it); writing ADDRESS sets the pointer and each DATA access advances it; the memory is made of 16-bit words |
| C2 | Value recalled from memory, unconfirmed | Mailbox bit in the HPI status, address of the LCP parameter area, BIOS accept and reject codes, codes of the jump, call, read and write control register commands, layout of parameters and results, reset and boot times |

Nothing at C2 is used unless the caller asks. The fields of `rv32_usb_profile_t` are zero by default, and a zero command code makes the function return `RV32_USB_E_INVALID`. Whoever holds the datasheet builds their own profile. `rv32_usb_profile_unverified()` returns the recalled values for lab use and lives in a separate file so it can be removed.

## 3. API

### 3.1. Bridge

| Function | Effect |
| :--- | :--- |
| `rv32_usb_new(base, poll_budget)` | Handle, no hardware write; a null or misaligned base or a zero budget gives an invalid handle |
| `rv32_usb_port_write(usb, port, value)` | Waits for the bridge to be free, writes 16 bits to the port, waits for completion and checks `ERROR` |
| `rv32_usb_port_read(usb, port, &value)` | Requests the read, waits for `BUSY` to drop and returns `RDATA`, as the bridge doc requires |
| `rv32_usb_chip_hold_reset`, `rv32_usb_chip_reset` | `CTRL.CHIP_RESET`; the pulse takes a delay callback and the two times from the caller |
| `rv32_usb_set_timing`, `rv32_usb_irq_mask` | `TIMING` (setup, pulse, recovery) and `IRQ_MASK` |

Every wait is bounded by `poll_budget` reads of `STATUS`, with no embedded time. A stale `ERROR` is cleared when an access starts, and an `ERROR` raised during the access becomes `RV32_USB_E_BRIDGE`.

### 3.2. HPI and code loading

| Function | Effect |
| :--- | :--- |
| `rv32_usb_hpi_read_words`, `rv32_usb_hpi_write_words` | Set ADDRESS and access DATA in sequence, with an even byte address |
| `rv32_usb_hpi_status`, `rv32_usb_hpi_mailbox_send`, `rv32_usb_hpi_mailbox_receive` | Status port and mailbox; receiving waits for the profile flag |
| `rv32_usb_load_code` | Writes the image as 16-bit words and reads it back to check |
| `rv32_usb_lcp_run`, `rv32_usb_run_code`, `rv32_usb_call_code`, `rv32_usb_read_ctrl_reg`, `rv32_usb_write_ctrl_reg` | BIOS commands through the profile: parameters in the LCP area, command in the mailbox, reply compared with accept and reject |
| `rv32_usb_smoke` | Reads the HPI status and one chip word |

The API uses 16-bit words instead of bytes, so the driver assumes no byte order of the image.

## 4. Use

```c
rv32_usb_t usb = rv32_usb_platform_new(RV32_USB_DEFAULT_INSTANCE);
uint16_t status, word;

rv32_usb_chip_hold_reset(usb, false);
/* boot wait: datasheet time, up to the caller */
if (rv32_usb_smoke(usb, REGISTER_ADDRESS, &status, &word) != RV32_USB_OK) {
    /* bridge or chip failure */
}
```

`REGISTER_ADDRESS` comes from the datasheet. The driver ships no chip register address as a confirmed value.

## 5. Verification

`make usb-driver-test` compiles the driver with `-std=c23 -Wall -Wextra -Wpedantic -Werror -Wconversion -Wshadow`, and the `rv32_usb_hook_*` functions of the test replace MMIO access with a C model. The model has two parts. The bridge follows the RTL: a port read only requests the access, `RDATA` is valid at the end of `BUSY`, a request while `BUSY` is dropped and raises `ERROR`. The chip is an assumption of the author (HPI ports, auto-incrementing pointer, mailbox, BIOS with the C2 values). The test covers handle, smoke, auto-increment, bridge errors, registers, reset, loading with and without corruption, BIOS commands, reject, a silent BIOS and an empty profile. Passing proves the driver is coherent with the model and the bridge, not the behavior of the real chip.

## 6. What the datasheet must confirm

1. Mailbox bit in the HPI status and the polarity of each flag.
2. Whether a dummy read exists after setting ADDRESS, and the pointer value after the last access.
3. BIOS command, accept and reject codes, the parameter area and where results land.
4. Whether the code jump replies with accept before executing.
5. Widths of the reset pulse and the boot time, and the HPI boot mode.
6. Chip revision register (candidate for the first board test).
7. The host and device firmware, and their structures, for pendrive or keyboard enumeration (item T27).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).

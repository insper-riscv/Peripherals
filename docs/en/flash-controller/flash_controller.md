# flash_controller

Memory-mapped peripheral that commands the FLASH chip: the software writes the address, fills the page buffer and writes the command code, and the controller delivers the command to the chip and shows its state.

## 1. Role of the component in the SoC

A real FLASH changes its content through commands (write enable, sector erase, page program, protect), not through stores. The controller gives the software a register interface in the style of the common serial FLASH chips and connects it to the chip modeled by `flash_cmd_port` (Memory repository, document [flash_cmd_port](https://github.com/insper-riscv/Memory/blob/main/docs/en/rom/flash_cmd_port.md)). The invalidation pulse for the caches comes out of the chip, not out of the controller.

| Side | Signals |
| :--- | :--- |
| Core bus | `i_data_in`, `i_address`, `i_write`, `i_read`, `o_data_out` |
| Command to the chip | `o_cmd_valid`, `o_cmd_op`, `o_cmd_addr` |
| State of the chip | `i_busy`, `i_wel`, `i_refused` |
| Page buffer read by the chip | `i_buf_idx`, `o_buf_data` |

## 2. Registers

The address is the offset in words inside the peripheral.

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `CMD` | Zero | Delivers to the chip the command in bits 2:0 of the data |
| 1 | `ADDR` | The byte address of the command | Stores the 32 bits as the address of the command |
| 2 | `STATUS` | Bit 0 busy, bit 1 write latch armed, bit 2 last erase or program refused | Ignored |
| 3 | `BUF_PTR` | Index of the buffer word that the next `BUF_DATA` writes | Sets the index (low bits of the data) |
| 4 | `BUF_DATA` | Zero | Writes the word into the buffer at `BUF_PTR` and adds one to `BUF_PTR`, which wraps at the end of the page |
| 5 | `IRQ_ENABLE` | Bit 0 done, bit 1 refused | Sets both bits; zero after reset |
| 6 | `IRQ_STATUS` | Bit 0 `DONE`, bit 1 `REFUSED` | A one in a bit clears it (W1C) |
| 7 | Reserved | Zero | Ignored |

Codes of `CMD`:

| Code | Command |
| :--- | :--- |
| 1 | Write enable |
| 2 | Erase the sector that contains `ADDR` |
| 3 | Program the page that contains `ADDR` with the content of the buffer |
| 4 | Protect the sector that contains `ADDR` |
| 5 | Unprotect the sector |

## 3. Behavior

### 3.1. Command delivery

A write to `CMD` raises `o_cmd_valid` in the same cycle, with no register on the path, with `o_cmd_op` equal to bits 2:0 of the data and `o_cmd_addr` equal to the `ADDR` register. The chip accepts the command on the edge that ends that cycle, and `STATUS` already shows busy in the next cycle. A read of `STATUS` right after the write to `CMD` never sees the state from before the command.

The chip ignores a command that arrives with busy at 1. The software waits for `STATUS` with bit 0 at zero before each command.

### 3.2. Page buffer

The buffer holds one page of `page_bytes` bytes. Its bits are 1 at FPGA configuration, and reset does not clear it. The software writes the words of the page with `BUF_DATA`, starting at `BUF_PTR`, and then sends the program command. The words the software does not write keep the previous content of the buffer, so a partial page writes `0xFFFFFFFF` into the words it must not change, because the program does the bitwise AND with the FLASH content.

The chip reads the buffer through `i_buf_idx`, and `o_buf_data` brings the word one edge later, like the storage memory of the chip.

### 3.3. Sequence of a sector update

1. Write `ADDR` with the address of a byte of the sector.
2. Write `CMD` with 1 and then with 2, waiting for `STATUS` busy to fall after the second.
3. For each page of the sector, write `ADDR`, fill the buffer, write `CMD` with 1 and then with 3, and wait for the end.
4. Read `STATUS` and check that bit 2 is zero.

### 3.4. Interrupt

Two chip events set bits of `IRQ_STATUS`, even with the enable off.

| Bit | Event | Detection |
| ---: | :--- | :--- |
| 0 `DONE` | The chip finished an accepted erase or program | Fall of `i_busy` |
| 1 `REFUSED` | The chip refused an erase or program | Rise of `i_refused`, which only falls with a new write enable |

The `o_irq` output is one while any pending bit is enabled. Software clears an event by writing a one to the bit. An event in the same cycle as the clear wins and keeps the bit set.

## 4. Interface

### 4.1. Generics

| Generic | Type | Default | Meaning |
| :--- | :--- | :--- | :--- |
| `page_bytes` | `positive` | 256 | Size of the program page in bytes, a power of two from 8 bytes up; it is the size of the buffer |

### 4.2. Ports

| Port | Direction | Width | Meaning |
| :--- | :--- | ---: | :--- |
| `i_clk` | input | 1 | Module clock |
| `i_rst` | input | 1 | Reset, active at `'1'`; clears `ADDR` and `BUF_PTR` |
| `i_data_in` | input | `XLEN` (`word_t`) | Write data |
| `i_address` | input | 3 | Word address |
| `i_write` | input | 1 | Write pulse |
| `i_read` | input | 1 | Read pulse |
| `o_data_out` | output | `XLEN` (`word_t`) | Read data, zero without `i_read` |
| `o_irq` | output | 1 | Level interrupt, `(IRQ_STATUS and IRQ_ENABLE) /= 0` |
| `o_cmd_valid` | output | 1 | Pulse that delivers a command to the chip |
| `o_cmd_op` | output | 3 | Command code |
| `o_cmd_addr` | output | `ADDR_BITS` (`addr_t`) | Byte address of the command |
| `i_busy` | input | 1 | The chip is busy |
| `i_wel` | input | 1 | The write latch of the chip is armed |
| `i_refused` | input | 1 | The last erase or program was refused |
| `i_buf_idx` | input | $\log_2(\texttt{page\_bytes}) - 2$ | Index of the buffer word read by the chip |
| `o_buf_data` | output | 32 | Buffer word, with a registered read |

## 5. Verification

| `tests/python/tests.json` entry | cocotb module | What it covers |
| :--- | :--- | :--- |
| `FlashController` | `tests.python.unittests.flash_controller.flash_controller` | Reset values; `ADDR` keeps the whole word and changes only by a write to it; the command pulse with the code and the address, only from a write to `CMD` and only in its cycle; `STATUS` in the eight combinations; `BUF_DATA` with advance and wrap of `BUF_PTR`; `BUF_PTR` set by a write; buffer read one edge later; reset |

The formal proof is in `formal/flash_controller_props.sv` (see [formal](../formal/formal.md)), with a 16-byte page and nine mutants of the VHDL.

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).

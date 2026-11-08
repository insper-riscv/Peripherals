# Serial UART

## 1. What it is

A memory-mapped serial UART connects the core bus to physical 8N1 lines. Two synchronous queues separate processor access speed from serial frame duration. The transmit queue stores bytes written by the core, and the receive queue stores bytes delivered by the physical layer.

| Item | Initial value |
| :--- | :--- |
| Baud rate | 115200 |
| Clock | 50 MHz |
| Format | 8 data bits, no parity, and 1 stop bit |
| TX depth | 16 bytes |
| RX depth | 16 bytes |
| Memory-mapped access | 1 cycle without bus wait |

The TX and RX depths are independent parameters from 1 through 255. The baud generator parameters support another clock without changing the queue logic.

## 2. Byte flow

A write to `TX_DATA` adds the byte to the tail of TX. When the physical transmitter is free, it automatically removes the oldest byte and starts a frame. The processor can keep writing while space remains.

Every received frame adds one byte to the tail of RX. A read of `RX_DATA` returns the oldest byte and removes it at the edge that ends the access. An arrival simultaneous with that read reuses the released position without reporting an error.

## 3. Registers

| Word | Name | Read | Write |
| ---: | :--- | :--- | :--- |
| 0 | `TX_DATA` | Zero | Queues bits 7:0 in TX |
| 1 | `RX_DATA` | Bits 7:0 of the oldest byte, removed at the end of the access | Ignored |
| 2 | `STATUS` | State, errors, and levels described below | A one in an error bit clears it |
| 3 | `CONTROL` | Bit 0 `RX_IRQ_ENABLE`, bit 1 `TX_EMPTY_IRQ_ENABLE`, bit 2 `ERROR_IRQ_ENABLE` | The three bits enable the interrupt causes |

| `STATUS` bits | Name | Meaning |
| :--- | :--- | :--- |
| 0 | `RX_VALID` | At least one byte is in the receive queue |
| 1 | `TX_READY` | At least one position is free in the transmit queue |
| 2 | `RX_OVERRUN` | A received byte was dropped because RX was full |
| 3 | `TX_DROPPED` | A write was dropped because TX was full |
| 4 | `RX_FULL` | The receive queue is full |
| 5 | `TX_EMPTY` | No byte is waiting in the transmit queue |
| 6 | `TX_IDLE` | TX is empty and the physical transmitter finished the last frame |
| 15:8 | `RX_LEVEL` | Number of bytes in the receive queue |
| 23:16 | `TX_LEVEL` | Number of bytes in the transmit queue |

`TX_READY` lets software continue producing bytes without waiting for the current frame to finish. Software that must guarantee that the last bit reached the pin waits for `TX_IDLE`.

## 4. Errors and interrupt

`RX_OVERRUN` and `TX_DROPPED` are sticky. Writing one to its own `STATUS` bit clears it, and writing zero preserves it. A new error in the same cycle as a clear takes priority and keeps the bit set.

When RX is full, the new byte is dropped and every old byte stays in order. When TX is full, the new write is dropped without changing the bytes already waiting.

The `o_irq` output is a level and is the sum of three causes, each with its own enable, all cleared by reset.

| Cause | Condition | Stops holding when |
| :--- | :--- | :--- |
| Receive (`RX_IRQ_ENABLE`) | RX is not empty | Software removes the last byte |
| Transmitter empty (`TX_EMPTY_IRQ_ENABLE`) | TX is empty | Software writes `TX_DATA` |
| Error (`ERROR_IRQ_ENABLE`) | `RX_OVERRUN` or `TX_DROPPED` set | Software clears the bit in `STATUS` |

With TX empty the transmitter-empty cause holds as soon as it is enabled, so software enables it only when it has bytes to send and disables it when done.

## 5. Verification

The entity tests cover reset, order, filling, draining, pointer wraparound, simultaneous insert and remove, levels, interrupt, sticky errors, 8N1 frames, and the default 115200-baud timing at 50 MHz.

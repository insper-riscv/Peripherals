"""Bits de estado e de controle comuns ao mestre SPI e ao SD."""

RX_VALID = 1 << 0
TX_READY = 1 << 1
TX_EMPTY = 1 << 2
BUSY = 1 << 3
RX_FULL = 1 << 4
DONE = 1 << 5
RX_OVERRUN = 1 << 6
TX_DROPPED = 1 << 7
CS_ASSERT = 1 << 0
RX_IRQ_ENABLE = 1 << 1
TX_EMPTY_IRQ_ENABLE = 1 << 2
DONE_IRQ_ENABLE = 1 << 3
ERROR_IRQ_ENABLE = 1 << 4

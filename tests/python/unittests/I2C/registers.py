"""Register map and bit positions of the I2C master, shared by tests."""

CTRL, DIVIDER, CMD, TX, RX, STATUS = range(6)

ENABLE = 1 << 0
IRQ_DONE = 1 << 1
IRQ_ERR = 1 << 2
ABORT = 1 << 3

START = 1 << 0
STOP = 1 << 1
READ = 1 << 2
WRITE = 1 << 3
NACK = 1 << 4

BUSY = 1 << 0
BUS_ACTIVE = 1 << 1
DONE = 1 << 2
NACKED = 1 << 3
ARB_LOST = 1 << 4
REJECTED = 1 << 5

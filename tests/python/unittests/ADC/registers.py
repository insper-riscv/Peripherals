"""Register map and bit positions of the MAX 10 ADC peripheral."""

CTRL, MASK, PERIOD, STATUS = range(4)
CHANNEL_BASE = 8
CHANNELS = 18
TEMPERATURE = 17

ENABLE = 1 << 0
CONTINUOUS = 1 << 1
IRQ_ENABLE = 1 << 2
START = 1 << 3

BUSY = 1 << 0
DONE = 1 << 1
LATE = 1 << 2

SAMPLE_MASK = 0xFFF
VALID = 1 << 12
OVERRUN = 1 << 13

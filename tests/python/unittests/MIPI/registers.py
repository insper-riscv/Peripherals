"""Endereços de palavra e campos de bits do receptor de câmera MIPI."""

CTRL = 0
STATUS = 1
FRAME_COUNT = 2
CONFIG = 3
GEOMETRY = 4
RD_ADDR = 5
RD_DATA = 6
LAST_FRAME = 7
ERRORS = 8
INFO = 9

START = 1 << 0
FRAME_IRQ = 1 << 1
ERROR_IRQ = 1 << 2
ENABLE = 1 << 3

BUSY = 1 << 0
READY = 1 << 1
ERROR = 1 << 2
SEEN = 1 << 3

DT_FS = 0x00
DT_FE = 0x01
DT_LS = 0x02
DT_LE = 0x03
DT_RAW8 = 0x2A
DT_EMBEDDED = 0x12

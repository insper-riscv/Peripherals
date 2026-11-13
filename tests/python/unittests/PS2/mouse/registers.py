"""Endereços de palavra e campos de bits do mouse PS/2 nos testes."""

STATUS = 0
DX = 1
DY = 2
BUTTONS = 3
CONTROL = 4

NEW = 1 << 0
OVERFLOW = 1 << 1
ERROR = 1 << 2
STREAMING = 1 << 3

IRQ_ENABLE = 1 << 0
REINIT = 1 << 1

CMD_RESET = 0xFF
CMD_ENABLE = 0xF4
RSP_ACK = 0xFA
RSP_SELF_TEST = 0xAA
RSP_ID = 0x00

INIT_TIMEOUT = 200
PACKET_TIMEOUT = 50
ACC_MAX = 2**15 - 1
ACC_MIN = -(2**15)

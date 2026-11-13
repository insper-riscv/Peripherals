"""Word addresses and bit masks of the infrared receiver registers."""

CTRL = 0
STATUS = 1
DATA = 2
RAW_MARK = 3
RAW_SPACE = 4

CTRL_EN = 1 << 0
CTRL_FRAME_IE = 1 << 1
CTRL_ERR_IE = 1 << 2
CTRL_EXT_EN = 1 << 3
CTRL_RAW_IE = 1 << 4
CTRL_FLUSH = 1 << 5
CTRL_ALL = 0x1F
CTRL_DEFAULT = 0x0F

STAT_NOT_EMPTY = 1 << 0
STAT_FULL = 1 << 1
STAT_FRAME_ERR = 1 << 2
STAT_OVERFLOW = 1 << 3
STAT_LINE = 1 << 4
STAT_RAW_NEW = 1 << 5
STAT_LEVEL_SHIFT = 8

FRAME_REPEAT = 1 << 24
FRAME_EXT = 1 << 25

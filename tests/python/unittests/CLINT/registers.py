"""Word addresses of the CLINT registers, shared by its tests."""

MSIP = 0x0000 // 4
MTIMECMP_LO = 0x4000 // 4
MTIMECMP_HI = 0x4004 // 4
MTIME_LO = 0xBFF8 // 4
MTIME_HI = 0xBFFC // 4
MASK32 = 0xFFFFFFFF
MASK64 = (1 << 64) - 1

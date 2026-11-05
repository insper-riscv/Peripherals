"""Register addresses of the FLASH controller, shared by its tests."""

CMD, ADDR, STATUS, BUF_PTR, BUF_DATA = range(5)
RESERVED = (5, 6, 7)

# Command codes of the chip, written to CMD.
WREN, ERASE, PROGRAM, PROTECT, UNPROTECT = 1, 2, 3, 4, 5

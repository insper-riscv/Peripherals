"""Register addresses of the FLASH controller, shared by its tests."""

CMD, ADDR, STATUS, BUF_PTR, BUF_DATA, IRQ_ENABLE, IRQ_STATUS = range(7)
RESERVED = (7,)
IRQ_DONE, IRQ_REFUSED = 1, 2

# Command codes of the chip, written to CMD.
WREN, ERASE, PROGRAM, PROTECT, UNPROTECT = 1, 2, 3, 4, 5

"""GPIO_OPERATION_DECODER: the register map of the GPIO, address by address."""

import cocotb
from cocotb.triggers import Timer

# address -> (write-enable bit it raises on a write or None, wr_op, rd_sel)
# wr_en bits: 0 DIR, 1 LOAD_OUT, 2 BIT_OUT, 3 IRQ_MASK, 4 RISE_MASK, 5 FALL_MASK, 6 IRQ_CLR (read)
DIR, OUT_LOAD, OUT_SET, OUT_CLR, OUT_TGL = 0, 1, 2, 3, 4
IRQ_MASK, RISE_MASK, FALL_MASK, IRQ_STAT, PINS = 5, 6, 7, 8, 9
WRITE_BIT = {DIR: 0, OUT_LOAD: 1, OUT_SET: 2, OUT_CLR: 2, OUT_TGL: 2, IRQ_MASK: 3, RISE_MASK: 4, FALL_MASK: 5}
WR_OP = {OUT_LOAD: 0b00, OUT_SET: 0b01, OUT_CLR: 0b10, OUT_TGL: 0b11}
RD_SEL = {
    DIR: 0b000, OUT_LOAD: 0b001, OUT_SET: 0b001, OUT_CLR: 0b001, OUT_TGL: 0b001,
    PINS: 0b010, IRQ_STAT: 0b011, IRQ_MASK: 0b100, RISE_MASK: 0b101, FALL_MASK: 0b110,
}


async def _apply(dut, address, write, read):
    dut.address.value = address
    dut.write.value = write
    dut.read.value = read
    await Timer(1, unit="ns")
    return int(dut.wr_en.value), int(dut.wr_op.value), int(dut.rd_sel.value)


@cocotb.test()
async def test_writes_raise_one_enable(dut):
    for address in range(16):
        wr_en, wr_op, _ = await _apply(dut, address, 1, 0)
        want = 1 << WRITE_BIT[address] if address in WRITE_BIT else 0
        assert wr_en == want, f"write {address}: wr_en={wr_en:07b}, expected {want:07b}"
        assert wr_op == WR_OP.get(address, 0), f"write {address}: wr_op={wr_op:02b}"


@cocotb.test()
async def test_no_write_no_enable(dut):
    for address in range(16):
        wr_en, _, _ = await _apply(dut, address, 0, 0)
        assert wr_en == 0, f"idle {address}: wr_en={wr_en:07b}"


@cocotb.test()
async def test_only_reading_the_status_clears_it(dut):
    for address in range(16):
        wr_en, _, _ = await _apply(dut, address, 0, 1)
        want = 1 << 6 if address == IRQ_STAT else 0
        assert wr_en == want, f"read {address}: wr_en={wr_en:07b}, expected {want:07b}"


@cocotb.test()
async def test_read_select(dut):
    for address in range(16):
        _, _, rd_sel = await _apply(dut, address, 0, 1)
        assert rd_sel == RD_SEL.get(address, 0b111), f"address {address}: rd_sel={rd_sel:03b}"

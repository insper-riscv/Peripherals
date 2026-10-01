"""TIMER_OPERATION_DECODER: the register map of the timer, address by address."""

import cocotb
from cocotb.triggers import Timer

CONFIG, TIMER_LOAD, TIMER_RESET, TOP, DUTY, OVF_STATUS, PWM, PRESCALER = range(8)
# wr_en bits: 0 CONFIG, 1 LOAD_TIMER, 2 RESET, 3 LOAD_TOP, 4 LOAD_DUTY, 5 OVF_CLR (read), 6 PRESCALER
WRITE_BIT = {CONFIG: 0, TIMER_LOAD: 1, TIMER_RESET: 2, TOP: 3, DUTY: 4, PRESCALER: 6}
RD_SEL = {
    TIMER_LOAD: 0b000, TIMER_RESET: 0b000, TOP: 0b001, DUTY: 0b010, CONFIG: 0b011,
    PWM: 0b100, OVF_STATUS: 0b101, PRESCALER: 0b110,
}


async def _apply(dut, address, write, read):
    dut.address.value = address
    dut.write.value = write
    dut.read.value = read
    await Timer(1, unit="ns")
    return int(dut.wr_en.value), int(dut.cnt_sel.value), int(dut.rd_sel.value)


@cocotb.test()
async def test_writes_raise_one_enable(dut):
    for address in range(8):
        wr_en, _, _ = await _apply(dut, address, 1, 0)
        want = 1 << WRITE_BIT[address] if address in WRITE_BIT else 0
        assert wr_en == want, f"write {address}: wr_en={wr_en:07b}, expected {want:07b}"


@cocotb.test()
async def test_only_reading_the_status_clears_it(dut):
    for address in range(8):
        wr_en, _, _ = await _apply(dut, address, 0, 1)
        want = 1 << 5 if address == OVF_STATUS else 0
        assert wr_en == want, f"read {address}: wr_en={wr_en:07b}, expected {want:07b}"


@cocotb.test()
async def test_counter_input_selects_the_bus_only_when_loading(dut):
    for address in range(8):
        for write in (0, 1):
            _, cnt_sel, _ = await _apply(dut, address, write, 0)
            want = 1 if (address == TIMER_LOAD and write) else 0
            assert cnt_sel == want, f"address {address} write={write}: cnt_sel={cnt_sel}"


@cocotb.test()
async def test_read_select(dut):
    for address in range(8):
        _, _, rd_sel = await _apply(dut, address, 0, 1)
        assert rd_sel == RD_SEL[address], f"address {address}: rd_sel={rd_sel:03b}"

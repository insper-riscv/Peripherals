"""TIMER_OPERATION_DECODER: the register map of the timer."""

import cocotb
from cocotb.triggers import Timer

from tests.python.utils.dut import TimerDecoderDut

(
    CONFIG,
    TIMER_LOAD,
    TIMER_RESET,
    TOP,
    DUTY,
    OVF_STATUS,
    PWM,
    PRESCALER,
) = range(8)
ADDRESSES = 8
# wr_en bits: 0 CONFIG, 1 LOAD_TIMER, 2 RESET, 3 LOAD_TOP, 4 LOAD_DUTY,
# 5 OVF_CLR (read), 6 PRESCALER
OVF_CLEAR_BIT = 5
WRITE_BIT = {
    CONFIG: 0,
    TIMER_LOAD: 1,
    TIMER_RESET: 2,
    TOP: 3,
    DUTY: 4,
    PRESCALER: 6,
}
RD_SEL = {
    TIMER_LOAD: 0b000,
    TIMER_RESET: 0b000,
    TOP: 0b001,
    DUTY: 0b010,
    CONFIG: 0b011,
    PWM: 0b100,
    OVF_STATUS: 0b101,
    PRESCALER: 0b110,
}


async def _apply(
    dut: TimerDecoderDut, address: int, write: int, read: int
) -> tuple[int, int, int]:
    """Drive one bus operation and sample the decoder outputs.

    Parameters
    ----------
    dut : TimerDecoderDut
        The design under test.
    address : int
        Register address.
    write : int
        Value of the write strobe.
    read : int
        Value of the read strobe.

    Returns
    -------
    tuple[int, int, int]
        The wr_en, cnt_sel and rd_sel outputs.
    """
    dut.i_address.value = address
    dut.i_write.value = write
    dut.i_read.value = read
    await Timer(1, unit="ns")
    return (
        int(dut.o_wr_en.value),
        int(dut.o_cnt_sel.value),
        int(dut.o_rd_sel.value),
    )


@cocotb.test()
async def test_writes_raise_one_enable(dut: TimerDecoderDut) -> None:
    """A write raises the enable of its own register."""
    for address in range(ADDRESSES):
        wr_en, _, _ = await _apply(dut, address, 1, 0)
        want = 1 << WRITE_BIT[address] if address in WRITE_BIT else 0
        assert wr_en == want, (
            f"write {address}: wr_en={wr_en:07b}, expected {want:07b}"
        )


@cocotb.test()
async def test_only_reading_the_status_clears_it(
    dut: TimerDecoderDut,
) -> None:
    """Only a read of the overflow status raises its clear enable."""
    for address in range(ADDRESSES):
        wr_en, _, _ = await _apply(dut, address, 0, 1)
        want = 1 << OVF_CLEAR_BIT if address == OVF_STATUS else 0
        assert wr_en == want, (
            f"read {address}: wr_en={wr_en:07b}, expected {want:07b}"
        )


@cocotb.test()
async def test_counter_input_selects_the_bus_only_when_loading(
    dut: TimerDecoderDut,
) -> None:
    """The counter takes the bus only on a write to the load address."""
    for address in range(ADDRESSES):
        for write in (0, 1):
            _, cnt_sel, _ = await _apply(dut, address, write, 0)
            want = 1 if (address == TIMER_LOAD and write) else 0
            assert cnt_sel == want, (
                f"address {address} write={write}: cnt_sel={cnt_sel}"
            )


@cocotb.test()
async def test_read_select(dut: TimerDecoderDut) -> None:
    """Each address selects its own read source."""
    for address in range(ADDRESSES):
        _, _, rd_sel = await _apply(dut, address, 0, 1)
        assert rd_sel == RD_SEL[address], (
            f"address {address}: rd_sel={rd_sel:03b}"
        )

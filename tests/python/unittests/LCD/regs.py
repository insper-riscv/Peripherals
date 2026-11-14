"""lcd_regs: registradores, flags, interrupção e inserção."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.LCD import common as c
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdRegsDut

DELAY_RESET = 7
DELAY_LONG_RESET = 11
FIFO_DEPTH = 4
LEVEL_THREE = 3
BYTE_LOW = 0xA5
DELAY_VALUE = 0x123456
DELAY_LONG_VALUE = 0xABCDEF


def idle_inputs(dut: LcdRegsDut) -> None:
    """Deixa a fila e a camada física em repouso.

    Parameters
    ----------
    dut : LcdRegsDut
        Registradores sob teste.
    """
    dut.i_push_accepted.value = 1
    dut.i_fifo_full.value = 0
    dut.i_fifo_empty.value = 1
    dut.i_fifo_level.value = 0
    dut.i_phy_busy.value = 0
    dut.i_init_busy.value = 0
    dut.i_timeout.value = 0


async def setup(dut: LcdRegsDut) -> None:
    """Aplica o reset com as entradas em repouso.

    Parameters
    ----------
    dut : LcdRegsDut
        Registradores sob teste.
    """
    idle_inputs(dut)
    await bus.reset(dut, hold=3, period_ns=c.CLOCK_NS)


@cocotb.test()
async def reset_values(dut: LcdRegsDut) -> None:
    """Confira os valores de reset dos registradores e dos pinos."""
    await setup(dut)
    check(
        await bus.read(dut, c.CONTROL) == c.POLL_ENABLE | c.LCD_ON, "CONTROL"
    )
    check(await bus.read(dut, c.DELAY) == DELAY_RESET, "DELAY")
    check(await bus.read(dut, c.DELAY_LONG) == DELAY_LONG_RESET, "DELAY_LONG")
    check(await bus.read(dut, c.STATUS) == c.FIFO_EMPTY, "STATUS")
    check(int(dut.o_poll_enable.value) == 1, "espera pelo ocupado")
    check(
        int(dut.o_lcd_on.value) == 1 and int(dut.o_lcd_blon.value) == 0,
        "pinos",
    )
    check(int(dut.o_irq.value) == 0, "sem interrupção")


@cocotb.test()
async def push_decoding(dut: LcdRegsDut) -> None:
    """Só COMMAND e DATA pedem inserção, com RS e byte corretos."""
    await setup(dut)
    cases = {c.COMMAND: 0, c.DATA: 1, c.STATUS: None, c.CONTROL: None}
    for address, rs in cases.items():
        dut.i_address.value = address
        dut.i_data_in.value = 0x1A5
        dut.i_write.value = 1
        await bus.cycles(dut, 0)
        await Timer(1, unit="ns")
        want_push = rs is not None
        check(int(dut.o_push.value) == int(want_push), f"push em {address}")
        if want_push:
            check(int(dut.o_push_rs.value) == rs, f"RS em {address}")
            check(int(dut.o_push_data.value) == BYTE_LOW, "byte baixo")
        dut.i_write.value = 0
        await bus.cycles(dut, 1)
    dut.i_address.value = c.DATA
    dut.i_write.value = 0
    await Timer(1, unit="ns")
    check(int(dut.o_push.value) == 0, "sem escrita não há inserção")


@cocotb.test()
async def sticky_flags_and_clear(dut: LcdRegsDut) -> None:
    """Mantenha DROPPED e TIMEOUT até a escrita de 1."""
    await setup(dut)
    dut.i_push_accepted.value = 0
    await bus.write(dut, c.DATA, 0x41)
    check(c.flag(await bus.read(dut, c.STATUS), c.DROPPED), "DROPPED aceso")
    dut.i_push_accepted.value = 1
    dut.i_timeout.value = 1
    await bus.cycles(dut, 1)
    dut.i_timeout.value = 0
    status = await bus.read(dut, c.STATUS)
    check(
        c.flag(status, c.TIMEOUT) and c.flag(status, c.DROPPED),
        "as duas flags",
    )
    await bus.write(dut, c.STATUS, c.DROPPED)
    status = await bus.read(dut, c.STATUS)
    check(
        not c.flag(status, c.DROPPED) and c.flag(status, c.TIMEOUT),
        "limpa só DROPPED",
    )
    dut.i_timeout.value = 1
    await bus.write(dut, c.STATUS, c.TIMEOUT)
    dut.i_timeout.value = 0
    check(
        c.flag(await bus.read(dut, c.STATUS), c.TIMEOUT),
        "o evento vence a limpeza",
    )
    await bus.write(dut, c.STATUS, c.TIMEOUT)
    check(
        not c.flag(await bus.read(dut, c.STATUS), c.TIMEOUT), "TIMEOUT limpo"
    )


@cocotb.test()
async def status_and_interrupt(dut: LcdRegsDut) -> None:
    """Reflita a fila e a camada física em STATUS e na interrupção."""
    await setup(dut)
    await bus.write(dut, c.CONTROL, c.IRQ_ENABLE | c.LCD_ON)
    check(await bus.read(dut, c.CONTROL) == c.IRQ_ENABLE | c.LCD_ON, "CONTROL")
    check(int(dut.o_poll_enable.value) == 0, "poll desligado")
    check(int(dut.o_irq.value) == 1, "fila vazia pede")
    dut.i_init_busy.value = 1
    await Timer(1, unit="ns")
    check(int(dut.o_irq.value) == 0, "durante a inicialização não pede")
    status = await bus.read(dut, c.STATUS)
    check(
        c.flag(status, c.INIT_BUSY) and c.flag(status, c.BUSY),
        "INIT_BUSY e BUSY",
    )
    dut.i_init_busy.value = 0
    dut.i_fifo_empty.value = 0
    dut.i_fifo_level.value = LEVEL_THREE
    await Timer(1, unit="ns")
    check(int(dut.o_irq.value) == 0, "fila com palavras não pede")
    status = await bus.read(dut, c.STATUS)
    check(
        c.flag(status, c.BUSY) and not c.flag(status, c.FIFO_EMPTY),
        "BUSY pela fila",
    )
    check(status >> c.LEVEL_SHIFT & c.LEVEL_MASK == LEVEL_THREE, "nível")
    dut.i_fifo_level.value = FIFO_DEPTH
    dut.i_fifo_full.value = 1
    check(c.flag(await bus.read(dut, c.STATUS), c.FIFO_FULL), "FIFO_FULL")
    dut.i_fifo_full.value = 0
    dut.i_fifo_empty.value = 1
    dut.i_fifo_level.value = 0
    dut.i_phy_busy.value = 1
    check(
        c.flag(await bus.read(dut, c.STATUS), c.BUSY),
        "BUSY pela camada física",
    )


@cocotb.test()
async def delays_and_pins(dut: LcdRegsDut) -> None:
    """DELAY, DELAY_LONG e os pinos guardam o que foi escrito."""
    await setup(dut)
    await bus.write(dut, c.DELAY, DELAY_VALUE)
    await bus.write(dut, c.DELAY_LONG, DELAY_LONG_VALUE)
    check(await bus.read(dut, c.DELAY) == DELAY_VALUE, "DELAY")
    check(await bus.read(dut, c.DELAY_LONG) == DELAY_LONG_VALUE, "DELAY_LONG")
    check(int(dut.o_delay.value) == DELAY_VALUE, "saída DELAY")
    await bus.write(dut, c.CONTROL, c.BACKLIGHT | c.POLL_ENABLE)
    check(
        int(dut.o_lcd_on.value) == 0 and int(dut.o_lcd_blon.value) == 1,
        "pinos",
    )
    for address in (c.COMMAND, c.DATA, 6, 7):
        check(await bus.read(dut, address) == 0, f"endereço {address}")

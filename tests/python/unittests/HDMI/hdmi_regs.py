"""Registradores do HDMI: mapa, interrupções e pulso de reinício."""

from typing import Protocol

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.HDMI.hdmi_bench import (
    HDMI_MODE as MODE,
)
from tests.python.unittests.HDMI.hdmi_bench import (
    HDMI_STATUS as STATUS,
)
from tests.python.unittests.HDMI.hdmi_bench import (
    IRQ_EN,
    IRQ_PEND,
    PIXEL_KHZ,
    SEQ_COUNT,
    SEQ_CTRL,
)
from tests.python.utils.check import check

CLOCK_NS = 10
MODE_VALUE = 0x304
STATUS_VALUE = 0b11100
COUNT_VALUE = 0x040103
PIXEL_VALUE = 74250
PEND_INT = 0b10


class RegsDut(Protocol):
    """Sinais dos registradores do HDMI."""

    i_clk: LogicObject
    i_rst: LogicObject
    i_data_in: LogicArrayObject
    i_address: LogicArrayObject
    i_write: LogicObject
    o_data_out: LogicArrayObject
    i_vblank: LogicObject
    i_int_active: LogicObject
    i_seq_busy: LogicObject
    i_seq_done: LogicObject
    i_seq_nack: LogicObject
    i_seq_sent: LogicArrayObject
    i_seq_nacks: LogicArrayObject
    o_seq_start: LogicObject
    o_irq: LogicObject


async def start(dut: RegsDut) -> None:
    """Inicia o clock e aplica o reset.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    for name in (
        "i_write",
        "i_address",
        "i_data_in",
        "i_vblank",
        "i_int_active",
        "i_seq_busy",
        "i_seq_done",
        "i_seq_nack",
        "i_seq_sent",
        "i_seq_nacks",
    ):
        getattr(dut, name).value = 0
    dut.i_rst.value = 1
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0


async def write(dut: RegsDut, address: int, data: int) -> None:
    """Escreve uma palavra em um ciclo.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    address : int
        Endereço de palavra.
    data : int
        Dado de 32 bits.
    """
    dut.i_address.value = address
    dut.i_data_in.value = data
    dut.i_write.value = 1
    await cycle(dut)
    dut.i_write.value = 0


async def cycle(dut: RegsDut) -> None:
    """Espera um ciclo de clock.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    """
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def read(dut: RegsDut, address: int) -> int:
    """Lê uma palavra, combinacional no endereço.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    address : int
        Endereço de palavra.

    Returns
    -------
    int
        O dado lido.
    """
    dut.i_address.value = address
    await Timer(1, unit="ns")
    return int(dut.o_data_out.value)


@cocotb.test()
async def test_read_map(dut: RegsDut) -> None:
    """Cada palavra lê o que o contrato diz e as outras leem zero."""
    await start(dut)
    dut.i_seq_sent.value = 3
    dut.i_seq_nacks.value = 1
    dut.i_seq_done.value = 1
    dut.i_seq_nack.value = 1
    check(
        await read(dut, MODE) == MODE_VALUE, "modo 4, sincronismos positivos"
    )
    check(
        await read(dut, STATUS) == STATUS_VALUE, "estado: presente, NACK, fim"
    )
    check(
        await read(dut, SEQ_COUNT) == COUNT_VALUE, "contador do sequenciador"
    )
    check(await read(dut, PIXEL_KHZ) == PIXEL_VALUE, "clock de pixel em kHz")
    for address in (0, 5, 7, 15, 100, 255, 256, 1024, 2047):
        check(await read(dut, address) == 0, f"palavra {address}")
    dut.i_int_active.value = 1
    check(await read(dut, STATUS) & 1 == 1, "pino de interrupção ativo")


@cocotb.test()
async def test_interrupts(dut: RegsDut) -> None:
    """Eventos ficam pendentes, a máscara decide o_irq, 1 limpa."""
    await start(dut)
    dut.i_vblank.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(await read(dut, IRQ_PEND) == 0b01, "fim de quadro pendente")
    check(int(dut.o_irq.value) == 0, "sem máscara não há interrupção")
    await write(dut, IRQ_EN, 0b01)
    check(int(dut.o_irq.value) == 1, "a máscara libera a interrupção")
    await write(dut, IRQ_PEND, 0b01)
    check(await read(dut, IRQ_PEND) == 0, "escrever 1 limpa")
    check(int(dut.o_irq.value) == 0, "a interrupção cai")
    dut.i_int_active.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(await read(dut, IRQ_PEND) == PEND_INT, "ativação do pino pendente")
    await write(dut, IRQ_PEND, 0b10)
    check(await read(dut, IRQ_PEND) == 0, "limpa com o pino ainda ativo")
    await write(dut, IRQ_PEND, 0b00)
    check(await read(dut, IRQ_EN) == 0b01, "a máscara não muda")


@cocotb.test()
async def test_restart_pulse(dut: RegsDut) -> None:
    """Só a escrita do bit 0 na palavra 12 gera o pulso de reinício."""
    await start(dut)
    await write(dut, SEQ_CTRL, 0b10)
    check(int(dut.o_seq_start.value) == 0, "o bit 1 não reinicia")
    dut.i_address.value = SEQ_CTRL
    dut.i_data_in.value = 1
    dut.i_write.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_write.value = 0
    check(int(dut.o_seq_start.value) == 1, "o pulso sobe")
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check(int(dut.o_seq_start.value) == 0, "o pulso dura um ciclo")

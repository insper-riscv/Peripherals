"""Registradores do periférico de captura de TV."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.TV.registers import (
    BUSY,
    CTRL,
    DECIMATION,
    DECODER_RUN,
    ERROR,
    ERROR_IRQ,
    FORMAT,
    FRAME_COUNT,
    FRAME_IRQ,
    GEOMETRY,
    PRESENT,
    RD_ADDR,
    RD_DATA,
    READY,
    SOURCE,
    START,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.check import check_equal
from tests.python.utils.dut import TvRegsDut

WIDTH = 4
HEIGHT = 4
DEPTH = WIDTH * HEIGHT // 2
MEMORY = [0xA0000000 | 0x111 * n for n in range(DEPTH)]


async def memory_model(dut: TvRegsDut) -> None:
    """Responda à leitura com a palavra do endereço, registrada.

    Parameters
    ----------
    dut : TvRegsDut
        Projeto sob teste.
    """
    while True:
        await RisingEdge(dut.i_clk)
        address = int(dut.o_rd_addr.value)
        await Timer(1, unit="ns")
        dut.i_rd_data.value = MEMORY[address % DEPTH]


async def start(dut: TvRegsDut) -> None:
    """Zere as entradas do outro domínio e reinicie.

    Parameters
    ----------
    dut : TvRegsDut
        Projeto sob teste.
    """
    dut.i_present.value = 0
    dut.i_done_tog.value = 0
    dut.i_cap_ok.value = 0
    dut.i_err_tog.value = 0
    dut.i_rd_data.value = MEMORY[0]
    await bus.reset(dut)
    cocotb.start_soon(memory_model(dut))


async def toggle(dut: TvRegsDut, name: str, ok: int = 1) -> None:
    """Inverta um toggle do outro domínio e espere dois ciclos.

    Parameters
    ----------
    dut : TvRegsDut
        Projeto sob teste.
    name : str
        `done` ou `err`.
    ok : int
        Resultado da captura que acompanha o fim.
    """
    dut.i_cap_ok.value = ok
    signal = dut.i_done_tog if name == "done" else dut.i_err_tog
    signal.value = 1 - int(signal.value)
    await bus.cycles(dut, 2)


@cocotb.test()
async def test_reset_values(dut: TvRegsDut) -> None:
    """Valores de reset e registradores de leitura."""
    await start(dut)
    for address in (CTRL, STATUS, FRAME_COUNT, FORMAT, RD_ADDR):
        check_equal(await bus.read(dut, address), 0)
    check_equal(await bus.read(dut, DECIMATION), 0x0101)
    check_equal(await bus.read(dut, GEOMETRY), HEIGHT << 16 | WIDTH)
    check_equal(await bus.read(dut, SOURCE), 480 << 16 | 720)
    check_equal(await bus.read(dut, 15), 0)
    check_equal(int(dut.o_start_tog.value), 0)
    check_equal(int(dut.o_irq.value), 0)
    dut.i_present.value = 1
    await bus.cycles(dut, 1)
    check_equal(await bus.read(dut, STATUS), PRESENT)


@cocotb.test()
async def test_start_and_done(dut: TvRegsDut) -> None:
    """Um início inverte o toggle uma vez; o fim traz o resultado."""
    await start(dut)
    await bus.write(dut, CTRL, START)
    check_equal(int(dut.o_start_tog.value), 1)
    check_equal(await bus.read(dut, STATUS), BUSY)
    await bus.write(dut, CTRL, START)
    check_equal(int(dut.o_start_tog.value), 1)
    await toggle(dut, "done", ok=1)
    check_equal(await bus.read(dut, STATUS), READY)
    check_equal(await bus.read(dut, FRAME_COUNT), 1)
    await bus.write(dut, CTRL, START)
    check_equal(int(dut.o_start_tog.value), 0)
    check_equal(await bus.read(dut, STATUS), BUSY)
    await toggle(dut, "done", ok=0)
    check_equal(await bus.read(dut, STATUS), ERROR)
    check_equal(await bus.read(dut, FRAME_COUNT), 1)
    await bus.write(dut, STATUS, ERROR)
    check_equal(await bus.read(dut, STATUS), 0)
    await toggle(dut, "done", ok=1)
    check_equal(await bus.read(dut, STATUS), 0)


@cocotb.test()
async def test_configuration_lock(dut: TvRegsDut) -> None:
    """A configuração só muda com a captura parada, e 0 vira 1."""
    await start(dut)
    await bus.write(dut, DECIMATION, 0x0304)
    await bus.write(dut, FORMAT, 0b101)
    check_equal(int(dut.o_x_div.value), 4)
    check_equal(int(dut.o_y_div.value), 3)
    check_equal(int(dut.o_field_sel.value), 2)
    check_equal(int(dut.o_format.value), 1)
    await bus.write(dut, DECIMATION, 0)
    check_equal(await bus.read(dut, DECIMATION), 0x0101)
    await bus.write(dut, DECIMATION, 0x0304)
    await bus.write(dut, CTRL, START)
    await bus.write(dut, DECIMATION, 0x0909)
    await bus.write(dut, FORMAT, 0)
    check_equal(await bus.read(dut, DECIMATION), 0x0304)
    check_equal(await bus.read(dut, FORMAT), 0b101)
    await toggle(dut, "done")
    await bus.write(dut, FORMAT, 0)
    check_equal(await bus.read(dut, FORMAT), 0)


@cocotb.test()
async def test_interrupt_and_errors(dut: TvRegsDut) -> None:
    """A interrupção segue as máscaras; erro do receptor e fim solto."""
    await start(dut)
    await toggle(dut, "done")
    check_equal(await bus.read(dut, STATUS), 0)
    await bus.write(dut, CTRL, START | FRAME_IRQ | ERROR_IRQ | DECODER_RUN)
    check_equal(await bus.read(dut, CTRL), FRAME_IRQ | ERROR_IRQ | DECODER_RUN)
    check_equal(int(dut.o_decoder_run.value), 1)
    await toggle(dut, "done")
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, STATUS, READY)
    check_equal(int(dut.o_irq.value), 0)
    await toggle(dut, "err")
    check_equal(await bus.read(dut, STATUS), ERROR)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, CTRL, FRAME_IRQ)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, STATUS, ERROR)
    check_equal(await bus.read(dut, STATUS), 0)


@cocotb.test()
async def test_read_pointer(dut: TvRegsDut) -> None:
    """O ponteiro lê em sequência, dá a volta e recusa valor fora."""
    await start(dut)
    await bus.write(dut, RD_ADDR, 5)
    for word in (5, 6, 7, 0, 1):
        check_equal(await bus.read(dut, RD_DATA), MEMORY[word])
    check_equal(await bus.read(dut, RD_ADDR), 2)
    await bus.write(dut, RD_ADDR, DEPTH)
    check_equal(await bus.read(dut, RD_ADDR), 2)
    await bus.write(dut, RD_ADDR, 0xFFFFFFFF)
    check_equal(await bus.read(dut, RD_ADDR), 2)
    await bus.write(dut, RD_ADDR, 3)
    check_equal(await bus.read(dut, RD_ADDR), 3)
    check_equal(await bus.read(dut, STATUS), 0)
    check_equal(await bus.read(dut, RD_ADDR), 3)

"""Fila síncrona usada pelas interfaces serial de recepção e transmissão."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.check import check
from tests.python.utils.dut import UartFifoDut

DEPTH = 4


async def setup(dut: UartFifoDut) -> None:
    """Inicialize o clock, as entradas e o estado da fila.

    Parameters
    ----------
    dut : UartFifoDut
        Fila exercitada pelo teste.
    """
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_push.value = 0
    dut.i_pop.value = 0
    dut.i_push_data.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def request(
    dut: UartFifoDut,
    *,
    push: bool = False,
    value: int = 0,
    pop: bool = False,
) -> tuple[int, int, int]:
    """Aplique pedidos por um ciclo e devolva a resposta anterior à borda.

    Parameters
    ----------
    dut : UartFifoDut
        Fila exercitada pelo teste.
    push : bool
        Solicita uma inserção.
    value : int
        Palavra apresentada para inserção.
    pop : bool
        Solicita uma remoção.

    Returns
    -------
    tuple[int, int, int]
        Aceitação da inserção, aceitação da remoção e palavra removida.
    """
    dut.i_push.value = int(push)
    dut.i_push_data.value = value
    dut.i_pop.value = int(pop)
    await Timer(1, unit="ns")

    result = (
        int(dut.o_push_accepted.value),
        int(dut.o_pop_accepted.value),
        int(dut.o_pop_data.value),
    )

    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_push.value = 0
    dut.i_pop.value = 0
    return result


async def pop_value(dut: UartFifoDut) -> int:
    """Remova e devolva a palavra mais antiga.

    Parameters
    ----------
    dut : UartFifoDut
        Fila exercitada pelo teste.

    Returns
    -------
    int
        Palavra removida.
    """
    push_accepted, pop_accepted, value = await request(dut, pop=True)
    check(push_accepted == 0)
    check(pop_accepted == 1)
    return value


@cocotb.test()
async def test_reset_and_rejected_empty_pop(dut: UartFifoDut) -> None:
    """O reset esvazia a fila e uma remoção vazia é rejeitada."""
    await setup(dut)

    check(int(dut.o_empty.value) == 1)
    check(int(dut.o_full.value) == 0)
    check(int(dut.o_level.value) == 0)
    check(int(dut.o_pop_data.value) == 0)

    check(await request(dut, pop=True) == (0, 0, 0))
    check(int(dut.o_empty.value) == 1)
    check(int(dut.o_level.value) == 0)


@cocotb.test()
async def test_fill_order_and_rejected_full_push(dut: UartFifoDut) -> None:
    """A fila preserva a ordem e rejeita uma inserção quando cheia."""
    await setup(dut)

    for index in range(DEPTH):
        accepted, popped, _ = await request(
            dut, push=True, value=0x20 + index
        )
        check(accepted == 1)
        check(popped == 0)
        check(int(dut.o_level.value) == index + 1)

    check(int(dut.o_full.value) == 1)
    accepted, popped, head = await request(dut, push=True, value=0xFF)
    check((accepted, popped, head) == (0, 0, 0x20))
    check(int(dut.o_level.value) == DEPTH)

    values = [await pop_value(dut) for _ in range(DEPTH)]
    check(values == [0x20, 0x21, 0x22, 0x23])
    check(int(dut.o_empty.value) == 1)


@cocotb.test()
async def test_pointer_wraparound_preserves_order(dut: UartFifoDut) -> None:
    """Os ponteiros circulares não alteram a ordem das palavras."""
    await setup(dut)

    for value in (0x10, 0x11, 0x12, 0x13):
        await request(dut, push=True, value=value)

    check(await pop_value(dut) == 0x10)
    check(await pop_value(dut) == 0x11)
    await request(dut, push=True, value=0x14)
    await request(dut, push=True, value=0x15)

    values = [await pop_value(dut) for _ in range(DEPTH)]
    check(values == [0x12, 0x13, 0x14, 0x15])


@cocotb.test()
async def test_simultaneous_push_and_pop_boundaries(
    dut: UartFifoDut,
) -> None:
    """Inserção e remoção simultâneas obedecem aos limites da fila."""
    await setup(dut)

    result = await request(dut, push=True, value=0x31, pop=True)
    check(result == (1, 0, 0))
    check(int(dut.o_level.value) == 1)
    check(await pop_value(dut) == 0x31)

    for value in (0x40, 0x41, 0x42, 0x43):
        await request(dut, push=True, value=value)

    result = await request(dut, push=True, value=0x44, pop=True)
    check(result == (1, 1, 0x40))
    check(int(dut.o_full.value) == 1)
    check(int(dut.o_level.value) == DEPTH)
    values = [await pop_value(dut) for _ in range(DEPTH)]
    check(values == [0x41, 0x42, 0x43, 0x44])

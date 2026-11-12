"""Acumulador saturado de um eixo do mouse PS/2."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.PS2.mouse.registers import ACC_MAX, ACC_MIN
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import AxisAccumulatorDut

DELTA_BITS = 9


async def add(dut: AxisAccumulatorDut, delta: int, clear: int = 0) -> int:
    """Adicione um deslocamento num ciclo e devolva a saturação.

    Parameters
    ----------
    dut : AxisAccumulatorDut
        Projeto sob teste.
    delta : int
        Deslocamento com sinal.
    clear : int
        Valor da entrada de limpeza no mesmo ciclo.

    Returns
    -------
    int
        Aviso de saturação visto antes da borda.
    """
    dut.i_delta.value = delta & ((1 << DELTA_BITS) - 1)
    dut.i_add_valid.value = 1
    dut.i_clear.value = clear
    await Timer(1, unit="ns")
    saturated = int(dut.o_saturated.value)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_add_valid.value = 0
    dut.i_clear.value = 0
    return saturated


def value(dut: AxisAccumulatorDut) -> int:
    """Devolva o valor acumulado como número com sinal.

    Parameters
    ----------
    dut : AxisAccumulatorDut
        Projeto sob teste.

    Returns
    -------
    int
        Valor acumulado com sinal.
    """
    raw = int(dut.o_value.value)
    return raw - (1 << 16) if raw & (1 << 15) else raw


async def start(dut: AxisAccumulatorDut) -> None:
    """Reinicie o projeto com as entradas paradas.

    Parameters
    ----------
    dut : AxisAccumulatorDut
        Projeto sob teste.
    """
    dut.i_add_valid.value = 0
    dut.i_clear.value = 0
    dut.i_delta.value = 0
    await bus.hold_reset(dut)


@cocotb.test()
async def test_add_and_clear(dut: AxisAccumulatorDut) -> None:
    """Os deslocamentos se somam e a limpeza zera o valor."""
    await start(dut)
    check(value(dut) == 0)
    await add(dut, 10)
    await add(dut, -25)
    check_equal(value(dut), -15)
    dut.i_clear.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_clear.value = 0
    check(value(dut) == 0)


@cocotb.test()
async def test_clear_with_add(dut: AxisAccumulatorDut) -> None:
    """Um deslocamento no ciclo da limpeza é mantido."""
    await start(dut)
    await add(dut, 40)
    await add(dut, 7, clear=1)
    check_equal(value(dut), 7)


@cocotb.test()
async def test_saturates_both_ways(dut: AxisAccumulatorDut) -> None:
    """O valor para nos limites e o aviso marca o corte."""
    await start(dut)
    flags = [await add(dut, 255) for _ in range(ACC_MAX // 255 + 2)]
    check(value(dut) == ACC_MAX)
    check(flags[-1] == 1 and flags[0] == 0)
    flags = [await add(dut, -256) for _ in range(ACC_MAX // 128 + 3)]
    check(value(dut) == ACC_MIN)
    check(flags[-1] == 1)
    await add(dut, 5)
    check(value(dut) == ACC_MIN + 5)

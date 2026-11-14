"""Escritor I2C: transações de escrita, confirmação e temporização."""

from typing import Protocol

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.HDMI.adv7513 import (
    SLAVE_ADDRESS,
    Adv7513Model,
    I2cPins,
    Write,
    start_model,
)
from tests.python.utils.check import check

CLOCK_NS = 250
TIMEOUT_CYCLES = 3000
SCL_PERIOD_NS = 10_000
SCL_TOLERANCE_NS = 100
MIN_PULSES = 26


class WriterDut(Protocol):
    """Sinais do escritor I2C."""

    i_clk: LogicObject
    i_rst: LogicObject
    i_start: LogicObject
    i_reg: LogicArrayObject
    i_value: LogicArrayObject
    o_busy: LogicObject
    o_done: LogicObject
    o_nack: LogicObject
    i_sda: LogicObject
    o_sda_out: LogicObject
    o_sda_oe: LogicObject
    o_scl_out: LogicObject
    o_scl_oe: LogicObject


async def start(dut: WriterDut, **model_args: object) -> Adv7513Model:
    """Inicia o clock, o modelo do escravo e solta o reset.

    Parameters
    ----------
    dut : WriterDut
        Escritor sob teste.
    **model_args : object
        Campos extras do modelo do escravo.

    Returns
    -------
    Adv7513Model
        O modelo em execução.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    model = Adv7513Model(I2cPins(dut.o_scl_oe, dut.o_sda_oe, dut.i_sda))
    for name, value in model_args.items():
        setattr(model, name, value)
    start_model(model)
    dut.i_rst.value = 1
    dut.i_start.value = 0
    dut.i_reg.value = 0
    dut.i_value.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    return model


async def write(dut: WriterDut, register: int, value: int) -> bool:
    """Pede uma escrita e espera o fim da transação.

    Parameters
    ----------
    dut : WriterDut
        Escritor sob teste.
    register : int
        Registrador do escravo.
    value : int
        Valor a escrever.

    Returns
    -------
    bool
        O valor de o_nack no pulso de fim.
    """
    dut.i_reg.value = register
    dut.i_value.value = value
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_start.value = 0
    for _ in range(TIMEOUT_CYCLES):
        await RisingEdge(dut.i_clk)
        if int(dut.o_done.value):
            nack = bool(int(dut.o_nack.value))
            await Timer(1, unit="ns")
            return nack
    message = "a transação não terminou"
    raise AssertionError(message)


def check_bus(dut: WriterDut, model: Adv7513Model) -> None:
    """Conferir o repouso, o dreno aberto e o período de SCL.

    Parameters
    ----------
    dut : WriterDut
        Escritor sob teste.
    model : Adv7513Model
        Modelo do escravo.
    """
    check(not model.errors, f"violações do protocolo: {model.errors}")
    check(int(dut.o_sda_out.value) == 0, "o_sda_out deve ser zero")
    check(int(dut.o_scl_out.value) == 0, "o_scl_out deve ser zero")
    check(int(dut.o_busy.value) == 0, "ocupado depois do fim")
    check(int(dut.o_sda_oe.value) == 0, "SDA liberada no repouso")
    check(int(dut.o_scl_oe.value) == 0, "SCL liberada no repouso")
    for period in (p for p in model.scl_periods_ns if p < 2 * SCL_PERIOD_NS):
        check(
            abs(period - SCL_PERIOD_NS) <= SCL_TOLERANCE_NS,
            f"período de SCL {period} ns fora de 100 kHz",
        )


@cocotb.test()
async def test_single_write(dut: WriterDut) -> None:
    """Uma escrita sai com endereço, registrador e valor corretos."""
    model = await start(dut)
    nack = await write(dut, 0x98, 0x03)
    check(not nack, "o escravo confirmou, o_nack deve ser zero")
    check(
        model.writes == [Write(SLAVE_ADDRESS, 0x98, 0x03, True)],
        f"escritas vistas: {model.writes}",
    )
    check(len(model.scl_periods_ns) >= MIN_PULSES, "faltam pulsos de SCL")
    check_bus(dut, model)


@cocotb.test()
async def test_back_to_back_writes(dut: WriterDut) -> None:
    """Escritas seguidas mantêm a ordem e o valor de cada uma."""
    model = await start(dut)
    sent = [(0x01, 0x00), (0xFF, 0xA5), (0x00, 0xFF), (0x7E, 0x80)]
    for register, value in sent:
        check(not await write(dut, register, value), "sem NACK esperado")
    got = [(w.register, w.value) for w in model.writes]
    check(got == sent, f"escritas vistas: {got}")
    check_bus(dut, model)


@cocotb.test()
async def test_nack_is_reported_and_cleared(dut: WriterDut) -> None:
    """A falta de ACK sobe em o_nack e some no pedido seguinte."""
    model = await start(dut, nack_registers={0x15})
    check(await write(dut, 0x15, 0x20), "NACK do valor deve ser visto")
    check(not await write(dut, 0x16, 0x30), "o_nack limpa no pedido seguinte")
    check(
        [w.acked for w in model.writes] == [False, True],
        f"escritas vistas: {model.writes}",
    )
    check_bus(dut, model)


@cocotb.test()
async def test_wrong_device_is_nack(dut: WriterDut) -> None:
    """Um escravo em outro endereço não confirma e o_nack sobe."""
    model = await start(dut, address=0x3D)
    check(await write(dut, 0x98, 0x03), "o endereço não foi confirmado")
    check(len(model.writes) == 1, "a transação segue até a parada")
    check_bus(dut, model)


@cocotb.test()
async def test_start_while_busy_is_ignored(dut: WriterDut) -> None:
    """Um pedido durante a transação não gera outra escrita."""
    model = await start(dut)
    dut.i_reg.value = 0x42
    dut.i_value.value = 0x24
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_reg.value = 0x99
    dut.i_value.value = 0x99
    for _ in range(40):
        await RisingEdge(dut.i_clk)
    dut.i_start.value = 0
    for _ in range(TIMEOUT_CYCLES):
        await RisingEdge(dut.i_clk)
    check(
        [(w.register, w.value) for w in model.writes] == [(0x42, 0x24)],
        f"escritas vistas: {model.writes}",
    )
    check_bus(dut, model)

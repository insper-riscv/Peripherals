"""PS2_MOUSE_DECODER: inicialização e pacotes, byte a byte."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.PS2.mouse.byte_driver import (
    expect_tx,
    initialize,
    reset_idle,
    send_byte,
    send_packet,
    send_rx_error,
)
from tests.python.unittests.PS2.mouse.registers import CMD_RESET, INIT_TIMEOUT
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MouseDecoderDut

DELTA_MASK = 0x1FF
BUTTONS_LEFT_MIDDLE = 0b101
DX_VALUE = 37
DY_VALUE = -90
MAX_DELTA = 255
MIN_DELTA = -256


async def start(dut: MouseDecoderDut) -> None:
    """Reinicie o decodificador com as entradas paradas.

    Parameters
    ----------
    dut : MouseDecoderDut
        Projeto sob teste.
    """
    dut.i_restart.value = 0
    await reset_idle(dut)


async def packet_pulse(dut: MouseDecoderDut) -> int:
    """Conte os ciclos em que o pulso de pacote fica alto.

    Parameters
    ----------
    dut : MouseDecoderDut
        Projeto sob teste.

    Returns
    -------
    int
        Quantos ciclos seguidos o pulso ficou alto.
    """
    width = int(dut.o_packet_valid.value)
    for _ in range(3):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        width += int(dut.o_packet_valid.value)
    return width


def signed9(value: int) -> int:
    """Interprete um deslocamento de 9 bits como número com sinal.

    Parameters
    ----------
    value : int
        Valor bruto de 9 bits.

    Returns
    -------
    int
        Valor com sinal.
    """
    return value - (1 << 9) if value & (1 << 8) else value


@cocotb.test()
async def test_streaming_flag(dut: MouseDecoderDut) -> None:
    """O streaming sobe só depois de toda a troca de respostas."""
    await start(dut)
    check(int(dut.o_streaming.value) == 0)
    await initialize(dut)
    await bus.cycles(dut, 1)
    check(int(dut.o_streaming.value) == 1)
    dut.i_restart.value = 1
    await bus.cycles(dut, 1)
    dut.i_restart.value = 0
    check(int(dut.o_streaming.value) == 0)
    await expect_tx(dut, CMD_RESET)


@cocotb.test()
async def test_packet_fields(dut: MouseDecoderDut) -> None:
    """Um pacote dá um pulso e deixa botões e deslocamentos estáveis."""
    await start(dut)
    await initialize(dut)
    await send_packet(dut, DX_VALUE, DY_VALUE, buttons=BUTTONS_LEFT_MIDDLE)
    check_equal(await packet_pulse(dut), 1)
    check_equal(int(dut.o_buttons.value), BUTTONS_LEFT_MIDDLE)
    check_equal(signed9(int(dut.o_dx.value)), DX_VALUE)
    check_equal(signed9(int(dut.o_dy.value)), DY_VALUE)
    check(int(dut.o_overflow.value) == 0)


@cocotb.test()
async def test_overflow_clips(dut: MouseDecoderDut) -> None:
    """Um bit de estouro corta o eixo no limite do seu sinal."""
    await start(dut)
    await initialize(dut)
    await send_packet(dut, 1, -1, overflow=0b11)
    await packet_pulse(dut)
    check_equal(signed9(int(dut.o_dx.value)), MAX_DELTA)
    check_equal(signed9(int(dut.o_dy.value)), MIN_DELTA)
    check(int(dut.o_overflow.value) == 1)


@cocotb.test()
async def test_error_pulses(dut: MouseDecoderDut) -> None:
    """Um primeiro byte ruim e um erro de quadro dão um pulso cada."""
    await start(dut)
    await initialize(dut)
    pulses = 0
    await send_byte(dut, 0x00)
    pulses += int(dut.o_error.value)
    await send_rx_error(dut)
    pulses += int(dut.o_error.value)
    await bus.cycles(dut, 2)
    check_equal(pulses, 2)
    check(int(dut.o_error.value) == 0)


@cocotb.test()
async def test_init_silence_restarts(dut: MouseDecoderDut) -> None:
    """O silêncio após o reset envia o comando de reset de novo."""
    await start(dut)
    await expect_tx(dut, CMD_RESET)
    await bus.cycles(dut, INIT_TIMEOUT + 10)
    await expect_tx(dut, CMD_RESET)

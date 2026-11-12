"""Teclado PS/2: fila, registradores, erros, comandos e interrupção."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import Ps2KeyboardTbDut
from tests.python.utils.ps2 import (
    Ps2Lines,
    device_receive,
    device_send,
    frame_bits,
)

DATA, STATUS, COMMAND, CONTROL = range(4)
RX_VALID = 1 << 0
TX_READY = 1 << 1
RX_OVERFLOW = 1 << 2
RX_ERROR = 1 << 3
RX_FULL = 1 << 4
TX_DROPPED = 1 << 5
RX_LEVEL_SHIFT = 8
LEVEL_MASK = 0xFF
RX_IRQ_ENABLE = 1 << 0
ERROR_IRQ_ENABLE = 1 << 1

FIFO_DEPTH = 4
MAKE_A = 0x1C
BREAK_PREFIX = 0xF0
EXTENDED_PREFIX = 0xE0
EXTENDED_UP = 0x75
RESET_COMMAND = 0xFF
SET_LEDS = 0xED
LEDS_ARGUMENT = 0x02
SETTLE_CYCLES = 200
POLL_LIMIT = 4000


def lines_of(dut: Ps2KeyboardTbDut) -> Ps2Lines:
    """Agrupe as linhas do conector do testbench.

    Parameters
    ----------
    dut : Ps2KeyboardTbDut
        Testbench exercitado.

    Returns
    -------
    Ps2Lines
        Linhas do lado do dispositivo.
    """
    return Ps2Lines(
        clk_low=dut.i_dev_clk_low0,
        dat_low=dut.i_dev_dat_low0,
        clk=dut.o_clk0,
        dat=dut.o_dat0,
    )


async def setup(dut: Ps2KeyboardTbDut) -> Ps2Lines:
    """Solte as linhas e reinicie o periférico.

    Parameters
    ----------
    dut : Ps2KeyboardTbDut
        Testbench exercitado.

    Returns
    -------
    Ps2Lines
        Linhas do lado do dispositivo.
    """
    lines = lines_of(dut)
    lines.clk_low.value = 0
    lines.dat_low.value = 0
    await bus.reset(dut)
    return lines


async def press(
    dut: Ps2KeyboardTbDut, lines: Ps2Lines, values: list[int]
) -> None:
    """Envie bytes de scancode pelo teclado simulado.

    Parameters
    ----------
    dut : Ps2KeyboardTbDut
        Testbench exercitado.
    lines : Ps2Lines
        Linhas do lado do dispositivo.
    values : list[int]
        Bytes enviados, um quadro cada.
    """
    for value in values:
        await device_send(dut, lines, frame_bits(value))
    await bus.cycles(dut, SETTLE_CYCLES)


async def drain(dut: Ps2KeyboardTbDut) -> list[int]:
    """Leia DATA até esvaziar a fila.

    Parameters
    ----------
    dut : Ps2KeyboardTbDut
        Testbench exercitado.

    Returns
    -------
    list[int]
        Bytes na ordem de leitura.
    """
    values: list[int] = []
    while await bus.read(dut, STATUS) & RX_VALID:
        values.append(await bus.read(dut, DATA) & 0xFF)
    return values


async def send_command(
    dut: Ps2KeyboardTbDut, lines: Ps2Lines, value: int
) -> tuple[int, bool]:
    """Escreva um comando e receba o quadro no teclado simulado.

    Parameters
    ----------
    dut : Ps2KeyboardTbDut
        Testbench exercitado.
    lines : Ps2Lines
        Linhas do lado do dispositivo.
    value : int
        Byte do comando.

    Returns
    -------
    tuple[int, bool]
        Byte recebido e se a paridade e a parada estavam certas.
    """
    await bus.write(dut, COMMAND, value)
    return await device_receive(dut, lines)


async def wait_tx_ready(dut: Ps2KeyboardTbDut) -> None:
    """Leia STATUS até o transmissor ficar livre.

    Parameters
    ----------
    dut : Ps2KeyboardTbDut
        Testbench exercitado.

    Raises
    ------
    TimeoutError
        Se o transmissor não ficar livre dentro do limite.
    """
    for _ in range(POLL_LIMIT):
        if await bus.read(dut, STATUS) & TX_READY:
            return
    raise TimeoutError("transmissor não ficou livre")


@cocotb.test()
async def reset_state(dut: Ps2KeyboardTbDut) -> None:
    """Comece com a fila vazia, transmissor livre e sem interrupção."""
    await setup(dut)
    status = await bus.read(dut, STATUS)
    check(status == TX_READY, f"estado {status:#x}")
    check(await bus.read(dut, CONTROL) == 0, "controle zerado")
    check(int(dut.o_irq.value) == 0, "sem interrupção")


@cocotb.test()
async def delivers_scancodes_in_order(dut: Ps2KeyboardTbDut) -> None:
    """Entregue make, break e estendido do conjunto 2 em ordem."""
    lines = await setup(dut)
    first = [MAKE_A, BREAK_PREFIX, MAKE_A]
    second = [EXTENDED_PREFIX, EXTENDED_UP]
    await press(dut, lines, first)
    status = await bus.read(dut, STATUS)
    level = (status >> RX_LEVEL_SHIFT) & LEVEL_MASK
    check(level == len(first), f"nível {level}")
    check(await drain(dut) == first, "make e break")
    await press(dut, lines, second)
    check(await drain(dut) == second, "estendido")
    check(await bus.read(dut, STATUS) & RX_VALID == 0, "fila vazia")


@cocotb.test()
async def overflow_keeps_the_oldest_bytes(dut: Ps2KeyboardTbDut) -> None:
    """Descarte o byte novo com a fila cheia e marque o overflow."""
    lines = await setup(dut)
    values = [0x11, 0x12, 0x13, 0x14, 0x15]
    await press(dut, lines, values)
    status = await bus.read(dut, STATUS)
    check(status & RX_FULL != 0, "fila cheia")
    check(status & RX_OVERFLOW != 0, "overflow marcado")
    check(await drain(dut) == values[:FIFO_DEPTH], "bytes antigos mantidos")
    await bus.write(dut, STATUS, 0)
    check(await bus.read(dut, STATUS) & RX_OVERFLOW != 0, "zero preserva")
    await bus.write(dut, STATUS, RX_OVERFLOW)
    check(await bus.read(dut, STATUS) & RX_OVERFLOW == 0, "um limpa")


@cocotb.test()
async def parity_error_is_flagged(dut: Ps2KeyboardTbDut) -> None:
    """Marque erro em quadro inválido sem enfileirar o byte."""
    lines = await setup(dut)
    await device_send(dut, lines, frame_bits(MAKE_A, parity_ok=False))
    await bus.cycles(dut, SETTLE_CYCLES)
    status = await bus.read(dut, STATUS)
    check(status & RX_ERROR != 0, "erro marcado")
    check(status & RX_VALID == 0, "nada enfileirado")
    await bus.write(dut, STATUS, RX_ERROR)
    check(await bus.read(dut, STATUS) & RX_ERROR == 0, "erro limpo")
    await press(dut, lines, [MAKE_A])
    check(await drain(dut) == [MAKE_A], "recupera depois do erro")


@cocotb.test()
async def sends_reset_and_led_commands(dut: Ps2KeyboardTbDut) -> None:
    """Envie reset 0xFF e ajuste de LEDs 0xED com argumento."""
    lines = await setup(dut)
    for command in (RESET_COMMAND, SET_LEDS, LEDS_ARGUMENT):
        value, framed_ok = await send_command(dut, lines, command)
        check(value == command, f"comando {value:#04x}")
        check(framed_ok, "paridade ímpar e parada corretas")
        await wait_tx_ready(dut)
    status = await bus.read(dut, STATUS)
    check(status & (RX_ERROR | TX_DROPPED) == 0, "sem erro")
    check(status & TX_READY != 0, "transmissor livre")


@cocotb.test()
async def command_while_busy_is_dropped(dut: Ps2KeyboardTbDut) -> None:
    """Descarte uma escrita em COMMAND com o transmissor ocupado."""
    lines = await setup(dut)
    await bus.write(dut, COMMAND, SET_LEDS)
    await bus.write(dut, COMMAND, RESET_COMMAND)
    status = await bus.read(dut, STATUS)
    check(status & TX_DROPPED != 0, "descarte marcado")
    check(status & TX_READY == 0, "transmissor ocupado")
    value, framed_ok = await device_receive(dut, lines)
    check(value == SET_LEDS and framed_ok, "só o primeiro comando sai")
    await bus.write(dut, STATUS, TX_DROPPED)
    await bus.cycles(dut, SETTLE_CYCLES)
    check(await bus.read(dut, STATUS) & TX_DROPPED == 0, "descarte limpo")


@cocotb.test()
async def interrupt_follows_the_enables(dut: Ps2KeyboardTbDut) -> None:
    """Gere interrupção por byte e por erro só quando habilitadas."""
    lines = await setup(dut)
    await press(dut, lines, [MAKE_A])
    check(int(dut.o_irq.value) == 0, "desabilitada")
    await bus.write(dut, CONTROL, RX_IRQ_ENABLE)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 1, "byte pendente")
    await bus.read(dut, DATA)
    check(int(dut.o_irq.value) == 0, "cai ao esvaziar")
    await device_send(dut, lines, frame_bits(MAKE_A, stop_ok=False))
    await bus.cycles(dut, SETTLE_CYCLES)
    check(int(dut.o_irq.value) == 0, "erro sem habilitação")
    await bus.write(dut, CONTROL, RX_IRQ_ENABLE | ERROR_IRQ_ENABLE)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 1, "erro habilitado")
    await bus.write(dut, STATUS, RX_ERROR)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 0, "cai ao limpar o erro")

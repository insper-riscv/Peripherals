"""Teclado e mouse PS/2 ativos ao mesmo tempo no cabo Y."""

import cocotb

from tests.python.unittests.PS2.mouse.registers import (
    BUTTONS,
    DX,
    DY,
    ERROR,
    NEW,
    STREAMING,
)
from tests.python.unittests.PS2.mouse.registers import STATUS as MOUSE_STATUS
from tests.python.unittests.PS2.mouse.top import (
    initialize,
    reply,
    send_packet,
    signed16,
)
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import Ps2CableTbDut
from tests.python.utils.ps2 import device_receive, device_send, frame_bits
from tests.python.utils.ps2_cable import Ps2Port, setup_cable

KB_DATA = 0
KB_STATUS = 1
KB_COMMAND = 2
KB_RX_VALID = 1 << 0
KB_RX_ERROR = 1 << 3
KB_ERROR_MASK = KB_RX_ERROR | (1 << 2) | (1 << 5)
SET_LEDS = 0xED
SCANCODES = [0x1C, 0xF0, 0x1C, 0xE0, 0x75]
MOVES = ((12, -7, 0b001), (-30, 25, 0b010), (100, 100, 0b100))
SETTLE = 200


async def press(keyboard: Ps2Port, values: list[int]) -> None:
    """Envie scancodes pelo teclado simulado.

    Parameters
    ----------
    keyboard : Ps2Port
        Barramento e linhas do teclado.
    values : list[int]
        Bytes enviados, um quadro cada.
    """
    for value in values:
        await device_send(keyboard, keyboard.lines, frame_bits(value))
    await bus.cycles(keyboard, SETTLE)


async def drain(keyboard: Ps2Port) -> list[int]:
    """Leia DATA do teclado até esvaziar a fila.

    Parameters
    ----------
    keyboard : Ps2Port
        Barramento do teclado.

    Returns
    -------
    list[int]
        Bytes na ordem de leitura.
    """
    values: list[int] = []
    while await bus.read(keyboard, KB_STATUS) & KB_RX_VALID:
        values.append(await bus.read(keyboard, KB_DATA) & 0xFF)
    return values


async def move_mouse(mouse: Ps2Port) -> None:
    """Envie os pacotes de movimento de MOVES pelo mouse simulado.

    Parameters
    ----------
    mouse : Ps2Port
        Barramento e linhas do mouse.
    """
    for dx, dy, buttons in MOVES:
        await send_packet(mouse, dx, dy, buttons=buttons)


async def command_keyboard(dut: Ps2CableTbDut, keyboard: Ps2Port) -> None:
    """Mande um comando ao teclado e confira o quadro recebido.

    Parameters
    ----------
    dut : Ps2CableTbDut
        Testbench exercitado.
    keyboard : Ps2Port
        Barramento e linhas do teclado.
    """
    await bus.write(keyboard, KB_COMMAND, SET_LEDS)
    value, framed_ok = await device_receive(dut, keyboard.lines)
    check_equal(value, SET_LEDS)
    check(framed_ok, "paridade ímpar e parada corretas")


@cocotb.test()
async def both_hosts_initialize_together(dut: Ps2CableTbDut) -> None:
    """O mouse inicializa enquanto o teclado entrega scancodes."""
    keyboard, mouse = await setup_cable(dut)
    mouse_task = cocotb.start_soon(initialize(dut, mouse))
    await press(keyboard, SCANCODES)
    await mouse_task
    check(await drain(keyboard) == SCANCODES, "scancodes em ordem")
    check(await bus.read(mouse, MOUSE_STATUS) & STREAMING != 0, "streaming")
    check(await bus.read(keyboard, KB_STATUS) & KB_ERROR_MASK == 0, "teclado")


@cocotb.test()
async def streams_do_not_interfere(dut: Ps2CableTbDut) -> None:
    """Pacotes do mouse e teclas chegam juntos sem perder nada."""
    keyboard, mouse = await setup_cable(dut)
    await initialize(dut, mouse)
    mouse_task = cocotb.start_soon(move_mouse(mouse))
    await press(keyboard, SCANCODES)
    await mouse_task
    check(await drain(keyboard) == SCANCODES, "teclas do canal 0")
    status = await bus.read(mouse, MOUSE_STATUS)
    check(status & NEW != 0 and status & ERROR == 0, hex(status))
    check_equal(signed16(await bus.read(mouse, DX)), sum(m[0] for m in MOVES))
    check_equal(signed16(await bus.read(mouse, DY)), sum(m[1] for m in MOVES))
    check_equal(await bus.read(mouse, BUTTONS), MOVES[-1][2])


@cocotb.test()
async def keyboard_command_during_mouse_stream(dut: Ps2CableTbDut) -> None:
    """Um comando ao teclado sai enquanto o mouse envia pacotes."""
    keyboard, mouse = await setup_cable(dut)
    await initialize(dut, mouse)
    mouse_task = cocotb.start_soon(move_mouse(mouse))
    await command_keyboard(dut, keyboard)
    await mouse_task
    await press(keyboard, SCANCODES[:2])
    check(await drain(keyboard) == SCANCODES[:2], "teclado após o comando")
    check_equal(signed16(await bus.read(mouse, DX)), sum(m[0] for m in MOVES))
    check(await bus.read(mouse, MOUSE_STATUS) & ERROR == 0, "mouse sem erro")


@cocotb.test()
async def mouse_command_during_keyboard_stream(dut: Ps2CableTbDut) -> None:
    """O reinício do mouse não perturba as teclas do canal 0."""
    keyboard, mouse = await setup_cable(dut)
    await initialize(dut, mouse)
    await bus.write(mouse, 4, 0b10)
    key_task = cocotb.start_soon(press(keyboard, SCANCODES))
    await initialize(dut, mouse)
    await key_task
    check(await drain(keyboard) == SCANCODES, "teclas durante o reinício")
    await reply(mouse, (0x09, 0x01, 0x02))
    await bus.cycles(mouse, SETTLE)
    check_equal(await bus.read(mouse, DX), 1)
    check_equal(await bus.read(mouse, DY), 2)

"""Camada física PS/2: quadros, erros, filtro, envio e dois canais."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import Ps2HostTbDut
from tests.python.utils.ps2 import (
    device_receive,
    device_send,
    frame_bits,
    host_send,
    setup,
    wait_until,
)

MAKE_A = 0x1C
BREAK_PREFIX = 0xF0
EXTENDED_PREFIX = 0xE0
EXTENDED_UP = 0x75
SET_LEDS = 0xED
ENABLE_STREAMING = 0xF4
RESET_COMMAND = 0xFF
BYTE_ODD = 0x07
BYTE_AFTER_ERROR = 0x5A
SETTLE_CYCLES = 200
TIMEOUT_CYCLES = 700
SHORT_GLITCH_CYCLES = 2


@cocotb.test()
async def receives_make_break_and_extended(dut: Ps2HostTbDut) -> None:
    """Receba os bytes de make, break e estendido do conjunto 2."""
    channel, _ = await setup(dut)
    sequence = [MAKE_A, BREAK_PREFIX, MAKE_A, EXTENDED_PREFIX, EXTENDED_UP]
    for value in sequence:
        await device_send(dut, channel, frame_bits(value))
        await bus.cycles(dut, SETTLE_CYCLES)
    check(
        channel.host.received == sequence, f"recebido {channel.host.received}"
    )
    check(channel.host.errors == 0, "nenhum erro em quadros corretos")


@cocotb.test()
async def reports_parity_and_stop_errors(dut: Ps2HostTbDut) -> None:
    """Sinalize erro de paridade, de parada e de início sem entregar."""
    channel, _ = await setup(dut)
    bad_parity = frame_bits(BYTE_ODD, parity_ok=False)
    bad_stop = frame_bits(BYTE_ODD, stop_ok=False)
    bad_frames = (bad_parity, bad_stop)
    for bits in bad_frames:
        await device_send(dut, channel, bits)
        await bus.cycles(dut, SETTLE_CYCLES)
    check(
        channel.host.errors == len(bad_frames), f"erros {channel.host.errors}"
    )
    check(channel.host.received == [], "quadro inválido não é entregue")
    await device_send(dut, channel, frame_bits(BYTE_AFTER_ERROR))
    await bus.cycles(dut, SETTLE_CYCLES)
    check(channel.host.received == [BYTE_AFTER_ERROR], "recupera após erro")


@cocotb.test()
async def aborts_a_stalled_frame(dut: Ps2HostTbDut) -> None:
    """Aborte um quadro parado e volte a receber."""
    channel, _ = await setup(dut)
    await device_send(dut, channel, frame_bits(MAKE_A)[:4])
    await bus.cycles(dut, TIMEOUT_CYCLES + SETTLE_CYCLES)
    check(channel.host.errors == 1, f"erros {channel.host.errors}")
    await device_send(dut, channel, frame_bits(MAKE_A))
    await bus.cycles(dut, SETTLE_CYCLES)
    check(channel.host.received == [MAKE_A], "recebe após o tempo esgotado")


@cocotb.test()
async def ignores_a_short_glitch(dut: Ps2HostTbDut) -> None:
    """Descarte um pulso curto no clock em repouso."""
    channel, _ = await setup(dut)
    channel.lines.clk_low.value = 1
    await bus.cycles(dut, SHORT_GLITCH_CYCLES)
    channel.lines.clk_low.value = 0
    await bus.cycles(dut, SETTLE_CYCLES)
    check(channel.host.errors == 0, "o glitch não vira início de quadro")
    await device_send(dut, channel, frame_bits(MAKE_A))
    await bus.cycles(dut, SETTLE_CYCLES)
    check(channel.host.received == [MAKE_A], "quadro seguinte recebido")


@cocotb.test()
async def sends_commands_with_ack(dut: Ps2HostTbDut) -> None:
    """Envie comandos ao dispositivo e confira bytes, paridade e ack."""
    channel, _ = await setup(dut)
    for command in (RESET_COMMAND, SET_LEDS):
        await host_send(dut, channel, command)
        value, framed_ok = await device_receive(dut, channel)
        check(value == command, f"comando {value:#04x}")
        check(framed_ok, "paridade ímpar e parada corretas")
        await wait_until(dut, lambda: int(channel.host.tx_ready.value) == 1)
    check(channel.host.errors == 0, "reconhecido, sem erro")


@cocotb.test()
async def reports_a_missing_ack(dut: Ps2HostTbDut) -> None:
    """Sinalize erro quando o dispositivo não reconhece."""
    channel, _ = await setup(dut)
    await host_send(dut, channel, SET_LEDS)
    await device_receive(dut, channel, ack=False)
    await bus.cycles(dut, SETTLE_CYCLES)
    check(channel.host.errors == 1, f"erros {channel.host.errors}")
    check(int(channel.host.tx_ready.value) == 1, "transmissor liberado")


@cocotb.test()
async def holds_the_command_while_receiving(dut: Ps2HostTbDut) -> None:
    """Não aceite um comando enquanto um quadro chega."""
    channel, _ = await setup(dut)
    frame = cocotb.start_soon(device_send(dut, channel, frame_bits(MAKE_A)))
    await bus.cycles(dut, SETTLE_CYCLES)
    check(int(channel.host.tx_ready.value) == 0, "ocupado durante o quadro")
    await frame
    await bus.cycles(dut, SETTLE_CYCLES)
    check(channel.host.received == [MAKE_A], "quadro entregue")
    check(int(channel.host.tx_ready.value) == 1, "livre depois do quadro")


@cocotb.test()
async def two_channels_do_not_interfere(dut: Ps2HostTbDut) -> None:
    """Teclado recebendo no canal 0 e comando ao mouse no canal 1."""
    keyboard, mouse = await setup(dut)
    keys = [MAKE_A, BREAK_PREFIX, MAKE_A]
    mouse_bytes = [0x08, 0x01, 0xFF]

    async def stream() -> None:
        for value in keys:
            await device_send(dut, keyboard, frame_bits(value))

    key_task = cocotb.start_soon(stream())
    await host_send(dut, mouse, ENABLE_STREAMING)
    value, framed_ok = await device_receive(dut, mouse)
    await key_task
    check(value == ENABLE_STREAMING and framed_ok, "comando do canal 1")
    for byte in mouse_bytes:
        await device_send(dut, mouse, frame_bits(byte))
    await bus.cycles(dut, SETTLE_CYCLES)
    check(keyboard.host.received == keys, f"canal 0 {keyboard.host.received}")
    check(mouse.host.received == mouse_bytes, f"canal 1 {mouse.host.received}")
    check(keyboard.host.errors == 0 and mouse.host.errors == 0, "sem erros")

"""UART serial: paridade, dois bits de parada e erros de quadro.

A configuração do teste usa ``BAUD_FREQ=1`` e ``BAUD_LIMIT=0``: cada
bit serial dura 16 ciclos. O controle de fluxo fica desligado, então o
registrador de configuração só tem os bits de formato.
"""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import UartDut
from tests.python.utils.uart_frame import (
    BIT_CYCLES,
    Format,
    receive_frame,
    reset_idle,
    send_frame,
    wait_tx_idle,
)

TX_DATA, RX_DATA, STATUS, CONTROL = range(4)
RX_VALID = 1 << 0
TX_IDLE = 1 << 6
FRAME_ERROR = 1 << 7
PARITY_ERROR = 1 << 24
ERROR_IRQ_ENABLE = 1 << 2
LINE_ERROR_IRQ_ENABLE = 1 << 6
FORMATS = [
    Format("none", 1),
    Format("even", 1),
    Format("odd", 1),
    Format("none", 2),
    Format("even", 2),
    Format("odd", 2),
]
BYTE_A = 0x5A
BYTE_B = 0x5B
BYTE_C = 0x5C
BYTE_D = 0x96
BYTE_E = 0x42
BYTES = [0x00, 0xFF, 0xA5, 0x3C, 0x01]


async def loopback(dut: UartDut) -> None:
    """Ligue a saída serial à entrada serial, com um ciclo de atraso.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.
    """
    while True:
        await RisingEdge(dut.i_clk)
        dut.i_uart_rx.value = dut.o_uart_tx.value


@cocotb.test()
async def test_reset_format_is_8n1_without_errors(dut: UartDut) -> None:
    """Após o reset o quadro é 8N1 e as flags de linha estão limpas."""
    await reset_idle(dut)
    check(await bus.read(dut, CONTROL) == 0)
    status = await bus.read(dut, STATUS)
    check(status & (FRAME_ERROR | PARITY_ERROR) == 0)


@cocotb.test()
async def test_transmit_frames_in_every_format(dut: UartDut) -> None:
    """A UART envia paridade par e ímpar e um ou dois bits de parada."""
    await reset_idle(dut)
    for fmt in FORMATS:
        await bus.write(dut, CONTROL, fmt.control)
        check(await bus.read(dut, CONTROL) == fmt.control)
        for value in BYTES:
            receiver = cocotb.start_soon(receive_frame(dut, fmt))
            await bus.write(dut, TX_DATA, value)
            check(await receiver == value, f"{fmt} byte {value:#04x}")
            await wait_tx_idle(dut)


@cocotb.test()
async def test_two_stop_bits_make_the_frame_one_bit_longer(
    dut: UartDut,
) -> None:
    """Dois bits de parada ocupam o transmissor um bit a mais."""
    await reset_idle(dut)
    lengths: list[int] = []
    for fmt in (Format("none", 1), Format("even", 1), Format("even", 2)):
        await bus.write(dut, CONTROL, fmt.control)
        await bus.write(dut, TX_DATA, 0x00)
        busy = 0
        while not await bus.read(dut, STATUS) & TX_IDLE:
            busy += 1
        lengths.append(busy)
        await bus.cycles(dut, BIT_CYCLES)
    check(lengths[0] < lengths[1] < lengths[2], f"{lengths}")


@cocotb.test()
async def test_loopback_in_every_format(dut: UartDut) -> None:
    """A UART recebe o que envia, sem erro, em todos os formatos."""
    await reset_idle(dut)
    cocotb.start_soon(loopback(dut))
    for fmt in FORMATS:
        await bus.write(dut, CONTROL, fmt.control)
        for value in BYTES:
            await bus.write(dut, TX_DATA, value)
            await wait_tx_idle(dut)
            await bus.cycles(dut, BIT_CYCLES * 2)
            check(await bus.read(dut, RX_DATA) == value, f"{fmt} {value:#x}")
        status = await bus.read(dut, STATUS)
        check(status & (FRAME_ERROR | PARITY_ERROR) == 0, f"{fmt} {status:#x}")
        check(status & RX_VALID == 0)


@cocotb.test()
async def test_parity_error_is_sticky_and_keeps_the_byte(
    dut: UartDut,
) -> None:
    """Paridade errada marca a flag, entrega o byte e só W1C limpa."""
    await reset_idle(dut)
    for parity in ("even", "odd"):
        fmt = Format(parity, 1)
        await bus.write(dut, CONTROL, fmt.control)
        await send_frame(dut, BYTE_A, fmt)
        check(await bus.read(dut, STATUS) & PARITY_ERROR == 0)
        check(await bus.read(dut, RX_DATA) == BYTE_A)

        await send_frame(dut, BYTE_B, fmt, bad_parity=True)
        await send_frame(dut, BYTE_C, fmt)
        status = await bus.read(dut, STATUS)
        check(status & PARITY_ERROR != 0, "a flag continua depois de um bom")
        check(status & FRAME_ERROR == 0)
        check(await bus.read(dut, RX_DATA) == BYTE_B)
        check(await bus.read(dut, RX_DATA) == BYTE_C)

        await bus.write(dut, STATUS, 0)
        check(await bus.read(dut, STATUS) & PARITY_ERROR != 0)
        await bus.write(dut, STATUS, PARITY_ERROR)
        check(await bus.read(dut, STATUS) & PARITY_ERROR == 0)


@cocotb.test()
async def test_parity_disabled_ignores_the_parity_position(
    dut: UartDut,
) -> None:
    """Sem paridade o receptor não procura o bit e não acusa erro."""
    await reset_idle(dut)
    await send_frame(dut, BYTE_D, Format("none", 1))
    check(await bus.read(dut, STATUS) & (PARITY_ERROR | FRAME_ERROR) == 0)
    check(await bus.read(dut, RX_DATA) == BYTE_D)


@cocotb.test()
async def test_frame_error_on_a_low_stop_bit(dut: UartDut) -> None:
    """Bit de parada em zero marca FRAME_ERROR, com ou sem paridade."""
    await reset_idle(dut)
    for fmt in (Format("none", 1), Format("odd", 2)):
        await bus.write(dut, CONTROL, fmt.control)
        await send_frame(dut, BYTE_E, fmt, bad_stop=True)
        status = await bus.read(dut, STATUS)
        check(status & FRAME_ERROR != 0, f"{fmt}")
        check(status & PARITY_ERROR == 0)
        check(await bus.read(dut, RX_DATA) == BYTE_E)
        await bus.write(dut, STATUS, FRAME_ERROR)
        check(await bus.read(dut, STATUS) & FRAME_ERROR == 0)


@cocotb.test()
async def test_line_error_interrupt_has_its_own_enable(dut: UartDut) -> None:
    """O erro de linha interrompe só com LINE_ERROR_IRQ_ENABLE."""
    await reset_idle(dut)
    fmt = Format("even", 1)
    await bus.write(dut, CONTROL, fmt.control | ERROR_IRQ_ENABLE)
    await send_frame(dut, 0x11, fmt, bad_parity=True)
    check(int(dut.o_irq.value) == 0, "ERROR_IRQ_ENABLE não cobre a linha")

    await bus.write(dut, CONTROL, fmt.control | LINE_ERROR_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, STATUS, PARITY_ERROR)
    check(int(dut.o_irq.value) == 0)

    await send_frame(dut, 0x12, fmt, bad_stop=True)
    check(int(dut.o_irq.value) == 1)
    check(await bus.read(dut, STATUS) & FRAME_ERROR != 0)
    await bus.write(dut, STATUS, FRAME_ERROR)
    check(int(dut.o_irq.value) == 0)

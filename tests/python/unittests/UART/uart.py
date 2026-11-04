"""UART serial: filas, registradores, quadros 8N1, erros e interrupção.

A configuração do teste usa ``BAUD_FREQ=1`` e ``BAUD_LIMIT=0``. O sinal
de habilitação de 16 vezes o baud pulsa em todo ciclo, portanto cada bit
serial dura exatamente 16 ciclos sem substituir a camada física.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import UartDut

TX_DATA, RX_DATA, STATUS, CONTROL = range(4)
RX_VALID = 1 << 0
TX_READY = 1 << 1
RX_OVERRUN = 1 << 2
TX_DROPPED = 1 << 3
RX_FULL = 1 << 4
TX_EMPTY = 1 << 5
TX_IDLE = 1 << 6
RX_IRQ_ENABLE = 1 << 0
RX_LEVEL_SHIFT = 8
TX_LEVEL_SHIFT = 16
LEVEL_MASK = 0xFF

BIT_CYCLES = 16
DATA_BITS = 8
STOP_MARGIN_CYCLES = 4
FIFO_DEPTH = 4
STATUS_POLL_LIMIT = BIT_CYCLES * 12

BYTE_TX = 0xA5
BYTE_QUEUED = 0x3C
BYTE_DROPPED = 0xE7
BYTE_PREVIOUS = 0x11
BYTE_ARRIVING = 0x22
BYTE_SIDE_EFFECT = 0x6D


def rx_level(status: int) -> int:
    """Extraia a quantidade de bytes da fila de recepção.

    Parameters
    ----------
    status : int
        Valor do registrador de estado.

    Returns
    -------
    int
        Quantidade de bytes recebidos e ainda não lidos.
    """
    return (status >> RX_LEVEL_SHIFT) & LEVEL_MASK


def tx_level(status: int) -> int:
    """Extraia a quantidade de bytes da fila de transmissão.

    Parameters
    ----------
    status : int
        Valor do registrador de estado.

    Returns
    -------
    int
        Quantidade de bytes esperando o transmissor físico.
    """
    return (status >> TX_LEVEL_SHIFT) & LEVEL_MASK


async def setup(dut: UartDut) -> None:
    """Deixe a linha serial ociosa e reinicie o periférico.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.
    """
    dut.i_uart_rx.value = 1
    await bus.reset(dut)


async def send_serial_byte(dut: UartDut, value: int) -> None:
    """Envie um byte 8N1 pela entrada serial, bit menos significativo primeiro.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.
    value : int
        Byte enviado.
    """
    dut.i_uart_rx.value = 0
    await bus.cycles(dut, BIT_CYCLES)

    for bit in range(DATA_BITS):
        dut.i_uart_rx.value = (value >> bit) & 1
        await bus.cycles(dut, BIT_CYCLES)

    dut.i_uart_rx.value = 1
    await bus.cycles(dut, BIT_CYCLES + STOP_MARGIN_CYCLES)


async def receive_serial_byte(dut: UartDut) -> int:
    """Decodifique um byte 8N1 produzido pela saída serial.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.

    Returns
    -------
    int
        Byte observado.
    """
    await with_timeout(FallingEdge(dut.o_uart_tx), 5, "us")
    await bus.cycles(dut, BIT_CYCLES // 2)
    check(int(dut.o_uart_tx.value) == 0, "bit de início em nível baixo")

    value = 0
    for bit in range(DATA_BITS):
        await bus.cycles(dut, BIT_CYCLES)
        value |= int(dut.o_uart_tx.value) << bit

    await bus.cycles(dut, BIT_CYCLES)
    check(int(dut.o_uart_tx.value) == 1, "bit de parada em nível alto")
    return value


async def receive_serial_bytes(dut: UartDut, count: int) -> list[int]:
    """Decodifique uma sequência de bytes da saída serial.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.
    count : int
        Quantidade de bytes esperada.

    Returns
    -------
    list[int]
        Bytes na ordem observada.
    """
    return [await receive_serial_byte(dut) for _ in range(count)]


async def wait_tx_idle(dut: UartDut) -> None:
    """Espere a fila e o transmissor físico ficarem ociosos.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.

    Raises
    ------
    AssertionError
        Se o transmissor não ficar ocioso dentro do limite.
    """
    for _ in range(STATUS_POLL_LIMIT):
        if await bus.read(dut, STATUS) & TX_IDLE:
            return
    message = "o transmissor não ficou ocioso"
    raise AssertionError(message)


@cocotb.test()
async def test_reset_state_and_register_map(dut: UartDut) -> None:
    """Os registradores assumem os valores definidos para o reset."""
    await setup(dut)

    expected_status = TX_READY | TX_EMPTY | TX_IDLE
    check(await bus.read(dut, TX_DATA) == 0)
    check(await bus.read(dut, RX_DATA) == 0)
    check(await bus.read(dut, STATUS) == expected_status)
    check(await bus.read(dut, CONTROL) == 0)
    check(int(dut.o_irq.value) == 0)
    check(int(dut.o_uart_tx.value) == 1, "a linha ociosa fica em nível alto")


@cocotb.test()
async def test_transmit_queued_complete_8n1_frames(dut: UartDut) -> None:
    """Uma escrita durante outra transmissão fica na fila e sai em ordem."""
    await setup(dut)

    receiver = cocotb.start_soon(receive_serial_bytes(dut, 2))
    await bus.write(dut, TX_DATA, BYTE_TX)
    await bus.write(dut, TX_DATA, BYTE_QUEUED)

    status = await bus.read(dut, STATUS)
    check(status & TX_DROPPED == 0)
    check(await receiver == [BYTE_TX, BYTE_QUEUED])
    await wait_tx_idle(dut)


@cocotb.test()
async def test_tx_full_rejects_only_extra_byte_and_reports_error(
    dut: UartDut,
) -> None:
    """TX aceita um byte físico e uma fila cheia antes de descartar."""
    await setup(dut)
    accepted = [0x40 + index for index in range(FIFO_DEPTH + 1)]
    receiver = cocotb.start_soon(receive_serial_bytes(dut, len(accepted)))

    for value in accepted:
        await bus.write(dut, TX_DATA, value)
    await bus.write(dut, TX_DATA, BYTE_DROPPED)

    status = await bus.read(dut, STATUS)
    check(status & TX_READY == 0)
    check(status & TX_DROPPED != 0)
    check(tx_level(status) == FIFO_DEPTH)

    await bus.write(dut, STATUS, TX_DROPPED)
    check(await bus.read(dut, STATUS) & TX_DROPPED == 0)
    check(await receiver == accepted)
    await wait_tx_idle(dut)

    status = await bus.read(dut, STATUS)
    check(status & (TX_READY | TX_EMPTY | TX_IDLE) == TX_READY | TX_EMPTY | TX_IDLE)
    check(tx_level(status) == 0)


@cocotb.test()
async def test_rx_full_preserves_oldest_bytes_and_reports_overrun(
    dut: UartDut,
) -> None:
    """RX cheia mantém os bytes antigos e descarta somente o novo."""
    await setup(dut)
    accepted = [0x20 + index for index in range(FIFO_DEPTH)]

    for value in [*accepted, BYTE_DROPPED]:
        await send_serial_byte(dut, value)

    status = await bus.read(dut, STATUS)
    check(status & RX_VALID != 0)
    check(status & RX_FULL != 0)
    check(status & RX_OVERRUN != 0)
    check(rx_level(status) == FIFO_DEPTH)

    received = [await bus.read(dut, RX_DATA) for _ in range(FIFO_DEPTH)]
    check(received == accepted)
    status = await bus.read(dut, STATUS)
    check(status & RX_VALID == 0)
    check(status & RX_OVERRUN != 0)
    check(rx_level(status) == 0)

    await bus.write(dut, STATUS, RX_OVERRUN)
    check(await bus.read(dut, STATUS) & RX_OVERRUN == 0)


@cocotb.test()
async def test_simultaneous_rx_data_read_and_arrival_keeps_new_byte(
    dut: UartDut,
) -> None:
    """Uma chegada simultânea à leitura substitui a posição liberada."""
    await setup(dut)
    await send_serial_byte(dut, BYTE_PREVIOUS)

    sender = cocotb.start_soon(send_serial_byte(dut, BYTE_ARRIVING))
    await with_timeout(RisingEdge(dut.phy_new_rx_data), 5, "us")

    dut.i_address.value = RX_DATA
    dut.i_read.value = 1
    await Timer(1, unit="ns")
    check(int(dut.o_data_out.value) == BYTE_PREVIOUS)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_read.value = 0

    await sender
    status = await bus.read(dut, STATUS)
    check(status & RX_VALID != 0)
    check(status & RX_OVERRUN == 0)
    check(rx_level(status) == 1)
    check(await bus.read(dut, RX_DATA) == BYTE_ARRIVING)


@cocotb.test()
async def test_rx_interrupt_remains_until_queue_is_empty(dut: UartDut) -> None:
    """A interrupção permanece ativa enquanto houver algum byte recebido."""
    await setup(dut)
    await bus.write(dut, CONTROL, RX_IRQ_ENABLE)
    await send_serial_byte(dut, 0xC3)
    await send_serial_byte(dut, 0xC4)
    check(int(dut.o_irq.value) == 1)

    check(await bus.read(dut, RX_DATA) == 0xC3)
    check(int(dut.o_irq.value) == 1)
    check(await bus.read(dut, RX_DATA) == 0xC4)
    check(int(dut.o_irq.value) == 0)

    await bus.write(dut, CONTROL, 0)
    check(await bus.read(dut, CONTROL) == 0)


@cocotb.test()
async def test_rx_wraparound_preserves_order_and_levels(dut: UartDut) -> None:
    """A fila RX preserva ordem e nível depois da volta dos ponteiros."""
    await setup(dut)

    for value in (0x10, 0x11, 0x12, 0x13):
        await send_serial_byte(dut, value)
    check(await bus.read(dut, RX_DATA) == 0x10)
    check(await bus.read(dut, RX_DATA) == 0x11)

    await send_serial_byte(dut, 0x14)
    await send_serial_byte(dut, 0x15)
    status = await bus.read(dut, STATUS)
    check(rx_level(status) == FIFO_DEPTH)
    received = [await bus.read(dut, RX_DATA) for _ in range(FIFO_DEPTH)]
    check(received == [0x12, 0x13, 0x14, 0x15])


@cocotb.test()
async def test_tx_read_and_rx_write_are_side_effect_free(
    dut: UartDut,
) -> None:
    """Ler TX_DATA e escrever RX_DATA não altera o estado das filas."""
    await setup(dut)
    await send_serial_byte(dut, BYTE_SIDE_EFFECT)

    check(await bus.read(dut, TX_DATA) == 0)
    check(await bus.read(dut, STATUS) & RX_VALID != 0)

    await bus.write(dut, RX_DATA, BYTE_TX)
    status = await bus.read(dut, STATUS)
    check(status & RX_VALID != 0)
    check(rx_level(status) == 1)
    check(int(dut.o_uart_tx.value) == 1)

    check(await bus.read(dut, RX_DATA) == BYTE_SIDE_EFFECT)
    check(await bus.read(dut, STATUS) & RX_VALID == 0)

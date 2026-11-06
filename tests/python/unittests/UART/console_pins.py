"""Console com o backend "pinos": a UART serial atrás da interface comum.

O mesmo teste roda com a polaridade normal e com TX e RX invertidos; o
sinal ``LINE_IDLE`` lê o nível de repouso que a configuração produz. A
configuração usa ``BAUD_FREQ=1`` e ``BAUD_LIMIT=0``, então cada bit serial
dura 16 ciclos.
"""

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout

from tests.python.utils.check import check

TX_DATA, RX_DATA, STATUS, CONTROL = range(4)
RX_VALID = 1 << 0
TX_IDLE = 1 << 6
RX_IRQ_ENABLE = 1 << 0
TX_EMPTY_IRQ_ENABLE = 1 << 1
BIT_CYCLES = 16
DATA_BITS = 8
STOP_MARGIN_CYCLES = 4
POLL_LIMIT = BIT_CYCLES * 12
BYTE_TX = 0xA5
BYTE_RX = 0x3C
# Inversão de TX e RX da configuração em teste (0 ou 1, vinda do ambiente).
INVERTED = os.environ.get("CONSOLE_INVERTED", "0") == "1"
LINE_IDLE = 0 if INVERTED else 1


async def cycles(dut, count: int) -> None:
    """Espere um número de bordas de subida do clock.

    Parameters
    ----------
    dut : object
        Console exercitado pelo teste.
    count : int
        Quantidade de bordas.
    """
    for _ in range(count):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def setup(dut) -> None:
    """Deixe a linha serial ociosa e reinicie o console.

    Parameters
    ----------
    dut : object
        Console exercitado pelo teste.
    """
    dut.i_rx.value = LINE_IDLE
    dut.i_we.value = 0
    dut.i_re.value = 0
    dut.i_addr.value = 0
    dut.i_wdata.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    await cycles(dut, 3)
    dut.i_rst.value = 0
    await cycles(dut, 1)


async def write(dut, address: int, value: int) -> None:
    """Escreva um registrador em um ciclo.

    Parameters
    ----------
    dut : object
        Console exercitado pelo teste.
    address : int
        Endereço de palavra.
    value : int
        Valor escrito.
    """
    dut.i_addr.value = address
    dut.i_wdata.value = value
    dut.i_we.value = 1
    await cycles(dut, 1)
    dut.i_we.value = 0


async def read(dut, address: int) -> int:
    """Leia um registrador em um ciclo.

    Parameters
    ----------
    dut : object
        Console exercitado pelo teste.
    address : int
        Endereço de palavra.

    Returns
    -------
    int
        Valor amostrado antes da borda.
    """
    dut.i_addr.value = address
    dut.i_re.value = 1
    await Timer(1, unit="ns")
    value = int(dut.o_rdata.value)
    await cycles(dut, 1)
    dut.i_re.value = 0
    return value


async def send_byte(dut, value: int) -> None:
    """Envie um byte 8N1 pela entrada serial, do bit 0 ao bit 7.

    Parameters
    ----------
    dut : object
        Console exercitado pelo teste.
    value : int
        Byte enviado.
    """
    active = 1 - LINE_IDLE
    dut.i_rx.value = active
    await cycles(dut, BIT_CYCLES)
    for bit in range(DATA_BITS):
        level = (value >> bit) & 1
        dut.i_rx.value = level if not INVERTED else 1 - level
        await cycles(dut, BIT_CYCLES)
    dut.i_rx.value = LINE_IDLE
    await cycles(dut, BIT_CYCLES + STOP_MARGIN_CYCLES)


async def receive_byte(dut) -> int:
    """Decodifique um byte 8N1 produzido pela saída serial.

    Parameters
    ----------
    dut : object
        Console exercitado pelo teste.

    Returns
    -------
    int
        Byte observado.
    """
    edge = RisingEdge if INVERTED else FallingEdge
    await with_timeout(edge(dut.o_tx), 5, "us")
    await cycles(dut, BIT_CYCLES // 2)
    check(int(dut.o_tx.value) != LINE_IDLE, "bit de início fora do repouso")
    value = 0
    for bit in range(DATA_BITS):
        await cycles(dut, BIT_CYCLES)
        level = int(dut.o_tx.value)
        value |= (level if not INVERTED else 1 - level) << bit
    await cycles(dut, BIT_CYCLES)
    check(int(dut.o_tx.value) == LINE_IDLE, "bit de parada em repouso")
    return value


@cocotb.test()
async def test_reset_state_and_idle_line(dut) -> None:
    """Após o reset a linha está em repouso e o controle em zero."""
    await setup(dut)
    check(int(dut.o_tx.value) == LINE_IDLE, "linha de transmissão em repouso")
    check(await read(dut, CONTROL) == 0)
    check(await read(dut, RX_DATA) == 0)
    check(await read(dut, STATUS) & TX_IDLE != 0, "transmissor ocioso")
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_transmit_frame_reaches_the_pin(dut) -> None:
    """Um byte escrito na palavra 0 sai no pino em um quadro 8N1."""
    await setup(dut)
    receiver = cocotb.start_soon(receive_byte(dut))
    await write(dut, TX_DATA, BYTE_TX)
    check(await receiver == BYTE_TX, "byte transmitido")


@cocotb.test()
async def test_received_frame_is_read_from_word_1(dut) -> None:
    """Um quadro no pino de entrada vira um byte na palavra 1."""
    await setup(dut)
    await send_byte(dut, BYTE_RX)
    check(await read(dut, STATUS) & RX_VALID != 0, "byte pendente")
    check(await read(dut, RX_DATA) & 0xFF == BYTE_RX, "byte recebido")
    check(await read(dut, STATUS) & RX_VALID == 0, "fila vazia depois da leitura")


@cocotb.test()
async def test_irq_follows_the_control_enables(dut) -> None:
    """A interrupção de recepção só sobe com a habilitação do controle."""
    await setup(dut)
    await send_byte(dut, BYTE_RX)
    check(int(dut.o_irq.value) == 0, "sem habilitação")
    await write(dut, CONTROL, RX_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 1, "recepção habilitada")
    await read(dut, RX_DATA)
    check(int(dut.o_irq.value) == 0, "cai ao ler o byte")
    await write(dut, CONTROL, TX_EMPTY_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 1, "fila de transmissão vazia")

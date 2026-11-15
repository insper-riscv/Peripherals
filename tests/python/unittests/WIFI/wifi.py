"""Ponte do módulo Wi-Fi: mapa de endereços, pinos, SPI e UART."""

import cocotb
from cocotb.triggers import FallingEdge, with_timeout

from tests.python.unittests.WIFI.registers import (
    ACK,
    CTRL,
    FALL,
    RESET_PULSE,
    RISE,
    RISE_IRQ,
    RUN,
    SPI_CONTROL,
    SPI_DIVIDER,
    SPI_RX_DATA,
    SPI_STATUS,
    SPI_TX_DATA,
    STATUS,
    UART_CONTROL,
    UART_RX_DATA,
    UART_STATUS,
    UART_TX_DATA,
    UNMAPPED,
)
from tests.python.utils import bus, polling
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import WifiDut
from tests.python.utils.spi_regs import CS_ASSERT, DONE
from tests.python.utils.spi_slave import Bit, Wires, WordSlave

BIT_CYCLES = 434
STOP_MARGIN_CYCLES = 2 * BIT_CYCLES
PULSE_CYCLES = 50_000
UART_RX_VALID = 1
SPI_WORD_BITS = 8
FAST_DIVIDER = 4


async def start(dut: WifiDut) -> None:
    """Deixe as entradas em repouso e reinicie o projeto.

    Parameters
    ----------
    dut : WifiDut
        Projeto sob teste.
    """
    idle = {"i_wm_ack": 1, "i_wm_cipo": 1, "i_wm_tx": 1, "i_wm_rts": 0}
    for name, level in idle.items():
        getattr(dut, name).value = level
    await bus.reset(dut)


@cocotb.test()
async def test_blocks_do_not_alias(dut: WifiDut) -> None:
    """Cada bloco tem os seus registradores, e o resto lê zero."""
    await start(dut)
    await bus.write(dut, SPI_DIVIDER, 0x1234)
    check_equal(await bus.read(dut, SPI_DIVIDER), 0x1234)
    check_equal(await bus.read(dut, CTRL), 0)
    await bus.write(dut, CTRL, RUN)
    check_equal(await bus.read(dut, SPI_DIVIDER), 0x1234)
    check_equal(await bus.read(dut, CTRL), RUN)
    await bus.write(dut, UART_CONTROL, 0x08)
    check_equal(await bus.read(dut, UART_CONTROL), 0x08)
    check_equal(await bus.read(dut, SPI_DIVIDER), 0x1234)
    for address in UNMAPPED:
        await bus.write(dut, address, 0xFFFF_FFFF)
        check_equal(await bus.read(dut, address), 0)
    check_equal(await bus.read(dut, CTRL), RUN)
    check_equal(await bus.read(dut, SPI_DIVIDER), 0x1234)
    check_equal(await bus.read(dut, UART_CONTROL), 0x08)


@cocotb.test()
async def test_control_pins(dut: WifiDut) -> None:
    """Reset, pulso de reset e interrupção de ACK chegam aos pinos."""
    await start(dut)
    check_equal(int(dut.o_wm_reset_n.value), 0)
    await bus.write(dut, CTRL, RUN | RISE_IRQ)
    check_equal(int(dut.o_wm_reset_n.value), 1)
    check_equal(await bus.read(dut, STATUS), ACK)
    dut.i_wm_ack.value = 0
    await bus.cycles(dut, 4)
    dut.i_wm_ack.value = 1
    await bus.cycles(dut, 4)
    check_equal(await bus.read(dut, STATUS), ACK | RISE | FALL)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, STATUS, RISE)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, RESET_PULSE, 1)
    check_equal(int(dut.o_wm_reset_n.value), 0)
    await bus.cycles(dut, PULSE_CYCLES // 2)
    check_equal(int(dut.o_wm_reset_n.value), 0)
    await bus.cycles(dut, PULSE_CYCLES)
    check_equal(int(dut.o_wm_reset_n.value), 1)


@cocotb.test()
async def test_spi_transfer(dut: WifiDut) -> None:
    """O mestre SPI troca bytes com o módulo, com a seleção em CS_N."""
    await start(dut)
    check_equal(int(dut.o_wm_cs_n.value), 1)
    await bus.write(dut, SPI_DIVIDER, FAST_DIVIDER)
    pins = Wires(
        dut.o_wm_sck,
        dut.o_wm_copi,
        dut.i_wm_cipo,
        Bit(dut.o_wm_cs_n, 0, dut.i_clk),
    )
    slave = WordSlave(pins, (0, 0), SPI_WORD_BITS, [0x3C, 0xC3])
    slave.start()
    control = CS_ASSERT | SPI_WORD_BITS << 8
    await bus.write(dut, SPI_CONTROL, control)
    check_equal(int(dut.o_wm_cs_n.value), 0)
    await bus.write(dut, SPI_TX_DATA, 0xA5)
    await bus.write(dut, SPI_TX_DATA, 0x5A)
    await polling.wait_status(dut, SPI_STATUS, DONE, DONE)
    check(slave.received == [0xA5, 0x5A], f"{slave.received}")
    check_equal(await bus.read(dut, SPI_RX_DATA), 0x3C)
    check_equal(await bus.read(dut, SPI_RX_DATA), 0xC3)
    await bus.write(dut, SPI_CONTROL, 0)
    check_equal(int(dut.o_wm_cs_n.value), 1)
    slave.stop()


async def uart_receive(dut: WifiDut) -> int:
    """Decodifique um quadro 8N1 enviado ao módulo.

    Parameters
    ----------
    dut : WifiDut
        Projeto sob teste.

    Returns
    -------
    int
        O byte do quadro.
    """
    await with_timeout(FallingEdge(dut.o_wm_rx), 400, "us")
    await bus.cycles(dut, BIT_CYCLES // 2)
    check_equal(int(dut.o_wm_rx.value), 0)
    value = 0
    for bit in range(8):
        await bus.cycles(dut, BIT_CYCLES)
        value |= int(dut.o_wm_rx.value) << bit
    await bus.cycles(dut, BIT_CYCLES)
    check_equal(int(dut.o_wm_rx.value), 1)
    return value


@cocotb.test()
async def test_uart_both_ways(dut: WifiDut) -> None:
    """A UART envia ao módulo e recebe dele."""
    await start(dut)
    await bus.write(dut, UART_TX_DATA, 0x55)
    check_equal(await uart_receive(dut), 0x55)
    bits = [0] + [0xA5 >> bit & 1 for bit in range(8)] + [1]
    for level in bits:
        dut.i_wm_tx.value = level
        await bus.cycles(dut, BIT_CYCLES)
    dut.i_wm_tx.value = 1
    await bus.cycles(dut, STOP_MARGIN_CYCLES)
    check_equal(
        await bus.read(dut, UART_STATUS) & UART_RX_VALID, UART_RX_VALID
    )
    check_equal(await bus.read(dut, UART_RX_DATA), 0xA5)


@cocotb.test()
async def test_interrupt_sum(dut: WifiDut) -> None:
    """A interrupção soma o controle, o SPI e a UART."""
    await start(dut)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, UART_CONTROL, 0x02)
    await bus.cycles(dut, 2)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, UART_CONTROL, 0)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, CTRL, RISE_IRQ)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, STATUS, RISE)
    dut.i_wm_ack.value = 0
    await bus.cycles(dut, 4)
    dut.i_wm_ack.value = 1
    await bus.cycles(dut, 4)
    check_equal(int(dut.o_irq.value), 1)

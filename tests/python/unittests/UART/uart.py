"""Memory-mapped UART: registers, 8N1 RX/TX, sticky errors and IRQ.

The test configuration sets BAUD_FREQ=1 and BAUD_LIMIT=0, making ce16
pulse on every clock. A serial bit therefore lasts exactly 16 clock
cycles while keeping the complete OpenCores receiver/transmitter
datapath in the test.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout

from tests.python.utils import bus
from tests.python.utils.dut import UartDut

TX_DATA, RX_DATA, STATUS, CONTROL = range(4)
RX_VALID = 1 << 0
TX_READY = 1 << 1
RX_OVERRUN = 1 << 2
TX_DROPPED = 1 << 3
RX_IRQ_ENABLE = 1 << 0

BIT_CYCLES = 16
DATA_BITS = 8
STOP_MARGIN_CYCLES = 4
TX_READY_LIMIT = 32


async def setup(dut: UartDut) -> None:
    """Idle the serial line and reset the design.

    Parameters
    ----------
    dut : UartDut
        The design under test.
    """
    dut.i_uart_rx.value = 1
    await bus.reset(dut)


async def send_serial_byte(dut: UartDut, value: int) -> None:
    """Drive one 8N1 byte into uart_rx, least-significant bit first.

    Parameters
    ----------
    dut : UartDut
        The design under test.
    value : int
        Byte to send.
    """
    dut.i_uart_rx.value = 0
    await bus.cycles(dut, BIT_CYCLES)

    for bit in range(DATA_BITS):
        dut.i_uart_rx.value = (value >> bit) & 1
        await bus.cycles(dut, BIT_CYCLES)

    dut.i_uart_rx.value = 1
    await bus.cycles(dut, BIT_CYCLES + STOP_MARGIN_CYCLES)


async def receive_serial_byte(dut: UartDut) -> int:
    """Decode one 8N1 byte emitted on uart_tx.

    Parameters
    ----------
    dut : UartDut
        The design under test.

    Returns
    -------
    int
        The byte received.
    """
    await with_timeout(FallingEdge(dut.o_uart_tx), 5, "us")

    await bus.cycles(dut, BIT_CYCLES // 2)
    assert int(dut.o_uart_tx.value) == 0, "start bit low at its midpoint"

    value = 0
    for bit in range(DATA_BITS):
        await bus.cycles(dut, BIT_CYCLES)
        value |= int(dut.o_uart_tx.value) << bit

    await bus.cycles(dut, BIT_CYCLES)
    assert int(dut.o_uart_tx.value) == 1, "stop bit must be high"
    return value


async def wait_tx_ready(dut: UartDut, limit: int = TX_READY_LIMIT) -> None:
    """Poll the status until the transmitter is ready.

    Parameters
    ----------
    dut : UartDut
        The design under test.
    limit : int
        Maximum number of polls.

    Raises
    ------
    AssertionError
        If the transmitter is still busy after the last poll.
    """
    for _ in range(limit):
        if await bus.read(dut, STATUS) & TX_READY:
            return
    message = "transmitter did not become ready"
    raise AssertionError(message)


@cocotb.test()
async def test_reset_state_and_register_map(dut: UartDut) -> None:
    """The registers have their reset values."""
    await setup(dut)

    assert await bus.read(dut, TX_DATA) == 0
    assert await bus.read(dut, RX_DATA) == 0
    assert await bus.read(dut, STATUS) == TX_READY
    assert await bus.read(dut, CONTROL) == 0
    assert int(dut.o_irq.value) == 0
    assert int(dut.o_uart_tx.value) == 1, "an idle UART line is high"


@cocotb.test()
async def test_transmit_complete_8n1_frame(dut: UartDut) -> None:
    """A written byte leaves as a complete 8N1 frame."""
    await setup(dut)

    receiver = cocotb.start_soon(receive_serial_byte(dut))
    await bus.write(dut, TX_DATA, 0xA5)

    assert await receiver == 0xA5
    await wait_tx_ready(dut)


@cocotb.test()
async def test_write_while_tx_busy_is_dropped_and_reported(
    dut: UartDut,
) -> None:
    """A write during a transmission is dropped and flagged."""
    await setup(dut)

    receiver = cocotb.start_soon(receive_serial_byte(dut))
    await bus.write(dut, TX_DATA, 0x3C)
    assert await bus.read(dut, STATUS) & TX_READY == 0

    await bus.write(dut, TX_DATA, 0xE7)
    assert await bus.read(dut, STATUS) & TX_DROPPED
    assert await receiver == 0x3C, "the in-flight byte must not be corrupted"

    await bus.write(dut, STATUS, TX_DROPPED)
    assert await bus.read(dut, STATUS) & TX_DROPPED == 0
    await wait_tx_ready(dut)
    await bus.cycles(dut, BIT_CYCLES * 2)
    assert int(dut.o_uart_tx.value) == 1, "no second frame may start"


@cocotb.test()
async def test_receive_byte_and_rx_data_read_consumes_rx_valid(
    dut: UartDut,
) -> None:
    """Reading RX_DATA returns the byte and clears RX_VALID."""
    await setup(dut)

    await send_serial_byte(dut, 0x5A)
    status = await bus.read(dut, STATUS)
    assert status & (RX_VALID | TX_READY) == RX_VALID | TX_READY
    assert await bus.read(dut, RX_DATA) == 0x5A
    assert await bus.read(dut, STATUS) & RX_VALID == 0


@cocotb.test()
async def test_rx_overrun_keeps_latest_byte_and_is_w1c(
    dut: UartDut,
) -> None:
    """An overrun keeps the newest byte and clears on write of one."""
    await setup(dut)

    await send_serial_byte(dut, 0x12)
    await send_serial_byte(dut, 0x34)

    status = await bus.read(dut, STATUS)
    assert status & RX_VALID
    assert status & RX_OVERRUN
    newest = await bus.read(dut, RX_DATA)
    assert newest == 0x34, "overrun policy keeps the newest byte"
    after_read = await bus.read(dut, STATUS)
    assert after_read & RX_OVERRUN, "reading RX_DATA keeps the error"

    await bus.write(dut, STATUS, RX_OVERRUN)
    assert await bus.read(dut, STATUS) & RX_OVERRUN == 0


@cocotb.test()
async def test_simultaneous_rx_data_read_and_arrival_keeps_new_byte(
    dut: UartDut,
) -> None:
    """A read coinciding with an arrival keeps the new byte."""
    await setup(dut)
    await send_serial_byte(dut, 0x11)

    sender = cocotb.start_soon(send_serial_byte(dut, 0x22))
    await with_timeout(RisingEdge(dut.phy_new_rx_data), 5, "us")

    # uartRx raises newRxData just after a clock edge. Assert read
    # before the following edge, when UART.vhd observes the pulse and
    # captures the byte.
    dut.i_address.value = RX_DATA
    dut.i_read.value = 1
    await Timer(1, unit="ns")
    previous = int(dut.o_data_out.value)
    assert previous == 0x11, "the read returns the previous byte"
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_read.value = 0

    await sender
    status = await bus.read(dut, STATUS)
    assert status & RX_VALID, "the coincident new byte remains pending"
    assert status & RX_OVERRUN == 0, "consuming the old byte avoids overrun"
    assert await bus.read(dut, RX_DATA) == 0x22


@cocotb.test()
async def test_rx_interrupt_enable_and_clear_by_rx_data_read(
    dut: UartDut,
) -> None:
    """The RX interrupt is enabled by CONTROL and cleared by a read."""
    await setup(dut)

    await bus.write(dut, CONTROL, RX_IRQ_ENABLE)
    assert await bus.read(dut, CONTROL) == RX_IRQ_ENABLE
    await send_serial_byte(dut, 0xC3)
    assert int(dut.o_irq.value) == 1

    assert await bus.read(dut, RX_DATA) == 0xC3
    assert int(dut.o_irq.value) == 0

    await bus.write(dut, CONTROL, 0)
    assert await bus.read(dut, CONTROL) == 0


@cocotb.test()
async def test_tx_read_and_rx_write_are_side_effect_free(
    dut: UartDut,
) -> None:
    """Reading TX_DATA and writing RX_DATA change nothing."""
    await setup(dut)
    await send_serial_byte(dut, 0x6D)

    # TX_DATA is write-only: reading it neither exposes nor consumes RX.
    assert await bus.read(dut, TX_DATA) == 0
    assert await bus.read(dut, STATUS) & RX_VALID

    # RX_DATA is read-only: writing it neither launches TX nor changes
    # the RX data.
    await bus.write(dut, RX_DATA, 0xA5)
    status = await bus.read(dut, STATUS)
    assert status & (RX_VALID | TX_READY) == RX_VALID | TX_READY
    await bus.cycles(dut, BIT_CYCLES * 2)
    assert int(dut.o_uart_tx.value) == 1

    assert await bus.read(dut, RX_DATA) == 0x6D
    assert await bus.read(dut, STATUS) & RX_VALID == 0

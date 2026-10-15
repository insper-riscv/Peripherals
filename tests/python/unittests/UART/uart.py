"""Memory-mapped UART: registers, 8N1 RX/TX, sticky errors and IRQ.

The test configuration sets BAUD_FREQ=1 and BAUD_LIMIT=0, making ce16 pulse on
every clock. A serial bit therefore lasts exactly 16 clock cycles while keeping
the complete OpenCores receiver/transmitter datapath in the test.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout

from tests.python.utils import bus


DATA, STATUS, CONTROL, RESERVED = range(4)
RX_VALID = 1 << 0
TX_READY = 1 << 1
RX_OVERRUN = 1 << 2
TX_DROPPED = 1 << 3
RX_IRQ_ENABLE = 1 << 0

BIT_CYCLES = 16


async def setup(dut):
    dut.uart_rx.value = 1
    await bus.reset(dut)


async def send_serial_byte(dut, value):
    """Drive one 8N1 byte into uart_rx, least-significant bit first."""
    dut.uart_rx.value = 0
    await bus.cycles(dut, BIT_CYCLES)

    for bit in range(8):
        dut.uart_rx.value = (value >> bit) & 1
        await bus.cycles(dut, BIT_CYCLES)

    dut.uart_rx.value = 1
    await bus.cycles(dut, BIT_CYCLES + 4)


async def receive_serial_byte(dut):
    """Decode one 8N1 byte emitted on uart_tx."""
    await with_timeout(FallingEdge(dut.uart_tx), 5, "us")

    await bus.cycles(dut, BIT_CYCLES // 2)
    assert int(dut.uart_tx.value) == 0, "start bit must still be low at its midpoint"

    value = 0
    for bit in range(8):
        await bus.cycles(dut, BIT_CYCLES)
        value |= int(dut.uart_tx.value) << bit

    await bus.cycles(dut, BIT_CYCLES)
    assert int(dut.uart_tx.value) == 1, "stop bit must be high"
    return value


async def wait_tx_ready(dut, limit=32):
    for _ in range(limit):
        if await bus.read(dut, STATUS) & TX_READY:
            return
    raise AssertionError("transmitter did not become ready")


@cocotb.test()
async def test_reset_state_and_register_map(dut):
    await setup(dut)

    assert await bus.read(dut, DATA) == 0
    assert await bus.read(dut, STATUS) == TX_READY
    assert await bus.read(dut, CONTROL) == 0
    assert await bus.read(dut, RESERVED) == 0
    assert int(dut.irq.value) == 0
    assert int(dut.uart_tx.value) == 1, "an idle UART line is high"


@cocotb.test()
async def test_transmit_complete_8n1_frame(dut):
    await setup(dut)

    receiver = cocotb.start_soon(receive_serial_byte(dut))
    await bus.write(dut, DATA, 0xA5)

    assert await receiver == 0xA5
    await wait_tx_ready(dut)


@cocotb.test()
async def test_write_while_tx_busy_is_dropped_and_reported(dut):
    await setup(dut)

    receiver = cocotb.start_soon(receive_serial_byte(dut))
    await bus.write(dut, DATA, 0x3C)
    assert await bus.read(dut, STATUS) & TX_READY == 0

    await bus.write(dut, DATA, 0xE7)
    assert await bus.read(dut, STATUS) & TX_DROPPED
    assert await receiver == 0x3C, "the in-flight byte must not be corrupted"

    await bus.write(dut, STATUS, TX_DROPPED)
    assert await bus.read(dut, STATUS) & TX_DROPPED == 0
    await wait_tx_ready(dut)
    await bus.cycles(dut, BIT_CYCLES * 2)
    assert int(dut.uart_tx.value) == 1, "the dropped byte must not start a second frame"


@cocotb.test()
async def test_receive_byte_and_read_consumes_rx_valid(dut):
    await setup(dut)

    await send_serial_byte(dut, 0x5A)
    status = await bus.read(dut, STATUS)
    assert status & (RX_VALID | TX_READY) == RX_VALID | TX_READY
    assert await bus.read(dut, DATA) == 0x5A
    assert await bus.read(dut, STATUS) & RX_VALID == 0


@cocotb.test()
async def test_rx_overrun_keeps_latest_byte_and_is_w1c(dut):
    await setup(dut)

    await send_serial_byte(dut, 0x12)
    await send_serial_byte(dut, 0x34)

    status = await bus.read(dut, STATUS)
    assert status & RX_VALID
    assert status & RX_OVERRUN
    assert await bus.read(dut, DATA) == 0x34, "overrun policy keeps the newest byte"
    assert await bus.read(dut, STATUS) & RX_OVERRUN, "reading DATA does not clear errors"

    await bus.write(dut, STATUS, RX_OVERRUN)
    assert await bus.read(dut, STATUS) & RX_OVERRUN == 0


@cocotb.test()
async def test_simultaneous_data_read_and_arrival_preserves_new_byte(dut):
    await setup(dut)
    await send_serial_byte(dut, 0x11)

    sender = cocotb.start_soon(send_serial_byte(dut, 0x22))
    await with_timeout(RisingEdge(dut.phy_new_rx_data), 5, "us")

    # uartRx raises newRxData just after a clock edge. Assert read before the
    # following edge, when UART.vhd observes the pulse and captures the byte.
    dut.address.value = DATA
    dut.read.value = 1
    await Timer(1, unit="ns")
    assert int(dut.data_out.value) == 0x11, "the read returns the previous byte"
    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.read.value = 0

    await sender
    status = await bus.read(dut, STATUS)
    assert status & RX_VALID, "the coincident new byte remains pending"
    assert status & RX_OVERRUN == 0, "consuming the old byte avoids an overrun"
    assert await bus.read(dut, DATA) == 0x22


@cocotb.test()
async def test_rx_interrupt_enable_and_clear_by_data_read(dut):
    await setup(dut)

    await bus.write(dut, CONTROL, RX_IRQ_ENABLE)
    assert await bus.read(dut, CONTROL) == RX_IRQ_ENABLE
    await send_serial_byte(dut, 0xC3)
    assert int(dut.irq.value) == 1

    assert await bus.read(dut, DATA) == 0xC3
    assert int(dut.irq.value) == 0

    await bus.write(dut, CONTROL, 0)
    assert await bus.read(dut, CONTROL) == 0

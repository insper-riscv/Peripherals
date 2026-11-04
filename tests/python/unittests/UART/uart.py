"""Buffered memory-mapped UART: FIFOs, 8N1, sticky errors and IRQ.

The test configuration uses four-byte FIFOs and sets BAUD_FREQ=1 and
BAUD_LIMIT=0, making ce16 pulse on every clock. A serial bit therefore lasts
exactly 16 clock cycles while retaining the complete physical UART datapath.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer, with_timeout

from tests.python.utils import bus


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
FIFO_DEPTH = 4
BIT_CYCLES = 16


def rx_level(status):
    return (status >> RX_LEVEL_SHIFT) & LEVEL_MASK


def tx_level(status):
    return (status >> TX_LEVEL_SHIFT) & LEVEL_MASK


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
    await with_timeout(FallingEdge(dut.uart_tx), 10, "us")

    await bus.cycles(dut, BIT_CYCLES // 2)
    assert int(dut.uart_tx.value) == 0, "start bit must still be low at its midpoint"

    value = 0
    for bit in range(8):
        await bus.cycles(dut, BIT_CYCLES)
        value |= int(dut.uart_tx.value) << bit

    await bus.cycles(dut, BIT_CYCLES)
    assert int(dut.uart_tx.value) == 1, "stop bit must be high"
    return value


async def receive_serial_bytes(dut, count):
    return [await receive_serial_byte(dut) for _ in range(count)]


async def wait_tx_idle(dut, limit=BIT_CYCLES * 16):
    for _ in range(limit):
        if await bus.read(dut, STATUS) & TX_IDLE:
            return
    raise AssertionError("transmitter did not become idle")


@cocotb.test()
async def test_reset_state_and_register_map(dut):
    await setup(dut)

    assert await bus.read(dut, TX_DATA) == 0
    assert await bus.read(dut, RX_DATA) == 0
    assert await bus.read(dut, STATUS) == TX_READY | TX_EMPTY | TX_IDLE
    assert await bus.read(dut, CONTROL) == 0
    assert int(dut.irq.value) == 0
    assert int(dut.uart_tx.value) == 1, "an idle UART line is high"


@cocotb.test()
async def test_transmit_complete_8n1_frame(dut):
    await setup(dut)

    receiver = cocotb.start_soon(receive_serial_byte(dut))
    await bus.write(dut, TX_DATA, 0xA5)

    assert await receiver == 0xA5
    await wait_tx_idle(dut)


@cocotb.test()
async def test_tx_fifo_buffers_order_and_reports_only_full_write(dut):
    await setup(dut)

    # The first byte moves into the physical transmitter while four more fill
    # the FIFO. A sixth immediate write therefore exceeds total capacity.
    accepted_values = [0x30 + index for index in range(FIFO_DEPTH + 1)]
    receiver = cocotb.start_soon(receive_serial_bytes(dut, len(accepted_values)))

    for value in accepted_values:
        await bus.write(dut, TX_DATA, value)

    status = await bus.read(dut, STATUS)
    assert status & TX_READY == 0
    assert status & TX_EMPTY == 0
    assert status & TX_IDLE == 0
    assert tx_level(status) == FIFO_DEPTH
    assert status & TX_DROPPED == 0

    await bus.write(dut, TX_DATA, 0xEE)
    assert await bus.read(dut, STATUS) & TX_DROPPED

    await bus.write(dut, STATUS, TX_DROPPED)
    assert await bus.read(dut, STATUS) & TX_DROPPED == 0

    assert await receiver == accepted_values
    await wait_tx_idle(dut)
    status = await bus.read(dut, STATUS)
    assert status & (TX_READY | TX_EMPTY | TX_IDLE) == TX_READY | TX_EMPTY | TX_IDLE
    assert tx_level(status) == 0


@cocotb.test()
async def test_receive_bytes_are_dequeued_in_order(dut):
    await setup(dut)

    await send_serial_byte(dut, 0x5A)
    await send_serial_byte(dut, 0xC3)

    status = await bus.read(dut, STATUS)
    assert status & RX_VALID
    assert status & RX_FULL == 0
    assert rx_level(status) == 2

    assert await bus.read(dut, RX_DATA) == 0x5A
    status = await bus.read(dut, STATUS)
    assert status & RX_VALID
    assert rx_level(status) == 1

    assert await bus.read(dut, RX_DATA) == 0xC3
    status = await bus.read(dut, STATUS)
    assert status & RX_VALID == 0
    assert rx_level(status) == 0


@cocotb.test()
async def test_rx_overrun_preserves_queued_bytes_and_is_w1c(dut):
    await setup(dut)

    queued = [0x10 + index for index in range(FIFO_DEPTH)]
    for value in queued:
        await send_serial_byte(dut, value)

    status = await bus.read(dut, STATUS)
    assert status & RX_FULL
    assert rx_level(status) == FIFO_DEPTH

    await send_serial_byte(dut, 0xFE)
    status = await bus.read(dut, STATUS)
    assert status & RX_OVERRUN
    assert status & RX_FULL
    assert rx_level(status) == FIFO_DEPTH

    assert [await bus.read(dut, RX_DATA) for _ in range(FIFO_DEPTH)] == queued
    status = await bus.read(dut, STATUS)
    assert status & RX_VALID == 0
    assert status & RX_OVERRUN, "reading RX_DATA does not clear errors"

    await bus.write(dut, STATUS, RX_OVERRUN)
    assert await bus.read(dut, STATUS) & RX_OVERRUN == 0


@cocotb.test()
async def test_simultaneous_full_rx_read_and_arrival_accepts_new_byte(dut):
    await setup(dut)

    queued = [0x21, 0x22, 0x23, 0x24]
    for value in queued:
        await send_serial_byte(dut, value)

    sender = cocotb.start_soon(send_serial_byte(dut, 0x25))
    await with_timeout(RisingEdge(dut.phy_new_rx_data), 10, "us")

    # newRxData rises just after a clock edge. Assert read before the following
    # edge, when the wrapper observes the receive pulse and can pop/push at full.
    dut.address.value = RX_DATA
    dut.read.value = 1
    await Timer(1, unit="ns")
    assert int(dut.data_out.value) == queued[0]
    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.read.value = 0

    await sender
    status = await bus.read(dut, STATUS)
    assert status & RX_FULL
    assert status & RX_OVERRUN == 0
    assert rx_level(status) == FIFO_DEPTH
    assert [await bus.read(dut, RX_DATA) for _ in range(FIFO_DEPTH)] == queued[1:] + [0x25]


@cocotb.test()
async def test_new_rx_overrun_wins_over_simultaneous_w1c(dut):
    await setup(dut)

    for value in range(FIFO_DEPTH):
        await send_serial_byte(dut, value)

    await send_serial_byte(dut, 0xA0)
    assert await bus.read(dut, STATUS) & RX_OVERRUN

    sender = cocotb.start_soon(send_serial_byte(dut, 0xA1))
    await with_timeout(RisingEdge(dut.phy_new_rx_data), 10, "us")

    dut.address.value = STATUS
    dut.data_in.value = RX_OVERRUN
    dut.write.value = 1
    await RisingEdge(dut.clock)
    await Timer(1, unit="ns")
    dut.write.value = 0

    await sender
    assert await bus.read(dut, STATUS) & RX_OVERRUN


@cocotb.test()
async def test_rx_interrupt_remains_until_fifo_is_empty(dut):
    await setup(dut)

    await bus.write(dut, CONTROL, RX_IRQ_ENABLE)
    assert await bus.read(dut, CONTROL) == RX_IRQ_ENABLE

    await send_serial_byte(dut, 0xC3)
    await send_serial_byte(dut, 0xD4)
    assert int(dut.irq.value) == 1

    assert await bus.read(dut, RX_DATA) == 0xC3
    assert int(dut.irq.value) == 1
    assert await bus.read(dut, RX_DATA) == 0xD4
    assert int(dut.irq.value) == 0

    await bus.write(dut, CONTROL, 0)
    assert await bus.read(dut, CONTROL) == 0


@cocotb.test()
async def test_tx_read_and_rx_write_are_side_effect_free(dut):
    await setup(dut)
    await send_serial_byte(dut, 0x6D)

    # TX_DATA is write-only: reading it neither exposes nor consumes RX data.
    assert await bus.read(dut, TX_DATA) == 0
    status = await bus.read(dut, STATUS)
    assert status & RX_VALID
    assert rx_level(status) == 1

    # RX_DATA is read-only: writing it neither launches TX nor changes RX data.
    await bus.write(dut, RX_DATA, 0xA5)
    status = await bus.read(dut, STATUS)
    assert status & RX_VALID
    assert status & TX_IDLE
    assert rx_level(status) == 1
    assert tx_level(status) == 0
    await bus.cycles(dut, BIT_CYCLES * 2)
    assert int(dut.uart_tx.value) == 1

    assert await bus.read(dut, RX_DATA) == 0x6D
    assert await bus.read(dut, STATUS) & RX_VALID == 0

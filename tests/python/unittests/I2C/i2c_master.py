"""I2C master against a behavioral EEPROM: bus actions, registers."""

from itertools import pairwise

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.I2C.driver import (
    EEPROM_WRITE,
    command,
    eeprom_read,
    eeprom_write,
    enable,
    wait_idle,
    write_bytes,
)
from tests.python.unittests.I2C.registers import (
    ABORT,
    ARB_LOST,
    BUS_ACTIVE,
    CMD,
    CTRL,
    DIVIDER,
    DONE,
    ENABLE,
    IRQ_DONE,
    IRQ_ERR,
    NACKED,
    READ,
    REJECTED,
    RX,
    START,
    STATUS,
    STOP,
    TX,
    WRITE,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import I2cDut
from tests.python.utils.i2c_eeprom import I2cEeprom

SMALL = 256
LARGE = 8192
RESET_DIVIDER = 199
WIDE_DIVIDER = 0x1234
TX_VALUE = 0xA5
BYTE_VALUE = 0x5C
MIN_DIVIDER = 2
MIN_EDGES = 8
STARTS = 2


@cocotb.test()
async def test_reset_state(dut: I2cDut) -> None:
    """The registers have their reset values and the lines are free."""
    await bus.reset(dut)
    check(await bus.read(dut, CTRL) == 0)
    check(await bus.read(dut, DIVIDER) == RESET_DIVIDER)
    check(await bus.read(dut, STATUS) == 0)
    check(await bus.read(dut, RX) == 0)
    check(int(dut.o_irq.value) == 0)
    check(int(dut.o_scl.value) == 1 and int(dut.o_sda.value) == 1)


@cocotb.test()
async def test_registers_read_back(dut: I2cDut) -> None:
    """Control, divider and transmit registers read back their value."""
    await bus.reset(dut)
    await bus.write(dut, CTRL, IRQ_DONE | IRQ_ERR)
    check(await bus.read(dut, CTRL) == IRQ_DONE | IRQ_ERR)
    await bus.write(dut, DIVIDER, WIDE_DIVIDER)
    check(await bus.read(dut, DIVIDER) == WIDE_DIVIDER)
    await bus.write(dut, TX, TX_VALUE)
    check(await bus.read(dut, TX) == TX_VALUE)
    await bus.write(dut, DIVIDER, 0)
    check(await bus.read(dut, DIVIDER) == MIN_DIVIDER, "divider below minimum")


@cocotb.test()
async def test_read_data_is_zero_without_read_strobe(dut: I2cDut) -> None:
    """The data output is zero when the processor is not reading."""
    await bus.reset(dut)
    await bus.write(dut, TX, 0xFF)
    dut.i_address.value = TX
    dut.i_read.value = 0
    await Timer(1, unit="ns")
    check(int(dut.o_data_out.value) == 0)


@cocotb.test()
async def test_eeprom_byte_write_and_read_one_address_byte(
    dut: I2cDut,
) -> None:
    """A byte written to a 2 Kbit EEPROM is read back at its address."""
    await enable(dut)
    eeprom = I2cEeprom(dut, size=SMALL, page=8, addr_bytes=1)
    eeprom.start()
    await eeprom_write(dut, 0x2A, [BYTE_VALUE], SMALL)
    check(eeprom.memory[0x2A] == BYTE_VALUE)
    check(await eeprom_read(dut, 0x2A, 1, SMALL) == [BYTE_VALUE])
    status = await bus.read(dut, STATUS)
    check(not status & BUS_ACTIVE, "stop ends the transaction")


@cocotb.test()
async def test_eeprom_page_write_wraps_inside_the_page(dut: I2cDut) -> None:
    """A write longer than the page wraps to the start of the page."""
    await enable(dut)
    eeprom = I2cEeprom(dut, size=SMALL, page=8, addr_bytes=1)
    eeprom.start()
    await eeprom_write(dut, 0x14, list(range(1, 9)), SMALL)
    check(bytes(eeprom.memory[0x14:0x18]) == bytes([1, 2, 3, 4]))
    check(bytes(eeprom.memory[0x10:0x14]) == bytes([5, 6, 7, 8]))
    check(await eeprom_read(dut, 0x10, 8, SMALL) == [5, 6, 7, 8, 1, 2, 3, 4])


@cocotb.test()
async def test_eeprom_two_address_bytes_64_kbit(dut: I2cDut) -> None:
    """A 64 Kbit EEPROM takes two address bytes and a 32 byte page."""
    await enable(dut)
    eeprom = I2cEeprom(dut, size=LARGE, page=32, addr_bytes=2)
    eeprom.start()
    data = [(7 * n + 3) & 0xFF for n in range(32)]
    await eeprom_write(dut, 0x1A40, data, LARGE)
    check(list(eeprom.memory[0x1A40:0x1A60]) == data)
    check(await eeprom_read(dut, 0x1A40, 32, LARGE) == data)
    check(await eeprom_read(dut, 0x1A5F, 2, LARGE) == [data[31], 0xFF])


@cocotb.test()
async def test_ack_polling_sees_nack_during_write_cycle(dut: I2cDut) -> None:
    """The address is refused during the write cycle, then accepted."""
    await enable(dut)
    eeprom = I2cEeprom(dut, size=SMALL, page=8, write_cycles=3000)
    eeprom.start()
    await write_bytes(dut, EEPROM_WRITE, [0x10, 0x77])
    check(not await write_bytes(dut, EEPROM_WRITE, []), "busy refuses")
    status = await bus.read(dut, STATUS)
    check(bool(status & NACKED), "the NACK is flagged")
    for _ in range(200):
        if await write_bytes(dut, EEPROM_WRITE, []):
            break
        await bus.write(dut, STATUS, NACKED)
    await eeprom_write(dut, 0x11, [0x88], SMALL)
    check(bytes(eeprom.memory[0x10:0x12]) == bytes([0x77, 0x88]))
    check(eeprom.counts.nacked_addresses >= 1)


@cocotb.test()
async def test_wrong_device_address_is_nacked(dut: I2cDut) -> None:
    """A device that is not on the bus answers with NACK."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.start()
    status = await command(dut, START | WRITE, 0x92)
    check(bool(status & NACKED))
    check(bool(status & DONE))
    await command(dut, STOP)
    check(int(dut.o_scl.value) == 1 and int(dut.o_sda.value) == 1)


@cocotb.test()
async def test_clock_stretching(dut: I2cDut) -> None:
    """The master waits for a slave that holds SCL low."""
    await enable(dut)
    eeprom = I2cEeprom(dut, size=SMALL, page=8)
    eeprom.stretch_cycles = 150
    eeprom.start()
    await eeprom_write(dut, 0x40, [0xC3, 0x3C], SMALL)
    check(bytes(eeprom.memory[0x40:0x42]) == bytes([0xC3, 0x3C]))
    check(await eeprom_read(dut, 0x40, 2, SMALL) == [0xC3, 0x3C])


@cocotb.test()
async def test_scl_period_follows_divider(dut: I2cDut) -> None:
    """Each SCL period lasts 5 * (divider + 1) system clock cycles."""
    divider = 5
    await enable(dut, divider)
    eeprom = I2cEeprom(dut)
    eeprom.start()
    edges: list[int] = []
    scl_prev = [1]

    async def watch() -> None:
        cycle = 0
        while True:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            cycle += 1
            scl = int(dut.o_scl.value)
            if scl and not scl_prev[0]:
                edges.append(cycle)
            scl_prev[0] = scl

    cocotb.start_soon(watch())
    await command(dut, START | WRITE, 0xA0)
    periods = {b - a for a, b in pairwise(edges)}
    check(len(edges) >= MIN_EDGES)
    check(periods == {5 * (divider + 1)}, f"periods {sorted(periods)}")


@cocotb.test()
async def test_start_and_stop_conditions(dut: I2cDut) -> None:
    """The master gives a start, a repeated start and a stop."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.start()
    await command(dut, START | WRITE, 0xA0)
    check(eeprom.counts.starts == 1 and eeprom.counts.stops == 0)
    status = await bus.read(dut, STATUS)
    check(bool(status & BUS_ACTIVE))
    await command(dut, START | WRITE, 0xA1)
    check(eeprom.counts.starts == STARTS, "repeated start")
    await command(dut, READ | STOP | 0x10)
    check(eeprom.counts.stops == 1)


@cocotb.test()
async def test_sequential_read_acknowledges_every_byte_but_the_last(
    dut: I2cDut,
) -> None:
    """A read with ACK asks for the next byte; with NACK it ends."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.memory[0:4] = bytes([0x11, 0x22, 0x33, 0x44])
    eeprom.start()
    await write_bytes(dut, 0xA0, [0], stop=False)
    await command(dut, START | WRITE, 0xA1)
    values: list[int] = []
    for _ in range(3):
        await command(dut, READ)
        values.append(await bus.read(dut, RX))
    await command(dut, READ | STOP | 0x10)
    values.append(await bus.read(dut, RX))
    check(values == [0x11, 0x22, 0x33, 0x44])


@cocotb.test()
async def test_done_interrupt(dut: I2cDut) -> None:
    """The done interrupt rises at the end of a command, then clears."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.start()
    await bus.write(dut, CTRL, ENABLE | IRQ_DONE)
    await bus.write(dut, TX, 0xA0)
    await bus.write(dut, CMD, START | WRITE)
    check(int(dut.o_irq.value) == 0, "not before the end")
    await wait_idle(dut)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, STATUS, DONE)
    check(int(dut.o_irq.value) == 0)
    await command(dut, STOP)


@cocotb.test()
async def test_error_interrupt_on_nack_and_mask(dut: I2cDut) -> None:
    """A NACK raises the error interrupt only when it is enabled."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.start()
    await command(dut, START | WRITE, 0x92)
    check(int(dut.o_irq.value) == 0, "masked")
    await bus.write(dut, CTRL, ENABLE | IRQ_ERR)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, STATUS, NACKED | DONE)
    check(int(dut.o_irq.value) == 0)
    await command(dut, STOP)


@cocotb.test()
async def test_arbitration_lost(dut: I2cDut) -> None:
    """A second master that sends 0 while this one sends 1 wins."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.fight_bit = 0
    eeprom.start()
    status = await command(dut, START | WRITE, 0xA0)
    check(bool(status & ARB_LOST) and bool(status & DONE))
    check(not status & BUS_ACTIVE)
    check(int(dut.o_scl.value) == 1, "the master released SCL")
    await bus.write(dut, CTRL, ENABLE | IRQ_ERR)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, STATUS, ARB_LOST)
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_start_on_a_busy_bus_loses_arbitration(dut: I2cDut) -> None:
    """A start with SDA held low by someone else is not given."""
    await enable(dut)
    dut.i_slave_sda_low.value = 1
    status = await command(dut, START | WRITE, 0xA0)
    check(bool(status & ARB_LOST))
    dut.i_slave_sda_low.value = 0


@cocotb.test()
async def test_rejected_commands(dut: I2cDut) -> None:
    """Commands that make no sense are refused and flagged."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.start()
    await bus.write(dut, CMD, 0)
    check(await bus.read(dut, STATUS) == REJECTED, "empty command")
    await bus.write(dut, STATUS, REJECTED)
    await bus.write(dut, CMD, WRITE)
    check(await bus.read(dut, STATUS) == REJECTED, "write without start")
    await bus.write(dut, STATUS, REJECTED)
    await bus.write(dut, CMD, START | READ | WRITE)
    check(await bus.read(dut, STATUS) == REJECTED, "read and write")
    await bus.write(dut, STATUS, REJECTED)
    await bus.write(dut, CMD, STOP)
    check(await bus.read(dut, STATUS) == REJECTED, "stop without start")
    await bus.write(dut, STATUS, REJECTED)
    await bus.write(dut, CMD, START | WRITE)
    await bus.write(dut, CMD, START | WRITE)
    status = await wait_idle(dut)
    check(bool(status & REJECTED), "command while busy")
    await command(dut, STOP)


@cocotb.test()
async def test_disabled_master_refuses_commands(dut: I2cDut) -> None:
    """With the master off, a command is refused and lines stay free."""
    await enable(dut)
    await bus.write(dut, CTRL, 0)
    await bus.write(dut, CMD, START | WRITE)
    check(await bus.read(dut, STATUS) == REJECTED)
    check(int(dut.o_scl.value) == 1 and int(dut.o_sda.value) == 1)


@cocotb.test()
async def test_abort_releases_the_bus(dut: I2cDut) -> None:
    """The abort bit ends the command in course and frees the lines."""
    await enable(dut)
    eeprom = I2cEeprom(dut)
    eeprom.stretch_cycles = 100000
    eeprom.start()
    await bus.write(dut, TX, 0xA0)
    await bus.write(dut, CMD, START | WRITE)
    await bus.write(dut, CTRL, ENABLE)
    await bus.cycles(dut, 600)
    check(bool(await bus.read(dut, STATUS) & 1), "stuck by the stretch")
    await bus.write(dut, CTRL, ENABLE | ABORT)
    status = await bus.read(dut, STATUS)
    check(not status & 1 and not status & BUS_ACTIVE)
    check(await bus.read(dut, CTRL) == ENABLE, "abort reads as zero")
    eeprom.stretch_cycles = 0

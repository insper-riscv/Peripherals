"""Software driver of the I2C master written for the tests.

The sequences are the same the C example of the document performs: one
command register write per bus action, and a poll of the busy bit.
"""

from tests.python.unittests.I2C.registers import (
    BUSY,
    CMD,
    CTRL,
    DIVIDER,
    ENABLE,
    NACK,
    NACKED,
    READ,
    RX,
    START,
    STATUS,
    STOP,
    TX,
    WRITE,
)
from tests.python.utils import bus
from tests.python.utils.dut import I2cDut

POLL_LIMIT = 4000
ONE_BYTE_SIZE = 256
EEPROM_WRITE = 0xA0
EEPROM_READ = 0xA1


async def enable(dut: I2cDut, divider: int = 3) -> None:
    """Reset the bus, set the divider and turn the master on.

    Parameters
    ----------
    dut : I2cDut
        The design under test.
    divider : int
        Value of the divider register.
    """
    dut.i_slave_scl_low.value = 0
    dut.i_slave_sda_low.value = 0
    await bus.reset(dut)
    await bus.write(dut, DIVIDER, divider)
    await bus.write(dut, CTRL, ENABLE)


async def wait_idle(dut: I2cDut) -> int:
    """Poll the status until the command ends.

    Parameters
    ----------
    dut : I2cDut
        The design under test.

    Returns
    -------
    int
        The status word read when the busy bit was clear.

    Raises
    ------
    TimeoutError
        If the master stays busy for too long.
    """
    for _ in range(POLL_LIMIT):
        status = await bus.read(dut, STATUS)
        if not status & BUSY:
            return status
    raise TimeoutError("the I2C master stayed busy")


async def command(dut: I2cDut, flags: int, tx: int | None = None) -> int:
    """Issue a command and wait for its end.

    Parameters
    ----------
    dut : I2cDut
        The design under test.
    flags : int
        Bits of the command register.
    tx : int | None
        Byte to load in the transmit register first.

    Returns
    -------
    int
        The status word at the end.
    """
    if tx is not None:
        await bus.write(dut, TX, tx)
    await bus.write(dut, CMD, flags)
    return await wait_idle(dut)


async def write_bytes(
    dut: I2cDut, device: int, data: list[int], stop: bool = True
) -> bool:
    """Send an address byte and data bytes, as a write transaction.

    Parameters
    ----------
    dut : I2cDut
        The design under test.
    device : int
        Address byte with the write bit.
    data : list[int]
        Bytes after the address.
    stop : bool
        End with a stop condition.

    Returns
    -------
    bool
        True when every byte was acknowledged.
    """
    status = await command(dut, START | WRITE, device)
    acked = not status & NACKED
    for index, value in enumerate(data):
        last = index == len(data) - 1
        flags = WRITE | (STOP if last and stop else 0)
        status = await command(dut, flags, value)
        acked = acked and not status & NACKED
    if not data and stop:
        await command(dut, STOP)
    return acked


async def read_bytes(dut: I2cDut, device: int, count: int) -> list[int]:
    """Read bytes after a repeated start, ending with NACK and stop.

    Parameters
    ----------
    dut : I2cDut
        The design under test.
    device : int
        Address byte with the read bit.
    count : int
        Bytes to read.

    Returns
    -------
    list[int]
        The bytes received.
    """
    await command(dut, START | WRITE, device)
    values: list[int] = []
    for index in range(count):
        last = index == count - 1
        await command(dut, READ | (NACK | STOP if last else 0))
        values.append(await bus.read(dut, RX))
    return values


def address_bytes(address: int, size: int) -> list[int]:
    """Return the address bytes of an EEPROM of the given size.

    Parameters
    ----------
    address : int
        Address inside the array.
    size : int
        Size of the array in bytes.

    Returns
    -------
    list[int]
        One byte up to 256 bytes of array, two bytes above.
    """
    if size <= ONE_BYTE_SIZE:
        return [address & 0xFF]
    return [(address >> 8) & 0xFF, address & 0xFF]


async def eeprom_write(
    dut: I2cDut, address: int, data: list[int], size: int
) -> None:
    """Write a page and wait for the write cycle by polling the ACK.

    Parameters
    ----------
    dut : I2cDut
        The design under test.
    address : int
        Address of the first byte.
    data : list[int]
        Bytes of the page.
    size : int
        Size of the array in bytes.
    """
    await write_bytes(dut, EEPROM_WRITE, address_bytes(address, size) + data)
    for _ in range(200):
        acked = await write_bytes(dut, EEPROM_WRITE, [])
        if acked:
            return
        await bus.write(dut, STATUS, NACKED)
    raise TimeoutError("the write cycle never ended")


async def eeprom_read(
    dut: I2cDut, address: int, count: int, size: int
) -> list[int]:
    """Read bytes from a given address (random read).

    Parameters
    ----------
    dut : I2cDut
        The design under test.
    address : int
        Address of the first byte.
    count : int
        Bytes to read.
    size : int
        Size of the array in bytes.

    Returns
    -------
    list[int]
        The bytes read.
    """
    await write_bytes(
        dut, EEPROM_WRITE, address_bytes(address, size), stop=False
    )
    return await read_bytes(dut, EEPROM_READ, count)

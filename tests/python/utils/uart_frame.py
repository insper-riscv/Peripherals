"""Serial frames of the UART with parity and one or two stop bits.

The tests use ``BAUD_FREQ=1`` and ``BAUD_LIMIT=0``, so every serial bit
lasts sixteen clock cycles.
"""

from dataclasses import dataclass

from cocotb.triggers import FallingEdge, with_timeout

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import UartDut

BIT_CYCLES = 16
DATA_BITS = 8
STOP_MARGIN_CYCLES = 4
FRAME_TIMEOUT_US = 20
STATUS = 2
TX_IDLE = 1 << 6
IDLE_POLL_LIMIT = BIT_CYCLES * 14


@dataclass(frozen=True)
class Format:
    """Format of a serial frame.

    Attributes
    ----------
    parity : str
        ``"none"``, ``"even"`` or ``"odd"``.
    stop_bits : int
        Number of stop bits, one or two.
    """

    parity: str = "none"
    stop_bits: int = 1

    @property
    def control(self) -> int:
        """Bits 5:3 of CONTROL (stop, parity odd, parity enable)."""
        value = 0
        if self.parity != "none":
            value |= 1 << 3
        if self.parity == "odd":
            value |= 1 << 4
        if self.stop_bits == 2:  # noqa: PLR2004
            value |= 1 << 5
        return value


def parity_bit(value: int, parity: str) -> int:
    """Return the parity bit that a byte asks for.

    Parameters
    ----------
    value : int
        Data byte.
    parity : str
        ``"even"`` or ``"odd"``.

    Returns
    -------
    int
        Bit that makes the number of ones even or odd.
    """
    ones = value.bit_count() & 1
    return ones ^ (1 if parity == "odd" else 0)


async def send_frame(
    dut: UartDut,
    value: int,
    fmt: Format,
    *,
    bad_parity: bool = False,
    bad_stop: bool = False,
) -> None:
    """Send a frame by the serial input, with the faults asked for.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.
    value : int
        Byte sent.
    fmt : Format
        Format of the frame.
    bad_parity : bool
        Invert the parity bit.
    bad_stop : bool
        Send the first stop bit at zero.
    """
    bits = [0] + [(value >> bit) & 1 for bit in range(DATA_BITS)]
    if fmt.parity != "none":
        bits.append(parity_bit(value, fmt.parity) ^ int(bad_parity))
    bits.append(0 if bad_stop else 1)
    bits.extend([1] * (fmt.stop_bits - 1))
    for level in bits:
        dut.i_uart_rx.value = level
        await bus.cycles(dut, BIT_CYCLES)
    dut.i_uart_rx.value = 1
    await bus.cycles(dut, STOP_MARGIN_CYCLES)


async def receive_frame(dut: UartDut, fmt: Format) -> int:
    """Decode one frame from the serial output and check its format.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.
    fmt : Format
        Format the frame must have.

    Returns
    -------
    int
        Data byte observed.
    """
    await with_timeout(FallingEdge(dut.o_uart_tx), FRAME_TIMEOUT_US, "us")
    await bus.cycles(dut, BIT_CYCLES // 2)
    check(int(dut.o_uart_tx.value) == 0, "start bit low")
    value = 0
    for bit in range(DATA_BITS):
        await bus.cycles(dut, BIT_CYCLES)
        value |= int(dut.o_uart_tx.value) << bit
    if fmt.parity != "none":
        await bus.cycles(dut, BIT_CYCLES)
        check(
            int(dut.o_uart_tx.value) == parity_bit(value, fmt.parity),
            f"parity bit of {value:#04x}",
        )
    for index in range(fmt.stop_bits):
        await bus.cycles(dut, BIT_CYCLES)
        check(int(dut.o_uart_tx.value) == 1, f"stop bit {index}")
    return value


async def reset_idle(dut: UartDut) -> None:
    """Leave the serial line idle and reset the UART.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.
    """
    dut.i_uart_rx.value = 1
    await bus.reset(dut)


async def wait_tx_idle(dut: UartDut) -> None:
    """Wait until the queue and the transmitter are idle.

    Parameters
    ----------
    dut : UartDut
        UART exercitada pelo teste.

    Raises
    ------
    AssertionError
        If the transmitter does not become idle within the limit.
    """
    for _ in range(IDLE_POLL_LIMIT):
        if await bus.read(dut, STATUS) & TX_IDLE:
            return
    message = "the transmitter did not become idle"
    raise AssertionError(message)

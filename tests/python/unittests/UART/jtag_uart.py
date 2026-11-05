"""JTAG_UART: the byte queues between the core and a JTAG host.

The testbench plays the core (one pulse of we or re) and the Virtual
JTAG instance (it drives the scan states of the chain).
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.utils import bus, jtag
from tests.python.utils.check import check
from tests.python.utils.dut import JtagUartDut

CLK_NS = 20
DEPTH = 64
SCAN_BITS = 48
TXDATA, RXDATA, STATUS = 0, 1, 2
PUSH_BIT = 1 << 8
BYTES_SHIFT = 32
COUNT_SHIFT = 32
COUNT_MASK = 0b111
MAX_SCANS = 8
SETTLE_CYCLES = 4


async def _post_edge(dut: JtagUartDut) -> None:
    """Wait for a clock edge and let the signals settle.

    Parameters
    ----------
    dut : JtagUartDut
        The design under test.
    """
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def _start(dut: JtagUartDut) -> None:
    """Start the clock, reset the design and select the data register.

    Parameters
    ----------
    dut : JtagUartDut
        The design under test.
    """
    for signal in (dut.i_we, dut.i_re, dut.i_tck, dut.i_tdi):
        signal.value = 0
    dut.i_addr.value = 0
    dut.i_wdata.value = 0
    dut.i_ir_in.value = 0
    # an idle pulse leaves every scan state low
    await jtag.tck(dut)
    await bus.hold_reset(dut, 4, CLK_NS)
    await _post_edge(dut)
    await jtag.tck(dut, ir=1)


async def _core_write(dut: JtagUartDut, value: int) -> None:
    """Write a byte to the transmit queue from the core side.

    Parameters
    ----------
    dut : JtagUartDut
        The design under test.
    value : int
        The byte.
    """
    dut.i_addr.value = TXDATA
    dut.i_wdata.value = value
    dut.i_we.value = 1
    await _post_edge(dut)
    dut.i_we.value = 0


async def _core_read(dut: JtagUartDut, address: int) -> int:
    """Read a register from the core side.

    Parameters
    ----------
    dut : JtagUartDut
        The design under test.
    address : int
        Word address.

    Returns
    -------
    int
        The value sampled before the clock edge.
    """
    dut.i_addr.value = address
    dut.i_re.value = 1
    await FallingEdge(dut.i_clk)
    value = int(dut.o_rdata.value)
    await _post_edge(dut)
    dut.i_re.value = 0
    return value


async def _scan(dut: JtagUartDut, command: int = 0) -> int:
    """Run one scan of the 48-bit register.

    Parameters
    ----------
    dut : JtagUartDut
        The design under test.
    command : int
        The word shifted in: the push flag and the byte.

    Returns
    -------
    int
        The word shifted out.
    """
    await jtag.tck(dut, "cdr")
    out = 0
    for i in range(SCAN_BITS):
        dut.i_tdi.value = (command >> i) & 1
        await Timer(1, unit="ns")
        out |= int(dut.o_tdo.value) << i
        await jtag.tck(dut, "sdr")
    await jtag.tck(dut, "udr")
    for _ in range(SETTLE_CYCLES):
        await _post_edge(dut)
    return out


async def _host_bytes(dut: JtagUartDut) -> list[int]:
    """Scan until the host has seen every byte the core queued.

    Parameters
    ----------
    dut : JtagUartDut
        The design under test.

    Returns
    -------
    list[int]
        The bytes, in the order the core wrote them.
    """
    received: list[int] = []
    idle = 0
    for _ in range(MAX_SCANS * DEPTH):
        word = await _scan(dut)
        count = (word >> COUNT_SHIFT) & COUNT_MASK
        received.extend((word >> (8 * n)) & 0xFF for n in range(count))
        idle = 0 if count else idle + 1
        if idle >= MAX_SCANS // 2:
            break
    return received


@cocotb.test()
async def test_status_after_reset(dut: JtagUartDut) -> None:
    """Both queues are empty and nothing is lost."""
    await _start(dut)
    status = await _core_read(dut, STATUS)
    check(status == DEPTH, f"status {status:#x}")
    check(await _core_read(dut, RXDATA) == 0, "empty receive queue")
    check(await _core_read(dut, TXDATA) == 0, "TXDATA reads zero")


@cocotb.test()
async def test_core_bytes_reach_the_host_in_order(dut: JtagUartDut) -> None:
    """Bytes written by the core come out of the scan in order."""
    await _start(dut)
    sent = [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0x00, 0xFF, 0x7E]
    for byte in sent:
        await _core_write(dut, byte)
    status = await _core_read(dut, STATUS)
    check(status & 0xFF == DEPTH - len(sent), f"free places {status:#x}")
    received = await _host_bytes(dut)
    check(received == sent, f"host got {received}")
    status = await _core_read(dut, STATUS)
    check(status & 0xFF == DEPTH, "transmit queue drained")


@cocotb.test()
async def test_host_bytes_reach_the_core_in_order(dut: JtagUartDut) -> None:
    """Bytes pushed by the host are read by the core, one at a time."""
    await _start(dut)
    sent = [0x01, 0x80, 0xA5, 0x5A]
    for byte in sent:
        await _scan(dut, PUSH_BIT | byte)
    for _ in range(3):
        await _scan(dut)
    status = await _core_read(dut, STATUS)
    check((status >> 8) & 0xFF == len(sent), f"waiting {status:#x}")
    for byte in sent:
        word = await _core_read(dut, RXDATA)
        check(word == PUSH_BIT | byte, f"expected {byte:#x}, got {word:#x}")
    check(await _core_read(dut, RXDATA) == 0, "queue empty after the reads")


@cocotb.test()
async def test_scan_without_push_delivers_nothing(dut: JtagUartDut) -> None:
    """The byte of a command only counts when the push flag is set."""
    await _start(dut)
    await _scan(dut, 0x55)
    for _ in range(3):
        await _scan(dut)
    check(await _core_read(dut, RXDATA) == 0, "no byte without the flag")


@cocotb.test()
async def test_attached_flag_is_set_by_a_scan(dut: JtagUartDut) -> None:
    """The status shows a host once one has scanned."""
    await _start(dut)
    check((await _core_read(dut, STATUS) >> 17) & 1 == 0, "no host yet")
    for _ in range(3):
        await _scan(dut)
    check((await _core_read(dut, STATUS) >> 17) & 1 == 1, "host attached")


@cocotb.test()
async def test_full_transmit_queue_drops_and_flags(dut: JtagUartDut) -> None:
    """A write to a full queue is lost and flagged."""
    await _start(dut)
    for byte in range(DEPTH):
        await _core_write(dut, byte)
    status = await _core_read(dut, STATUS)
    check(status & 0xFF == 0, f"queue should be full: {status:#x}")
    check((status >> 16) & 1 == 0, "nothing lost yet")
    await _core_write(dut, 0xEE)
    status = await _core_read(dut, STATUS)
    check((status >> 16) & 1 == 1, "loss flagged")
    status = await _core_read(dut, STATUS)
    check((status >> 16) & 1 == 0, "reading the status clears the flag")
    received = await _host_bytes(dut)
    check(received == list(range(DEPTH)), "the dropped byte never appears")

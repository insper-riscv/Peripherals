"""CRC-32 register: nibble steps against the host CRC-32."""

import zlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.checks import check_equal
from tests.python.unittests.dut import Dut
from tests.python.unittests.ETH.driver import pulse, reset_edges
from tests.python.unittests.ETH.model import fcs, to_nibbles
from tests.python.utils.rng import seeded

CLOCK_NS = 10
FINAL_XOR = 0xFFFFFFFF
RESIDUE = 0xDEBB20E3
MESSAGES = 20


async def absorb(dut: Dut, data: bytes) -> None:
    """Feed the nibbles of the data to the register.

    Parameters
    ----------
    dut : Dut
        The design under test.
    data : bytes
        Bytes to absorb.
    """
    for nibble in to_nibbles(data):
        dut.i_nibble.value = nibble
        dut.i_enable.value = 1
        await RisingEdge(dut.i_clk)
    dut.i_enable.value = 0
    await Timer(1, unit="ns")


async def clear(dut: Dut) -> None:
    """Return the register to its initial value.

    Parameters
    ----------
    dut : Dut
        The design under test.
    """
    await pulse(dut.i_clk, dut.i_clear)
    await Timer(1, unit="ns")


@cocotb.test()
async def test_matches_host_crc(dut: Dut) -> None:
    """The state equals the host CRC-32; the FCS gives the residue."""
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_clear.value = 0
    dut.i_enable.value = 0
    dut.i_nibble.value = 0
    await reset_edges(dut, 1)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_crc.value), FINAL_XOR)
    rng = seeded(7)
    for length in range(1, MESSAGES + 1):
        data = rng.randbytes(length * 5)
        await clear(dut)
        await absorb(dut, data)
        check_equal(int(dut.o_crc.value) ^ FINAL_XOR, zlib.crc32(data))
        check_equal(int(dut.o_residue_ok.value), 0)
        await absorb(dut, fcs(data))
        check_equal(int(dut.o_crc.value), RESIDUE)
        check_equal(int(dut.o_residue_ok.value), 1)

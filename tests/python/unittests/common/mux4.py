"""GENERIC_MUX_4X1: the output is the selected source, for every selector."""

import cocotb
from cocotb.triggers import Timer

PATTERNS = (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88)


async def _check(dut, n_sources):
    for i in range(n_sources):
        getattr(dut, f"source_{i + 1}").value = PATTERNS[i]
    for sel in range(n_sources):
        dut.selector.value = sel
        await Timer(1, unit="ns")
        got = int(dut.destination.value)
        assert got == PATTERNS[sel], f"selector={sel}: got {got:#x}, expected {PATTERNS[sel]:#x}"


@cocotb.test()
async def test_mux_4x1_selects_each_source(dut):
    await _check(dut, 4)

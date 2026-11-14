"""Backend VGA: canais, apagamento e repouso do reset."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.unittests.video.signals import VgaDut
from tests.python.utils.check import check
from tests.python.utils.rng import seeded

SEED = 0xBAC
CLOCK_NS = 10
CYCLES = 2000
RESET_EDGES = 3
LIT_PROB = 0.7
CHANNELS = 3


async def start(dut: VgaDut) -> None:
    """Inicia o clock com as entradas em repouso e aplica o reset.

    Parameters
    ----------
    dut : VgaDut
        Backend sob teste.
    """
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_color.value = 0
    dut.i_lit.value = 0
    dut.i_visible.value = 0
    dut.i_hs.value = 0
    dut.i_vs.value = 0
    dut.i_rst.value = 1
    for _ in range(RESET_EDGES):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


@cocotb.test()
async def test_reset_rest_levels(dut: VgaDut) -> None:
    """O reset leva as saídas ao repouso da polaridade do modo."""
    await start(dut)
    h_idle = 0 if int(dut.h_sync_positive.value) else 1
    v_idle = 0 if int(dut.v_sync_positive.value) else 1
    for channel in (dut.o_r, dut.o_g, dut.o_b):
        check(int(channel.value) == 0, "cores pretas")
    check(int(dut.o_hs.value) == h_idle, "HS inativo")
    check(int(dut.o_vs.value) == v_idle, "VS inativo")
    check(int(dut.o_blank_n.value) == 0, "apagamento ativo")
    check(int(dut.o_sync_n.value) == 0, "SYNC_N em zero")


@cocotb.test()
async def test_random_pixels(dut: VgaDut) -> None:
    """Cada canal sai do seu campo, apagado fora da imagem acesa."""
    bits = int(dut.channel_bits.value)
    mask = (1 << bits) - 1
    rng = seeded(SEED + bits)
    await start(dut)
    dut.i_rst.value = 0
    for _ in range(CYCLES):
        color = rng.getrandbits(CHANNELS * bits)
        lit = int(rng.random() < LIT_PROB)
        visible, hs, vs = (rng.getrandbits(1) for _ in range(3))
        dut.i_color.value = color
        dut.i_lit.value = lit
        dut.i_visible.value = visible
        dut.i_hs.value = hs
        dut.i_vs.value = vs
        await FallingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        want = (
            ((color >> (2 * bits)) & mask) * lit,
            ((color >> bits) & mask) * lit,
            (color & mask) * lit,
            hs,
            vs,
            visible,
        )
        got = (
            int(dut.o_r.value),
            int(dut.o_g.value),
            int(dut.o_b.value),
            int(dut.o_hs.value),
            int(dut.o_vs.value),
            int(dut.o_blank_n.value),
        )
        check(got == want, f"{got} != {want}")

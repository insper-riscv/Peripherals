"""Áudio I2S com início automático: o tom sai sem software."""

import itertools

import cocotb

from tests.python.unittests.audio.common import (
    CONTROL,
    TONE_EN,
    TX_EN,
    has_pairs,
    init_pins,
    pairs_of,
    start_codec,
    wait_until,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioDut

AMPLITUDE = 0x2000
HALF = 24
FRAMES = 60
WORD_BITS = 24


@cocotb.test()
async def tone_without_software(dut: AudioDut) -> None:
    """Toque 1 kHz logo depois do reset, sem nenhuma escrita."""
    init_pins(dut)
    await bus.reset(dut)
    codec = await start_codec(dut, WORD_BITS, [])
    control = await bus.read(dut, CONTROL)
    check(control & TONE_EN != 0 and control & TX_EN != 0, "ligado")
    await wait_until(dut, has_pairs(codec, FRAMES))
    left = [pair[0] for pair in pairs_of(codec)][3:]
    high = AMPLITUDE << (WORD_BITS - 16)
    check(set(left) == {high, -high}, f"{set(left)}")
    edges = [i for i in range(1, len(left)) if left[i] != left[i - 1]]
    gaps = {b - a for a, b in itertools.pairwise(edges)}
    check(gaps == {HALF}, f"semiciclo {gaps}")

"""Caminho de pixel no formato indexado: paleta de 24 bits."""

import random

import cocotb

from tests.python.unittests.HDMI import scanout_bench as sb
from tests.python.unittests.HDMI.scanout_bench import ScanoutDut

INDEXED_BITS = 8


@cocotb.test()
async def test_indexed_pixels_through_palette(dut: ScanoutDut) -> None:
    """Cada pixel sai pela paleta, alinhado com o controle."""
    rng = random.Random(3)  # noqa: S311
    pixels = [
        [rng.randrange(256) for _ in range(sb.FB_WIDTH)]
        for _ in range(sb.FB_HEIGHT)
    ]
    await sb.run(dut, pixels, INDEXED_BITS, seed=11)

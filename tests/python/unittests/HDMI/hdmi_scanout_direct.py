"""Caminho de pixel no formato direto: RGB565 expandido para 24 bits."""

import random

import cocotb

from tests.python.unittests.HDMI import scanout_bench as sb
from tests.python.unittests.HDMI.scanout_bench import ScanoutDut

DIRECT_BITS = 16


@cocotb.test()
async def test_rgb565_is_expanded(dut: ScanoutDut) -> None:
    """Cada pixel RGB565 sai expandido e alinhado com o controle."""
    rng = random.Random(5)  # noqa: S311
    pixels = [
        [rng.randrange(1 << 16) for _ in range(sb.FB_WIDTH)]
        for _ in range(sb.FB_HEIGHT)
    ]
    await sb.run(dut, pixels, DIRECT_BITS, seed=13)

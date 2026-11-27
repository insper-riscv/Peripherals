"""Periférico de vídeo completo com ampliação vertical racional."""

import cocotb

from tests.python.unittests.video import bus
from tests.python.unittests.video.raster import capture, check_row
from tests.python.unittests.video.registers import CTRL, FORMAT, INDEXED_FLAG
from tests.python.unittests.video.signals import VideoDut
from tests.python.unittests.video.video import MARGIN, SEED, eq, fill, prepare
from tests.python.utils.check import check
from tests.python.utils.rng import seeded


@cocotb.test()
async def test_format_register_reports_ratio(dut: VideoDut) -> None:
    """O registrador de formato traz num (28:25) e den (31:29)."""
    geo, _, _ = await prepare(dut)
    fmt = await bus.read(dut, FORMAT)
    eq((fmt >> 25) & 0xF, geo.v_num, "numerador")
    eq(fmt >> 29, geo.v_den, "denominador")
    check(geo.v_num != 0, "o teste exige a razão não inteira")
    eq((fmt >> 8) & 0xFF, geo.scale, "ampliação horizontal")
    eq(bool(fmt & INDEXED_FLAG), geo.indexed, "formato indexado")


@cocotb.test()
async def test_ratio_image_against_model(dut: VideoDut) -> None:
    """Cada pixel da imagem inteira, por linha, contra o modelo."""
    geo, model, _ = await prepare(dut)
    rng = seeded(SEED)
    await fill(dut, model, lambda _: rng.getrandbits(32))
    await bus.write(dut, CTRL, 1)
    count = geo.image_height + 2 * MARGIN
    first = geo.y_off - MARGIN
    rows = await capture(dut, first, count)
    for offset, row in enumerate(rows):
        check_row(model, (first + offset) % geo.mode.v_total, row)
    sources = [geo.source_row(n) for n in range(geo.image_height)]
    check(sources[0] == 0 and sources[-1] == geo.fb_height - 1, "extremos")

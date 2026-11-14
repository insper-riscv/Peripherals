"""Conversão de cor: RGB565, luminância e empacotamento."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.TV.bt656 import to_rgb565
from tests.python.utils.check import check
from tests.python.utils.dut import TvColorDut
from tests.python.utils.rng import seeded

SEED = 0xC01
LATENCY = 2
RANDOM_PIXELS = 3000
EDGES = (0, 1, 15, 16, 17, 100, 127, 128, 129, 200, 235, 240, 254, 255)


async def run(
    dut: TvColorDut, pixels: list[tuple[int, int, int, int, int]]
) -> list[tuple[int, int, int]]:
    """Envie um pixel por ciclo e colete as saídas, com a latência.

    Parameters
    ----------
    dut : TvColorDut
        Projeto sob teste.
    pixels : list[tuple[int, int, int, int, int]]
        Índice, formato, Y, Cb e Cr de cada pixel.

    Returns
    -------
    list[tuple[int, int, int]]
        Habilitação de bytes, endereço de palavra e palavra de cada
        pixel, na ordem de envio.
    """
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_we.value = 0
    await RisingEdge(dut.i_clk)
    out: list[tuple[int, int, int]] = []
    for step in range(len(pixels) + LATENCY):
        if step < len(pixels):
            index, fmt, luma, cb, cr = pixels[step]
            dut.i_we.value = 1
            dut.i_index.value = index
            dut.i_format.value = fmt
            dut.i_y.value = luma
            dut.i_cb.value = cb
            dut.i_cr.value = cr
        else:
            dut.i_we.value = 0
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if step >= LATENCY - 1:
            out.append(
                (
                    int(dut.o_we.value),
                    int(dut.o_waddr.value),
                    int(dut.o_wdata.value),
                )
            )
    return out[: len(pixels)]


def pixel_list(count: int, fmt: int) -> list[tuple[int, int, int, int, int]]:
    """Monte pixels com extremos das componentes e outros ao acaso.

    Parameters
    ----------
    count : int
        Número de pixels ao acaso.
    fmt : int
        Formato dos pixels.

    Returns
    -------
    list[tuple[int, int, int, int, int]]
        Índice, formato, Y, Cb e Cr.
    """
    rng = seeded(SEED + fmt)
    pixels = [
        (len(EDGES) * i + j, fmt, y, cb, cr)
        for i, y in enumerate(EDGES)
        for j, (cb, cr) in enumerate(zip(EDGES, reversed(EDGES), strict=True))
    ]
    pixels += [
        (
            rng.randrange(1 << 15),
            fmt,
            rng.randrange(256),
            rng.randrange(256),
            rng.randrange(256),
        )
        for _ in range(count)
    ]
    return pixels


@cocotb.test()
async def test_rgb565(dut: TvColorDut) -> None:
    """RGB565 igual ao modelo, dois pixels por palavra."""
    pixels = pixel_list(RANDOM_PIXELS, 0)
    got = await run(dut, pixels)
    check(len(got) == len(pixels), "faltam saídas")
    for (index, _, luma, cb, cr), (mask, addr, data) in zip(
        pixels, got, strict=True
    ):
        rgb = to_rgb565(luma, cb, cr)
        want_mask = 0b1100 if index & 1 else 0b0011
        check(mask == want_mask, f"máscara {mask:#x} no índice {index}")
        check(addr == index >> 1, f"endereço {addr} no índice {index}")
        check(data == rgb << 16 | rgb, f"dado {data:#x}: Y{luma} {cb} {cr}")


@cocotb.test()
async def test_luma(dut: TvColorDut) -> None:
    """Luminância de 8 bits, quatro pixels por palavra."""
    pixels = pixel_list(RANDOM_PIXELS, 1)
    got = await run(dut, pixels)
    for (index, _, luma, _, _), (mask, addr, data) in zip(
        pixels, got, strict=True
    ):
        check(mask == 1 << (index & 3), f"máscara {mask:#x} no {index}")
        check(addr == index >> 2, f"endereço {addr} no índice {index}")
        check(data == luma * 0x01010101, f"dado {data:#x} com Y {luma}")


@cocotb.test()
async def test_no_write_without_enable(dut: TvColorDut) -> None:
    """Sem i_we nenhuma faixa é habilitada."""
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_we.value = 0
    dut.i_index.value = 5
    dut.i_format.value = 0
    dut.i_y.value = 100
    dut.i_cb.value = 100
    dut.i_cr.value = 100
    for _ in range(6):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        check(int(dut.o_we.value) == 0)

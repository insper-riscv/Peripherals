"""Gerador de temporização: sincronismos, imagem e coordenadas."""

import cocotb
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge
from cocotb.utils import get_sim_time

from tests.python.unittests.video.registers import (
    H_SYNC,
    H_TOTAL,
    H_VISIBLE,
    HS_BEGIN,
    V_SYNC,
    V_TOTAL,
    V_VISIBLE,
    VS_BEGIN,
)
from tests.python.unittests.video.signals import TimingDut
from tests.python.utils.bus import hold_reset
from tests.python.utils.check import check

PERIOD_NS = 10
EXTRA_LINES = (0, 1, 479, 480, 481, 489, 490, 491, 492, 493, 524)


def fb_lines(dut: TimingDut) -> list[int]:
    """Linhas da tela a examinar: bordas e miolo da imagem.

    Parameters
    ----------
    dut : TimingDut
        Gerador sob teste.

    Returns
    -------
    list[int]
        Números de linha em ordem crescente.
    """
    scale = int(dut.scale.value)
    height = int(dut.fb_height.value) * scale
    first = (V_VISIBLE - height) // 2
    around = [first + n for n in range(-1, scale + 2)]
    around += [first + height // 2, first + height - 1, first + height]
    return sorted({n for n in around + list(EXTRA_LINES) if 0 <= n < V_TOTAL})


def expected_coordinate(
    count: int, scale: int, visible: int, position: int
) -> int | None:
    """Coordenada do framebuffer esperada para uma posição da tela.

    Parameters
    ----------
    count : int
        Pixels do framebuffer na direção.
    scale : int
        Fator de ampliação.
    visible : int
        Pixels visíveis da tela na direção.
    position : int
        Coluna ou linha da tela.

    Returns
    -------
    int | None
        A coordenada do framebuffer, ou None fora da imagem.
    """
    size = count * scale
    first = (visible - size) // 2
    if first <= position < first + size:
        return (position - first) // scale
    return None


async def start(dut: TimingDut) -> None:
    """Inicia o clock e solta o reset; a amostra 0 é a coluna 0.

    Parameters
    ----------
    dut : TimingDut
        Gerador sob teste.
    """
    await hold_reset(dut, 3, PERIOD_NS)
    await FallingEdge(dut.i_clk)


def check_sample(
    dut: TimingDut, line: int, column: int, vsync_line: int
) -> None:
    """Confere todas as saídas em uma amostra.

    Parameters
    ----------
    dut : TimingDut
        Gerador sob teste.
    line : int
        Linha da tela.
    column : int
        Coluna da tela.
    vsync_line : int
        Linha que o_vsync e o_vblank, registradas, mostram.
    """
    where = f"linha {line} coluna {column}"
    hs_low = HS_BEGIN <= column < HS_BEGIN + H_SYNC
    vs_low = VS_BEGIN <= line < VS_BEGIN + V_SYNC
    check(int(dut.o_hs.value) == (0 if hs_low else 1), f"HS em {where}")
    check(int(dut.o_vs.value) == (0 if vs_low else 1), f"VS em {where}")
    scale = int(dut.scale.value)
    x = expected_coordinate(int(dut.fb_width.value), scale, H_VISIBLE, column)
    y = expected_coordinate(int(dut.fb_height.value), scale, V_VISIBLE, line)
    inside = x is not None and y is not None
    check(int(dut.o_image.value) == int(inside), f"imagem em {where}")
    check(int(dut.o_fb_x.value) < int(dut.fb_width.value), f"x em {where}")
    check(int(dut.o_fb_y.value) < int(dut.fb_height.value), f"y em {where}")
    if inside:
        check(int(dut.o_fb_x.value) == x, f"fb_x em {where}")
        check(int(dut.o_fb_y.value) == y, f"fb_y em {where}")
    sync = VS_BEGIN <= vsync_line < VS_BEGIN + V_SYNC
    check(int(dut.o_vsync.value) == int(sync), f"vsync em {where}")
    blank = vsync_line >= V_VISIBLE
    check(int(dut.o_vblank.value) == int(blank), f"vblank em {where}")


async def check_line(dut: TimingDut, line: int) -> None:
    """Confira as amostras de todas as colunas de uma linha.

    Parameters
    ----------
    dut : TimingDut
        Projeto sob teste.
    line : int
        Linha da varredura.
    """
    for column in range(H_TOTAL):
        previous = line if column else (line - 1) % V_TOTAL
        # As saídas registradas mostram a linha da amostra anterior.
        check_sample(dut, line, column, previous if line or column else 0)
        await FallingEdge(dut.i_clk)


@cocotb.test()
async def test_selected_lines(dut: TimingDut) -> None:
    """Sincronismos, imagem e coordenadas em linhas escolhidas."""
    await start(dut)
    cycle = 0
    for line in fb_lines(dut):
        target = line * H_TOTAL
        if target > cycle:
            await ClockCycles(dut.i_clk, target - cycle, rising=False)
            cycle = target
        await check_line(dut, line)
        cycle += H_TOTAL


@cocotb.test()
async def test_frame_length(dut: TimingDut) -> None:
    """O quadro dura 800 x 525 ciclos de pixel entre dois VS."""
    await start(dut)
    await FallingEdge(dut.o_vs)
    first = get_sim_time("ns")
    await RisingEdge(dut.o_vs)
    low = get_sim_time("ns") - first
    check(round(low / PERIOD_NS) == V_SYNC * H_TOTAL, "largura do VS")
    await FallingEdge(dut.o_vs)
    frame = get_sim_time("ns") - first
    check(round(frame / PERIOD_NS) == V_TOTAL * H_TOTAL, "período do VS")

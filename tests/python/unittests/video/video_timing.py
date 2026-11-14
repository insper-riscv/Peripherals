"""Gerador de temporização: sincronismos, imagem e coordenadas."""

import cocotb
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge
from cocotb.utils import get_sim_time

from tests.python.unittests.video.registers import Mode, read_mode
from tests.python.unittests.video.signals import TimingDut
from tests.python.utils.bus import hold_reset
from tests.python.utils.check import check

PERIOD_NS = 10


def extra_lines(mode: Mode) -> tuple[int, ...]:
    """Linhas de interesse: bordas da área visível e do sincronismo.

    Parameters
    ----------
    mode : Mode
        Temporização do modo.

    Returns
    -------
    tuple[int, ...]
        Números de linha ao redor das transições do quadro.
    """
    begin = mode.vs_begin
    return (
        0,
        1,
        mode.v_visible - 1,
        mode.v_visible,
        mode.v_visible + 1,
        begin - 1,
        begin,
        begin + 1,
        begin + mode.v_sync - 1,
        begin + mode.v_sync,
        mode.v_total - 1,
    )


def fb_lines(dut: TimingDut, mode: Mode) -> list[int]:
    """Linhas da tela a examinar: bordas e miolo da imagem.

    Parameters
    ----------
    dut : TimingDut
        Gerador sob teste.
    mode : Mode
        Temporização do modo.

    Returns
    -------
    list[int]
        Números de linha em ordem crescente.
    """
    scale = int(dut.scale.value)
    height = int(dut.fb_height.value) * scale
    first = (mode.v_visible - height) // 2
    around = [first + n for n in range(-1, scale + 2)]
    around += [first + height // 2, first + height - 1, first + height]
    lines = {n for n in around + list(extra_lines(mode)) if n >= 0}
    return sorted(n for n in lines if n < mode.v_total)


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
    dut: TimingDut, mode: Mode, line: int, column: int, vsync_line: int
) -> None:
    """Confere todas as saídas em uma amostra.

    Parameters
    ----------
    dut : TimingDut
        Gerador sob teste.
    mode : Mode
        Temporização do modo.
    line : int
        Linha da tela.
    column : int
        Coluna da tela.
    vsync_line : int
        Linha que o_vsync e o_vblank, registradas, mostram.
    """
    where = f"linha {line} coluna {column}"
    check(int(dut.o_hs.value) == mode.hs_level(column), f"HS em {where}")
    check(int(dut.o_vs.value) == mode.vs_level(line), f"VS em {where}")
    check(
        int(dut.o_visible.value) == int(mode.visible(column, line)),
        f"área visível em {where}",
    )
    scale = int(dut.scale.value)
    x = expected_coordinate(
        int(dut.fb_width.value), scale, mode.h_visible, column
    )
    y = expected_coordinate(
        int(dut.fb_height.value), scale, mode.v_visible, line
    )
    inside = x is not None and y is not None
    check(int(dut.o_image.value) == int(inside), f"imagem em {where}")
    check(int(dut.o_fb_x.value) < int(dut.fb_width.value), f"x em {where}")
    check(int(dut.o_fb_y.value) < int(dut.fb_height.value), f"y em {where}")
    if inside:
        check(int(dut.o_fb_x.value) == x, f"fb_x em {where}")
        check(int(dut.o_fb_y.value) == y, f"fb_y em {where}")
    sync = mode.vs_begin <= vsync_line < mode.vs_begin + mode.v_sync
    check(int(dut.o_vsync.value) == int(sync), f"vsync em {where}")
    blank = vsync_line >= mode.v_visible
    check(int(dut.o_vblank.value) == int(blank), f"vblank em {where}")


async def check_line(dut: TimingDut, mode: Mode, line: int) -> None:
    """Confira as amostras de todas as colunas de uma linha.

    Parameters
    ----------
    dut : TimingDut
        Projeto sob teste.
    mode : Mode
        Temporização do modo.
    line : int
        Linha da varredura.
    """
    for column in range(mode.h_total):
        previous = line if column else (line - 1) % mode.v_total
        # As saídas registradas mostram a linha da amostra anterior.
        check_sample(
            dut, mode, line, column, previous if line or column else 0
        )
        await FallingEdge(dut.i_clk)


@cocotb.test()
async def test_selected_lines(dut: TimingDut) -> None:
    """Sincronismos, imagem e coordenadas em linhas escolhidas."""
    mode = read_mode(dut)
    await start(dut)
    cycle = 0
    for line in fb_lines(dut, mode):
        target = line * mode.h_total
        if target > cycle:
            await ClockCycles(dut.i_clk, target - cycle, rising=False)
            cycle = target
        await check_line(dut, mode, line)
        cycle += mode.h_total


@cocotb.test()
async def test_frame_length(dut: TimingDut) -> None:
    """O quadro dura h_total x v_total ciclos de pixel entre dois VS."""
    mode = read_mode(dut)
    first_edge, second_edge = (
        (RisingEdge, FallingEdge)
        if mode.v_positive
        else (FallingEdge, RisingEdge)
    )
    await start(dut)
    await first_edge(dut.o_vs)
    first = get_sim_time("ns")
    await second_edge(dut.o_vs)
    width = get_sim_time("ns") - first
    check(
        round(width / PERIOD_NS) == mode.v_sync * mode.h_total,
        "largura do VS",
    )
    await first_edge(dut.o_vs)
    frame = get_sim_time("ns") - first
    check(
        round(frame / PERIOD_NS) == mode.v_total * mode.h_total,
        "período do VS",
    )

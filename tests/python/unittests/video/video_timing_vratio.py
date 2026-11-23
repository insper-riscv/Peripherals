"""Temporização com ampliação vertical racional (num / den)."""

from typing import Protocol

import cocotb
from cocotb.handle import LogicArrayObject
from cocotb.triggers import ClockCycles

from tests.python.unittests.video.registers import Mode, read_mode
from tests.python.unittests.video.signals import TimingDut
from tests.python.unittests.video.video_timing import start
from tests.python.utils.check import check

# Repetição esperada das linhas de origem em 12 / 5 (média 2,4).
PATTERN_12_5 = [3, 2, 3, 2, 2]
FRAMES = 2


class RatioDut(TimingDut, Protocol):
    """Gerador de temporização com os generics da razão vertical."""

    v_scale_num: LogicArrayObject
    v_scale_den: LogicArrayObject


def ratio(dut: RatioDut) -> tuple[int, int]:
    """Razão vertical efetiva (numerador, denominador).

    Parameters
    ----------
    dut : RatioDut
        Gerador sob teste.

    Returns
    -------
    tuple[int, int]
        scale / 1 quando v_scale_num vale 0 (ampliação inteira).
    """
    num = int(dut.v_scale_num.value)
    if num == 0:
        return int(dut.scale.value), 1
    return num, int(dut.v_scale_den.value)


def expected_row(dut: RatioDut, mode: Mode, line: int) -> int | None:
    """Linha de origem esperada para uma linha da tela.

    Parameters
    ----------
    dut : RatioDut
        Gerador sob teste.
    mode : Mode
        Temporização do modo.
    line : int
        Linha da tela.

    Returns
    -------
    int | None
        floor(n * den / num), com n a linha da imagem, ou None fora
        da imagem.
    """
    num, den = ratio(dut)
    height = -(-int(dut.fb_height.value) * num // den)
    first = (mode.v_visible - height) // 2
    if first <= line < first + height:
        return (line - first) * den // num
    return None


async def sample_rows(
    dut: RatioDut, mode: Mode, frames: int
) -> list[tuple[int, int, int]]:
    """Amostra uma coluna de cada linha, durante alguns quadros.

    Parameters
    ----------
    dut : RatioDut
        Gerador sob teste.
    mode : Mode
        Temporização do modo.
    frames : int
        Quadros a amostrar.

    Returns
    -------
    list[tuple[int, int, int]]
        Para cada linha da tela, (linha, o_image, o_fb_y) na coluna 1 da
        imagem.
    """
    x_off = (
        mode.h_visible - int(dut.fb_width.value) * int(dut.scale.value)
    ) // 2
    column = x_off + 1
    rows: list[tuple[int, int, int]] = []
    await ClockCycles(dut.i_clk, column, rising=False)
    for line in range(frames * mode.v_total):
        rows.append(
            (
                line % mode.v_total,
                int(dut.o_image.value),
                int(dut.o_fb_y.value),
            )
        )
        await ClockCycles(dut.i_clk, mode.h_total, rising=False)
    return rows


def runs(values: list[int]) -> list[int]:
    """Comprimentos das sequências de valores iguais consecutivos.

    Parameters
    ----------
    values : list[int]
        Sequência de linhas de origem.

    Returns
    -------
    list[int]
        Quantas vezes cada valor consecutivo se repete.
    """
    out: list[int] = []
    for index, value in enumerate(values):
        if index and value == values[index - 1]:
            out[-1] += 1
        else:
            out.append(1)
    return out


@cocotb.test()
async def test_source_row_per_line(dut: RatioDut) -> None:
    """A linha de origem de cada linha é floor(n * den / num)."""
    mode = read_mode(dut)
    await start(dut)
    rows = await sample_rows(dut, mode, FRAMES)
    for line, image, fb_y in rows:
        want = expected_row(dut, mode, line)
        check(image == int(want is not None), f"o_image na linha {line}")
        if want is not None:
            check(fb_y == want, f"fb_y na linha {line}: {fb_y} != {want}")
        check(fb_y < int(dut.fb_height.value), f"fb_y no limite, linha {line}")


@cocotb.test()
async def test_image_lines_and_repeat_pattern(dut: RatioDut) -> None:
    """Linhas exibidas por quadro e padrão de repetição das linhas."""
    mode = read_mode(dut)
    await start(dut)
    rows = await sample_rows(dut, mode, FRAMES)
    num, den = ratio(dut)
    fb_height = int(dut.fb_height.value)
    height = -(-fb_height * num // den)
    for frame in range(FRAMES):
        first = frame * mode.v_total
        last = first + mode.v_total
        lines = rows[first:last]
        shown = [fb_y for _, image, fb_y in lines if image]
        check(
            len(shown) == height, f"linhas exibidas: {len(shown)} != {height}"
        )
        check(shown[0] == 0, "começa na linha de origem 0")
        check(shown[-1] == fb_height - 1, "termina na última linha de origem")
        counts = runs(shown)
        check(sum(counts) == height, "soma das repetições")
        check(
            all(c in (num // den, -(-num // den)) for c in counts),
            f"repetições {counts} só de piso e teto de {num}/{den}",
        )
        if (num, den) == (12, 5):
            want = (PATTERN_12_5 * fb_height)[:fb_height]
            check(counts == want, f"padrão 3,2,3,2,2: {counts} != {want}")
        if (num, den) == (int(dut.scale.value), 1):
            check(set(counts) == {num}, "ampliação inteira: todas iguais")
        # O quadro seguinte repete o desenho (o acumulador reinicia).
        if frame:
            first = [fb_y for _, image, fb_y in rows[: mode.v_total] if image]
            check(shown == first, "quadros idênticos")

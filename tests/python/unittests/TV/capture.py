"""Controle da captura: decimação, campos, abortos e posição."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import TvCaptureDut

WIDTH = 4
HEIGHT = 3
SRC_WIDTH = 8
SRC_HEIGHT = 6
FIELD_LINES = SRC_HEIGHT // 2
GAP = 4


class Recorder:
    """Guarda os pixels aceitos e os pulsos de fim."""

    def __init__(self) -> None:
        """Zere os registros."""
        self.pixels: dict[int, int] = {}
        self.done: list[int] = []

    async def run(self, dut: TvCaptureDut) -> None:
        """Amostre as saídas depois de cada borda.

        Parameters
        ----------
        dut : TvCaptureDut
            Projeto sob teste.
        """
        while True:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            if int(dut.o_we.value):
                self.pixels[int(dut.o_index.value)] = int(dut.o_y.value)
            if int(dut.o_done.value):
                self.done.append(int(dut.o_ok.value))


async def start(
    dut: TvCaptureDut, x_div: int, y_div: int, sel: int
) -> Recorder:
    """Reinicie, escolha a configuração e peça a captura.

    Parameters
    ----------
    dut : TvCaptureDut
        Projeto sob teste.
    x_div : int
        Fator em x.
    y_div : int
        Fator em y.
    sel : int
        Seletor de campo.

    Returns
    -------
    Recorder
        Registro dos pixels e dos fins.
    """
    for name in ("i_start", "i_line_start", "i_field_start", "i_field_end"):
        getattr(dut, name).value = 0
    dut.i_pix_valid.value = 0
    dut.i_field.value = 0
    dut.i_present.value = 1
    dut.i_x_div.value = x_div
    dut.i_y_div.value = y_div
    dut.i_field_sel.value = sel
    dut.i_format.value = 0
    dut.i_y.value = 0
    dut.i_cb.value = 0
    dut.i_cr.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst.value = 1
    await bus.cycles(dut, 3)
    dut.i_rst.value = 0
    recorder = Recorder()
    cocotb.start_soon(recorder.run(dut))
    await pulse(dut, "i_start")
    return recorder


async def pulse(dut: TvCaptureDut, *names: str) -> None:
    """Levante sinais por um ciclo.

    Parameters
    ----------
    dut : TvCaptureDut
        Projeto sob teste.
    *names : str
        Nomes dos sinais.
    """
    for name in names:
        getattr(dut, name).value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    for name in names:
        getattr(dut, name).value = 0


def marker(row: int, col: int) -> int:
    """Valor de Y do pixel de coluna col da linha row do quadro.

    Parameters
    ----------
    row : int
        Linha do quadro.
    col : int
        Coluna de origem.

    Returns
    -------
    int
        Valor distinto por posição.
    """
    return 16 * row + col + 1


async def field(
    dut: TvCaptureDut, number: int, lines: int = FIELD_LINES, both: bool = True
) -> None:
    """Envie um campo: linhas ativas com pixels e o fim.

    Parameters
    ----------
    dut : TvCaptureDut
        Projeto sob teste.
    number : int
        Campo, 0 ou 1.
    lines : int
        Linhas ativas do campo.
    both : bool
        Verdadeiro se a linha do quadro é 2n + F, falso se é n.
    """
    dut.i_field.value = number
    for n in range(lines):
        names = (
            ("i_line_start", "i_field_start") if n == 0 else ("i_line_start",)
        )
        await pulse(dut, *names)
        await bus.cycles(dut, GAP)
        row = 2 * n + number if both else n
        for col in range(SRC_WIDTH + 3):
            dut.i_y.value = marker(row, col) & 0xFF
            await pulse(dut, "i_pix_valid")
        await bus.cycles(dut, GAP)
    await pulse(dut, "i_field_end")
    await bus.cycles(dut, GAP)


@cocotb.test()
async def test_both_fields(dut: TvCaptureDut) -> None:
    """Dois campos, fator 2 em x: o quadro é entrelaçado e cortado."""
    rec = await start(dut, 2, 1, 0)
    check_equal(int(dut.o_busy.value), 1)
    await field(dut, 0)
    check_equal(int(dut.o_busy.value), 1)
    await field(dut, 1)
    await bus.cycles(dut, 2)
    check(rec.done == [1], f"fim {rec.done}")
    check_equal(int(dut.o_busy.value), 0)
    want = {
        row * WIDTH + col: marker(row, 2 * col)
        for row in range(HEIGHT)
        for col in range(WIDTH)
    }
    check(rec.pixels == want, f"{rec.pixels} != {want}")


@cocotb.test()
async def test_second_field_only(dut: TvCaptureDut) -> None:
    """Só o segundo campo, fator 2 em y: linhas 0 e 2 do campo."""
    rec = await start(dut, 1, 2, 2)
    await field(dut, 0, both=False)
    check_equal(int(dut.o_busy.value), 1)
    check(not rec.pixels, "o primeiro campo foi gravado")
    await field(dut, 1, both=False)
    await bus.cycles(dut, 2)
    check(rec.done == [1], f"fim {rec.done}")
    want = {
        row * WIDTH + col: marker(2 * row, col)
        for row in range(2)
        for col in range(WIDTH)
    }
    check(rec.pixels == want, f"{rec.pixels} != {want}")


@cocotb.test()
async def test_abort_without_video(dut: TvCaptureDut) -> None:
    """Se o vídeo some a captura termina sem quadro completo."""
    rec = await start(dut, 1, 1, 0)
    await field(dut, 0, lines=1)
    dut.i_present.value = 0
    await bus.cycles(dut, 3)
    check(rec.done == [0], f"fim {rec.done}")
    check_equal(int(dut.o_busy.value), 0)


@cocotb.test()
async def test_abort_out_of_order(dut: TvCaptureDut) -> None:
    """Um segundo início de campo com o mesmo F aborta a captura."""
    rec = await start(dut, 1, 1, 0)
    await field(dut, 0)
    await pulse(dut, "i_line_start", "i_field_start")
    await bus.cycles(dut, 3)
    check(rec.done == [0], f"fim {rec.done}")


@cocotb.test()
async def test_field_end_without_start(dut: TvCaptureDut) -> None:
    """Um fim de campo sem início não completa o quadro."""
    rec = await start(dut, 1, 1, 1)
    await pulse(dut, "i_field_end")
    await bus.cycles(dut, 3)
    check_equal(len(rec.done), 0)
    check_equal(int(dut.o_busy.value), 1)
    await field(dut, 0, both=False)
    await bus.cycles(dut, 2)
    check(rec.done == [1], f"fim {rec.done}")


@cocotb.test()
async def test_wrong_field_is_ignored(dut: TvCaptureDut) -> None:
    """Pedir o primeiro campo ignora o segundo e espera o primeiro."""
    rec = await start(dut, 1, 1, 1)
    await field(dut, 1, both=False)
    check_equal(len(rec.done), 0)
    check(not rec.pixels)
    await field(dut, 0, both=False)
    await bus.cycles(dut, 2)
    check(rec.done == [1], f"fim {rec.done}")

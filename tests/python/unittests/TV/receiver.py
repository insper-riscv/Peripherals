"""Receptor BT.656: códigos, pixels, campos e erros de sincronismo."""

import cocotb
from cocotb.task import Task
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.TV.bt656 import (
    BLANK_FILL,
    PREFIX,
    timing_word,
)
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import TvRxDut

PRESENT_CYCLES = 64
PIXELS = 8
PIXEL_MAX = 255


class Probe:
    """Coleta os eventos e os pixels do receptor a cada ciclo."""

    def __init__(self) -> None:
        """Zere as contagens."""
        self.line_starts = 0
        self.field_starts = 0
        self.field_ends = 0
        self.errors = 0
        self.pixels: list[tuple[int, int, int]] = []
        self.fields: list[int] = []

    async def run(self, dut: TvRxDut) -> None:
        """Amostre as saídas depois de cada borda de subida.

        Parameters
        ----------
        dut : TvRxDut
            Projeto sob teste.
        """
        while True:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            self.line_starts += int(dut.o_line_start.value)
            self.field_starts += int(dut.o_field_start.value)
            self.field_ends += int(dut.o_field_end.value)
            self.errors += int(dut.o_error.value)
            if int(dut.o_field_start.value):
                self.fields.append(int(dut.o_field.value))
            if int(dut.o_pix_valid.value):
                self.pixels.append(
                    (
                        int(dut.o_y.value),
                        int(dut.o_cb.value),
                        int(dut.o_cr.value),
                    )
                )


def line(field: int, vblank: int, data: bytes, flip: int = 0) -> bytes:
    """Monte SAV, dados, EAV e um apagamento curto.

    Parameters
    ----------
    field : int
        Campo da linha.
    vblank : int
        Apagamento vertical.
    data : bytes
        Bytes entre o SAV e o EAV.
    flip : int
        Bits trocados na palavra XY do SAV.

    Returns
    -------
    bytes
        Os bytes da linha.
    """
    sav = timing_word(field, vblank, 0) ^ flip
    eav = timing_word(field, vblank, 1)
    blank = bytes(BLANK_FILL[i % 2] for i in range(12))
    return bytes((*PREFIX, sav)) + data + bytes((*PREFIX, eav)) + blank


def payload(seed: int, groups: int = PIXELS // 2) -> bytes:
    """Gere grupos Cb Y Cr Y com valores fora de 0 e de 255.

    Parameters
    ----------
    seed : int
        Semente dos valores.
    groups : int
        Número de grupos de quatro bytes.

    Returns
    -------
    bytes
        Os bytes de vídeo.
    """
    return bytes(1 + (seed * 37 + 11 * i) % 253 for i in range(4 * groups))


def expect_pixels(data: bytes) -> list[tuple[int, int, int]]:
    """Devolva os pixels (Y, Cb, Cr) dos bytes.

    Parameters
    ----------
    data : bytes
        Os bytes de vídeo.

    Returns
    -------
    list[tuple[int, int, int]]
        Dois pixels por grupo, com a crominância repetida.
    """
    out: list[tuple[int, int, int]] = []
    for i in range(0, len(data), 4):
        cb, y0, cr, y1 = data[i:][:4]
        out += [(y0, cb, cr), (y1, cb, cr)]
    return out


async def start(dut: TvRxDut) -> tuple[Probe, Task[None]]:
    """Inicie o clock, solte o reset e comece a coleta.

    Parameters
    ----------
    dut : TvRxDut
        Projeto sob teste.

    Returns
    -------
    tuple[Probe, Task[None]]
        A coleta e a tarefa que a executa.
    """
    dut.i_data.value = BLANK_FILL[0]
    await bus.hold_reset(dut)
    probe = Probe()
    return probe, cocotb.start_soon(probe.run(dut))


async def send(dut: TvRxDut, data: bytes) -> None:
    """Envie os bytes, um por ciclo.

    Parameters
    ----------
    dut : TvRxDut
        Projeto sob teste.
    data : bytes
        Bytes enviados.
    """
    for byte in data:
        dut.i_data.value = byte
        await RisingEdge(dut.i_clk)
    dut.i_data.value = BLANK_FILL[0]
    for _ in range(8):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


@cocotb.test()
async def test_field_and_pixels(dut: TvRxDut) -> None:
    """Um campo de três linhas ativas dá pixels, um início e um fim."""
    probe, _ = await start(dut)
    rows = [payload(seed) for seed in (1, 2, 3)]
    stream = line(0, 1, bytes(8)) * 2
    stream += b"".join(line(0, 0, row) for row in rows)
    stream += line(0, 1, bytes(8))
    await send(dut, stream)
    check_equal(probe.line_starts, 3)
    check_equal(probe.field_starts, 1)
    check_equal(probe.field_ends, 1)
    check_equal(probe.errors, 0)
    check(probe.fields == [0])
    want = [p for row in rows for p in expect_pixels(row)]
    check(probe.pixels == want, "pixels diferentes dos bytes enviados")
    check_equal(int(dut.o_present.value), 1)


@cocotb.test()
async def test_second_field(dut: TvRxDut) -> None:
    """Um segundo campo é visto com F igual a 1."""
    probe, _ = await start(dut)
    stream = line(0, 1, bytes(8)) + line(0, 0, payload(4))
    stream += line(0, 1, bytes(8)) + line(1, 1, bytes(8))
    stream += line(1, 0, payload(5)) + line(1, 1, bytes(8))
    await send(dut, stream)
    check_equal(probe.field_starts, 2)
    check_equal(probe.field_ends, 2)
    check(probe.fields == [0, 1])
    check_equal(probe.errors, 0)


@cocotb.test()
async def test_prefix_is_not_data(dut: TvRxDut) -> None:
    """Nenhum byte do prefixo FF 00 00 vira pixel, nem antes do EAV."""
    probe, _ = await start(dut)
    stream = line(0, 1, bytes(8)) + line(0, 0, payload(7, 10))
    stream += line(0, 1, bytes(8))
    await send(dut, stream)
    check_equal(len(probe.pixels), 20)
    check(all(0 < v < PIXEL_MAX for p in probe.pixels for v in p))


@cocotb.test()
async def test_protection_error(dut: TvRxDut) -> None:
    """Uma palavra XY com proteção errada é erro e a linha some."""
    probe, _ = await start(dut)
    stream = line(0, 1, bytes(8))
    stream += line(0, 0, payload(1), flip=0b0010)
    stream += line(0, 0, payload(2))
    await send(dut, stream)
    check(probe.errors >= 1, "o erro não foi sinalizado")
    check_equal(probe.line_starts, 1)


@cocotb.test()
async def test_misaligned_line(dut: TvRxDut) -> None:
    """Uma linha de bytes não múltipla de 4 é erro."""
    probe, _ = await start(dut)
    stream = line(0, 1, bytes(8)) + line(0, 0, payload(3)[:-1])
    await send(dut, stream)
    check_equal(probe.errors, 1)


@cocotb.test()
async def test_sav_without_eav(dut: TvRxDut) -> None:
    """Um SAV dentro de uma linha aberta é erro."""
    probe, _ = await start(dut)
    sav = bytes((*PREFIX, timing_word(0, 1, 0)))
    await send(dut, sav + bytes(8) + sav + bytes(8))
    check_equal(probe.errors, 1)


@cocotb.test()
async def test_present_times_out(dut: TvRxDut) -> None:
    """Sem códigos o vídeo some depois de present_cycles ciclos."""
    _, _ = await start(dut)
    check_equal(int(dut.o_present.value), 0)
    await send(dut, line(0, 1, bytes(8)))
    check_equal(int(dut.o_present.value), 1)
    for _ in range(PRESENT_CYCLES + 4):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    check_equal(int(dut.o_present.value), 0)

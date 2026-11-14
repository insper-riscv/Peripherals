"""Captura de TV: fluxo NTSC BT.656, formatos, decimação e erros."""

import cocotb
from cocotb.clock import Clock
from cocotb.task import Task
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.TV import bt656
from tests.python.unittests.TV.registers import (
    BUSY,
    CTRL,
    DECIMATION,
    DECODER_RUN,
    ERROR,
    ERROR_IRQ,
    FIELD_BOTH,
    FIELD_FIRST,
    FIELD_SECOND,
    FORMAT,
    FORMAT_LUMA,
    FORMAT_RGB565,
    FRAME_COUNT,
    FRAME_IRQ,
    GEOMETRY,
    PRESENT,
    RD_ADDR,
    RD_DATA,
    READY,
    SOURCE,
    START,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import TvDut

SYS_NS = 20
TD_NS = 37
FB_WIDTH = 180
FB_HEIGHT = 120
WORDS = FB_WIDTH * FB_HEIGHT // 2
POLL_US = 200
TIMEOUT_US = 200_000
FRAME = bt656.frame_bytes()
MIN_PIXELS = 1000


async def stream(dut: TvDut, data: bytes) -> None:
    """Envie o fluxo em laço, um byte por ciclo de TD_CLK27.

    Parameters
    ----------
    dut : TvDut
        Projeto sob teste.
    data : bytes
        Bytes enviados em ordem e repetidos sem parar.
    """
    index = 0
    size = len(data)
    while True:
        dut.i_td_data.value = data[index]
        index = (index + 1) % size
        await RisingEdge(dut.i_td_clk27)


async def start(dut: TvDut, data: bytes) -> Task[None]:
    """Inicie os clocks, solte o reset e comece o fluxo.

    Parameters
    ----------
    dut : TvDut
        Projeto sob teste.
    data : bytes
        Fluxo BT.656 enviado em laço.

    Returns
    -------
    Task[None]
        A tarefa que envia o fluxo, para ser cancelada.
    """
    dut.i_td_data.value = bt656.BLANK_FILL[0]
    cocotb.start_soon(Clock(dut.i_td_clk27, TD_NS, unit="ns").start())
    await bus.reset(dut, hold=10, period_ns=SYS_NS)
    return cocotb.start_soon(stream(dut, data))


async def wait_status(dut: TvDut, mask: int, value: int) -> int:
    """Leia o estado até os bits de mask valerem value.

    Parameters
    ----------
    dut : TvDut
        Projeto sob teste.
    mask : int
        Bits do estado observados.
    value : int
        Valor esperado desses bits.

    Returns
    -------
    int
        O estado lido quando a condição vale.
    """
    status = 0
    for _ in range(TIMEOUT_US // POLL_US):
        status = await bus.read(dut, STATUS)
        if status & mask == value:
            return status
        await Timer(POLL_US, unit="us")
    raise AssertionError(
        f"estado {status:#x}: {mask:#x} nunca valeu {value:#x}"
    )


async def configure(
    dut: TvDut, divisors: tuple[int, int], fmt: int, field_sel: int
) -> None:
    """Escreva a decimação, o formato e o campo.

    Parameters
    ----------
    dut : TvDut
        Projeto sob teste.
    divisors : tuple[int, int]
        Fatores em x e em y.
    fmt : int
        Formato do pixel.
    field_sel : int
        Campo capturado.
    """
    await bus.write(dut, DECIMATION, divisors[1] << 8 | divisors[0])
    await bus.write(dut, FORMAT, field_sel << 1 | fmt)


async def read_pixels(dut: TvDut, fmt: int) -> dict[int, int]:
    """Leia a memória do quadro inteira e separe os pixels.

    Parameters
    ----------
    dut : TvDut
        Projeto sob teste.
    fmt : int
        Formato do pixel.

    Returns
    -------
    dict[int, int]
        Valor de cada pixel por índice.
    """
    await bus.write(dut, RD_ADDR, 0)
    pixels: dict[int, int] = {}
    per_word = 4 if fmt == FORMAT_LUMA else 2
    bits = 32 // per_word
    for word in range(WORDS):
        value = await bus.read(dut, RD_DATA)
        for lane in range(per_word):
            pixels[word * per_word + lane] = (
                value >> (lane * bits) & (1 << bits) - 1
            )
    return pixels


async def capture_and_compare(
    dut: TvDut,
    divisors: tuple[int, int],
    fmt: int,
    field_sel: int,
    ctrl: int = 0,
) -> None:
    """Capture um quadro e confira todos os pixels gravados.

    Parameters
    ----------
    dut : TvDut
        Projeto sob teste.
    divisors : tuple[int, int]
        Fatores em x e em y.
    fmt : int
        Formato do pixel.
    field_sel : int
        Campo capturado.
    ctrl : int
        Bits de controle escritos junto com o início.
    """
    await configure(dut, divisors, fmt, field_sel)
    await bus.write(dut, CTRL, START | ctrl)
    status = await bus.read(dut, STATUS)
    check(status & BUSY != 0, "a captura não ficou ocupada")
    status = await wait_status(dut, BUSY, 0)
    check(status & READY != 0, "quadro não ficou pronto")
    check_equal(await bus.read(dut, FRAME_COUNT) & 0xFF, 1)
    want = bt656.expected_frame(
        divisors, fmt == FORMAT_LUMA, field_sel, (FB_WIDTH, FB_HEIGHT)
    )
    got = await read_pixels(dut, fmt)
    check(len(want) > MIN_PIXELS, "modelo vazio")
    for index, pixel in want.items():
        check(
            got[index] == pixel,
            f"pixel {index}: {got[index]:#x} != {pixel:#x}",
        )


@cocotb.test()
async def test_reset_values(dut: TvDut) -> None:
    """O reset deixa os valores documentados e a geometria certa."""
    await start(dut, bt656.blank_bytes(2000))
    check_equal(await bus.read(dut, CTRL), 0)
    check_equal(await bus.read(dut, STATUS), 0)
    check_equal(await bus.read(dut, FRAME_COUNT), 0)
    check_equal(await bus.read(dut, DECIMATION), 0x0101)
    check_equal(await bus.read(dut, FORMAT), 0)
    check_equal(await bus.read(dut, GEOMETRY), FB_HEIGHT << 16 | FB_WIDTH)
    check_equal(await bus.read(dut, SOURCE), 480 << 16 | 720)
    check_equal(await bus.read(dut, RD_ADDR), 0)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(int(dut.o_td_reset_n.value), 0)
    await bus.write(dut, CTRL, DECODER_RUN)
    check_equal(int(dut.o_td_reset_n.value), 1)
    check_equal(await bus.read(dut, CTRL), DECODER_RUN)


@cocotb.test()
async def test_no_video_aborts(dut: TvDut) -> None:
    """Sem códigos de temporização a captura aborta com erro."""
    await start(dut, bt656.blank_bytes(2000))
    check(await bus.read(dut, STATUS) & PRESENT == 0)
    await bus.write(dut, CTRL, START | ERROR_IRQ)
    status = await wait_status(dut, BUSY, 0)
    check(status & ERROR != 0, "o abortar não levantou o erro")
    check(status & READY == 0)
    check_equal(await bus.read(dut, FRAME_COUNT), 0)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, STATUS, ERROR)
    check_equal(await bus.read(dut, STATUS) & ERROR, 0)
    check_equal(int(dut.o_irq.value), 0)


@cocotb.test()
async def test_rgb_both_fields(dut: TvDut) -> None:
    """RGB565 dos dois campos, decimado 4x4, com interrupção."""
    await start(dut, FRAME)
    await wait_status(dut, PRESENT, PRESENT)
    await capture_and_compare(
        dut, (4, 4), FORMAT_RGB565, FIELD_BOTH, FRAME_IRQ
    )
    check_equal(int(dut.o_irq.value), 1)
    status = await bus.read(dut, STATUS)
    check_equal(status & ERROR, 0)
    await bus.write(dut, STATUS, READY)
    check_equal(await bus.read(dut, STATUS) & READY, 0)
    check_equal(int(dut.o_irq.value), 0)


@cocotb.test()
async def test_luma_second_field(dut: TvDut) -> None:
    """Luminância do segundo campo, decimada 4x2."""
    await start(dut, FRAME)
    await capture_and_compare(dut, (4, 2), FORMAT_LUMA, FIELD_SECOND)


@cocotb.test()
async def test_clipped_odd_factors(dut: TvDut) -> None:
    """Fatores 3 e 5: colunas além da memória são cortadas."""
    await start(dut, FRAME)
    await capture_and_compare(dut, (3, 5), FORMAT_RGB565, FIELD_BOTH)


@cocotb.test()
async def test_first_field_busy_rules(dut: TvDut) -> None:
    """Em curso, a configuração e um novo início são ignorados."""
    await start(dut, FRAME)
    await configure(dut, (8, 2), FORMAT_LUMA, FIELD_FIRST)
    await bus.write(dut, CTRL, START)
    await bus.write(dut, DECIMATION, 0x0303)
    await bus.write(dut, FORMAT, 0)
    check_equal(await bus.read(dut, DECIMATION), 0x0208)
    check_equal(await bus.read(dut, FORMAT), FIELD_FIRST << 1 | FORMAT_LUMA)
    await bus.write(dut, CTRL, START)
    await wait_status(dut, BUSY, 0)
    check_equal(await bus.read(dut, FRAME_COUNT), 1)
    await Timer(100, unit="us")
    check_equal(await bus.read(dut, STATUS) & BUSY, 0)
    await bus.write(dut, DECIMATION, 0)
    check_equal(await bus.read(dut, DECIMATION), 0x0101)


@cocotb.test()
async def test_protection_error(dut: TvDut) -> None:
    """Um SAV com proteção trocada levanta o erro de sincronismo."""
    await start(dut, bt656.frame_bytes(bad_line=40))
    await wait_status(dut, ERROR, ERROR)
    await bus.write(dut, STATUS, ERROR)
    status = await wait_status(dut, ERROR, ERROR)
    check(status & PRESENT != 0)


@cocotb.test()
async def test_read_pointer(dut: TvDut) -> None:
    """O ponteiro de leitura avança, dá a volta e recusa valor fora."""
    await start(dut, bt656.blank_bytes(2000))
    await bus.write(dut, RD_ADDR, 5)
    check_equal(await bus.read(dut, RD_ADDR), 5)
    await bus.read(dut, RD_DATA)
    check_equal(await bus.read(dut, RD_ADDR), 6)
    await bus.write(dut, RD_ADDR, WORDS)
    check_equal(await bus.read(dut, RD_ADDR), 6)
    await bus.write(dut, RD_ADDR, WORDS - 1)
    await bus.read(dut, RD_DATA)
    check_equal(await bus.read(dut, RD_ADDR), 0)

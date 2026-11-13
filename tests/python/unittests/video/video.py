"""Periférico de vídeo: registradores, temporização, imagem e clocks."""

import random
from collections.abc import Callable

import cocotb
from cocotb.handle import LogicObject
from cocotb.task import Task
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge
from cocotb.utils import get_sim_time

from tests.python.unittests.video import bus
from tests.python.unittests.video.raster import (
    Geometry,
    Model,
    capture,
    check_row,
    read_geometry,
    sample,
    seek,
)
from tests.python.unittests.video.registers import (
    CTRL,
    FRAME_COUNT,
    GEOMETRY,
    H_SYNC,
    H_TOTAL,
    MASK32,
    PALETTE,
    PALETTE_ENTRIES,
    PALETTE_PIXEL_BITS,
    STATUS,
    STATUS_VBLANK,
    STATUS_VSYNC,
    V_BACK,
    V_SYNC,
    V_TOTAL,
)
from tests.python.unittests.video.signals import VideoDut
from tests.python.utils.check import check
from tests.python.utils.rng import seeded

SEED = 0x7A1
FRAMES = 3
RANDOM_WRITES = 300
EDGES_PER_FRAME_CHECK = 6
MARGIN = 2
EDGE_ROWS = 6
SETTLE_PIXELS = 10
RATIOS = ((13, 40), (40, 40), (57, 40))
MAX_ENABLE_CYCLES = 8


def eq(actual: int, expected: int, message: str = "") -> None:
    """Falha o teste se dois valores diferem.

    Parameters
    ----------
    actual : int
        Valor observado.
    expected : int
        Valor esperado.
    message : str
        Texto da falha.
    """
    check(actual == expected, f"{message}: {actual:#x} != {expected:#x}")


async def prepare(
    dut: VideoDut,
    system_ns: int = bus.SYSTEM_NS,
    pixel_ns: int = bus.PIXEL_NS,
) -> tuple[Geometry, Model, list[Task[None]]]:
    """Reinicia o periférico e zera o framebuffer e a paleta.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    system_ns : int
        Período do clock do sistema em nanossegundos.
    pixel_ns : int
        Período do clock de pixel em nanossegundos.

    Returns
    -------
    tuple[Geometry, Model, list[Task[None]]]
        A geometria lida, o modelo de memória zerado e os clocks.
    """
    tasks = await bus.start(dut, system_ns, pixel_ns)
    geo = await read_geometry(dut)
    await fill(dut, Model(geo), lambda _: 0)
    model = Model(geo)
    if geo.pixel_bits == PALETTE_PIXEL_BITS:
        await bus.write_burst(
            dut, ((PALETTE + n, 0, bus.FULL_MASK) for n in range(256))
        )
    return geo, model, tasks


async def fill(
    dut: VideoDut, model: Model, source: Callable[[int], int]
) -> None:
    """Preenche o framebuffer inteiro e atualiza o modelo.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    model : Model
        Modelo que recebe as mesmas escritas.
    source : Callable[[int], int]
        Função que devolve a palavra de cada índice.
    """
    accesses: list[tuple[int, int, int]] = []
    for index in range(model.geo.words):
        value = source(index)
        model.write(index, value, bus.FULL_MASK)
        accesses.append((model.geo.window + index, value, bus.FULL_MASK))
    await bus.write_burst(dut, accesses)


async def fill_random(dut: VideoDut, model: Model, rng: random.Random) -> None:
    """Preenche o framebuffer com palavras aleatórias.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    model : Model
        Modelo que recebe as mesmas escritas.
    rng : random.Random
        Gerador do estímulo.
    """
    words = [rng.getrandbits(32) for _ in range(model.geo.words)]
    await fill(dut, model, words.__getitem__)


def image_rows(geo: Geometry) -> list[tuple[int, int]]:
    """Faixas de linhas da tela a conferir (início e quantidade).

    Parameters
    ----------
    geo : Geometry
        Dimensões do framebuffer.

    Returns
    -------
    list[tuple[int, int]]
        Faixas contíguas, uma captura por faixa.
    """
    height = geo.fb_height * geo.scale
    if height <= 2 * EDGE_ROWS * geo.scale:
        return [(geo.y_off - MARGIN, height + 2 * MARGIN)]
    return [
        (geo.y_off - MARGIN, EDGE_ROWS + MARGIN),
        (geo.y_off + height - EDGE_ROWS, EDGE_ROWS + MARGIN),
    ]


async def verify_image(dut: VideoDut, model: Model) -> None:
    """Captura as faixas de linhas e confere cada pixel e sincronismo.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    model : Model
        Conteúdo esperado.
    """
    for first, count in image_rows(model.geo):
        rows = await capture(dut, first, count)
        for offset, row in enumerate(rows):
            check_row(model, (first + offset) % V_TOTAL, row)


async def edge_times(signal: LogicObject, count: int) -> list[float]:
    """Instantes, em ns, das primeiras bordas de descida e de subida.

    Parameters
    ----------
    signal : LogicObject
        Sinal a observar.
    count : int
        Número de pares descida e subida.

    Returns
    -------
    list[float]
        Instantes alternados de descida e de subida.
    """
    times: list[float] = []
    for _ in range(count):
        await FallingEdge(signal)
        times.append(get_sim_time("ns"))
        await RisingEdge(signal)
        times.append(get_sim_time("ns"))
    return times


@cocotb.test()
async def test_registers(dut: VideoDut) -> None:
    """Reset, escrita com máscara e endereços sem registrador."""
    await bus.start(dut)
    geo = await read_geometry(dut)
    eq(await bus.read(dut, CTRL), 0, "controle no reset")
    eq(await bus.read(dut, FRAME_COUNT), 0, "contador")
    eq(
        await bus.read(dut, GEOMETRY),
        (geo.fb_height << 16) | geo.fb_width,
        "geometria",
    )
    await bus.write(dut, CTRL, MASK32, 0b1110)
    eq(await bus.read(dut, CTRL), 0, "máscara sem o byte 0")
    await bus.write(dut, CTRL, 0xFFFFFFFE)
    eq(await bus.read(dut, CTRL), 0, "só o bit 0 existe")
    await bus.write(dut, CTRL, 1)
    eq(await bus.read(dut, CTRL), 1, "liga")
    for address in (GEOMETRY, GEOMETRY + 1, STATUS, FRAME_COUNT):
        await bus.write(dut, address, MASK32)
    eq(await bus.read(dut, GEOMETRY), (geo.fb_height << 16) | geo.fb_width)
    for address in (5, 255, 300, 511, 512, geo.window + geo.words):
        eq(await bus.read(dut, address), 0, f"lacuna {address:#x}")
    eq(await bus.read(dut, geo.window), 0, "o framebuffer não é legível")
    await bus.start(dut)
    eq(await bus.read(dut, CTRL), 0, "reset desliga a exibição")


@cocotb.test()
async def test_sync_timing(dut: VideoDut) -> None:
    """Contagem exata de ciclos de HS e VS, ativos em nível baixo."""
    await bus.start(dut)
    eq(int(dut.o_vga_hs.value), 1, "HS em repouso")
    eq(int(dut.o_vga_vs.value), 1, "VS em repouso")
    hs = await edge_times(dut.o_vga_hs, EDGES_PER_FRAME_CHECK)
    for index in range(0, len(hs) - 2, 2):
        eq(round((hs[index + 1] - hs[index]) / bus.PIXEL_NS), H_SYNC, "HS")
        eq(round((hs[index + 2] - hs[index]) / bus.PIXEL_NS), H_TOTAL, "linha")
    vs = await edge_times(dut.o_vga_vs, FRAMES)
    for index in range(0, len(vs) - 2, 2):
        low = round((vs[index + 1] - vs[index]) / bus.PIXEL_NS)
        eq(low, V_SYNC * H_TOTAL, "VS")
        frame = round((vs[index + 2] - vs[index]) / bus.PIXEL_NS)
        eq(frame, V_TOTAL * H_TOTAL, "quadro")


@cocotb.test()
async def test_disabled_output_is_black(dut: VideoDut) -> None:
    """Com a exibição desligada só os sincronismos saem."""
    geo, model, _ = await prepare(dut)
    await fill(dut, model, lambda _: MASK32)
    await bus.write(dut, CTRL, 0)
    rows = await capture(dut, geo.y_off, 2)
    for offset, row in enumerate(rows):
        check_row(Model(geo), geo.y_off + offset, row)


@cocotb.test()
async def test_framebuffer_content(dut: VideoDut) -> None:
    """Pixels, ampliação, centralização e faixas contra o modelo."""
    geo, model, _ = await prepare(dut)
    rng = seeded(SEED)
    if geo.pixel_bits == PALETTE_PIXEL_BITS:
        entries = [rng.getrandbits(16) for _ in range(PALETTE_ENTRIES)]
        for index, value in enumerate(entries):
            model.write_palette(index, value, bus.FULL_MASK)
        await bus.write_burst(
            dut,
            ((PALETTE + n, v, bus.FULL_MASK) for n, v in enumerate(entries)),
        )
    await fill(dut, model, lambda _: rng.getrandbits(32))
    await bus.write(dut, CTRL, 1)
    await verify_image(dut, model)


@cocotb.test()
async def test_byte_masks_and_window(dut: VideoDut) -> None:
    """Escritas aleatórias com máscara; fora da janela, ignoradas."""
    geo, model, _ = await prepare(dut)
    rng = seeded(SEED + 1)
    accesses: list[tuple[int, int, int]] = []
    span = 2 * geo.fb_width // geo.pixels_per_word
    for _ in range(RANDOM_WRITES):
        index = rng.randrange(0, span)
        data, mask = rng.getrandbits(32), rng.randrange(0, 16)
        model.write(index, data, mask)
        accesses.append((geo.window + index, data, mask))
    # Dentro da janela, depois do último pixel: a escrita é descartada.
    accesses.append((geo.window + geo.words, MASK32, bus.FULL_MASK))
    accesses.append((geo.window + (1 << (geo.addr_width - 1)) - 1, 1, 15))
    # No espaço de registradores, o framebuffer não é tocado.
    accesses.append((PALETTE - 1, MASK32, bus.FULL_MASK))
    await bus.write_burst(dut, accesses)
    await bus.write(dut, CTRL, 1)
    await verify_image(dut, model)


@cocotb.test()
async def test_palette(dut: VideoDut) -> None:
    """A paleta de 8 bits por pixel; sem ela, a escrita é ignorada."""
    geo, model, _ = await prepare(dut)
    rng = seeded(SEED + 2)
    if geo.pixel_bits != PALETTE_PIXEL_BITS:
        await bus.write(dut, PALETTE, MASK32)
        eq(await bus.read(dut, PALETTE), 0, "sem paleta")
        return
    for index in range(PALETTE_ENTRIES):
        data, mask = rng.getrandbits(32), rng.choice((0b0011, 0b1111, 0b0001))
        model.write_palette(index, data, mask)
        await bus.write(dut, PALETTE + index, data, mask)
    await fill(dut, model, lambda i: (i * 0x04030201) & MASK32)
    await bus.write(dut, CTRL, 1)
    await verify_image(dut, model)


async def frame_status(dut: VideoDut) -> tuple[int, int, int]:
    """Estado lido no pulso de VS, depois dele e na área visível.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.

    Returns
    -------
    tuple[int, int, int]
        Contador de quadros no pulso e o estado nos três instantes.
    """
    await FallingEdge(dut.o_vga_vs)
    await ClockCycles(dut.i_pixel_clk, SETTLE_PIXELS)
    during = await bus.read(dut, STATUS)
    count = await bus.read(dut, FRAME_COUNT)
    await RisingEdge(dut.o_vga_vs)
    await ClockCycles(dut.i_pixel_clk, SETTLE_PIXELS)
    after = await bus.read(dut, STATUS)
    await ClockCycles(dut.i_pixel_clk, (V_BACK + 100) * H_TOTAL)
    visible = await bus.read(dut, STATUS)
    return count, during | (after << 8), visible


async def check_frames(dut: VideoDut) -> list[int]:
    """Confere o estado de VS e de apagamento em quadros consecutivos.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.

    Returns
    -------
    list[int]
        O contador de quadros lido em cada quadro.
    """
    counts: list[int] = []
    for _ in range(FRAMES):
        count, edges, visible = await frame_status(dut)
        eq(edges & 0xFF, STATUS_VSYNC | STATUS_VBLANK, "durante o pulso")
        eq(edges >> 8, STATUS_VBLANK, "depois do pulso")
        eq(visible, 0, "na área visível")
        counts.append(count)
    return counts


@cocotb.test()
async def test_vsync_status_and_frame_counter(dut: VideoDut) -> None:
    """O estado de VS e de apagamento e um quadro por contagem."""
    await bus.start(dut)
    eq(await bus.read(dut, STATUS), 0, "estado logo após o reset")
    counts = await check_frames(dut)
    check(counts == [1, 2, 3], f"contador de quadros {counts}")


async def enable_latency(dut: VideoDut, geo: Geometry, level: int) -> int:
    """Ciclos de pixel que a habilitação leva para chegar aos pinos.

    A imagem inteira é branca; a habilitação muda no meio de uma linha.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    geo : Geometry
        Dimensões do framebuffer.
    level : int
        Valor escrito no controle.

    Returns
    -------
    int
        Ciclos de pixel entre o fim da escrita e a saída mudar.
    """
    await bus.write(dut, CTRL, 1 - level)
    await seek(dut, geo.y_off + 1, geo.x_off + 2)
    await bus.write(dut, CTRL, level)
    cycles = 0
    while (sample(dut).color != (0, 0, 0)) != bool(level):
        await FallingEdge(dut.i_pixel_clk)
        cycles += 1
    return cycles


async def white_screen(dut: VideoDut, geo: Geometry, model: Model) -> None:
    """Deixa todos os pixels do framebuffer brancos.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    geo : Geometry
        Dimensões do framebuffer.
    model : Model
        Modelo que acompanha a memória.
    """
    if geo.pixel_bits == PALETTE_PIXEL_BITS:
        model.write_palette(0xFF, 0xFFF, bus.FULL_MASK)
        await bus.write(dut, PALETTE + 0xFF, 0xFFF)
    await fill(dut, model, lambda _: MASK32)


@cocotb.test()
async def test_clock_domain_crossing(dut: VideoDut) -> None:
    """Razões de clock distintas: contador, imagem e a habilitação."""
    for system_ns, pixel_ns in RATIOS:
        geo, model, tasks = await prepare(dut, system_ns, pixel_ns)
        rng = seeded(SEED + system_ns)
        await fill_random(dut, model, rng)
        await bus.write(dut, CTRL, 1)
        rows = await capture(dut, geo.y_off, 3)
        for offset, row in enumerate(rows):
            check_row(model, geo.y_off + offset, row)
        counts = await check_frames(dut)
        check(
            counts == [counts[0] + n for n in range(FRAMES)],
            f"um quadro por contagem: {counts}",
        )
        await white_screen(dut, geo, model)
        for level in (1, 0, 1):
            cycles = await enable_latency(dut, geo, level)
            check(cycles <= MAX_ENABLE_CYCLES, f"habilitação em {cycles}")
        for task in tasks:
            task.cancel()

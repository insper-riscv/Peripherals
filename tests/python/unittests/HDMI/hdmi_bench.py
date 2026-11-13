"""Bancada do HDMI: clocks, barramento e imagem de referência."""

import random
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Protocol

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.task import Task
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.HDMI.adv7513 import Adv7513Model, I2cPins
from tests.python.unittests.HDMI.monitor import (
    OutputDut,
    Sample,
    Timing,
    sample_clocks,
)
from tests.python.unittests.video.bus import drive
from tests.python.unittests.video.registers import Axis, ModeDut
from tests.python.utils.check import check

CTRL, STATUS, FRAME_COUNT = 0, 1, 2
GEOMETRY, FORMAT = 3, 4
HDMI_MODE = 8
HDMI_STATUS = 9
IRQ_EN = 10
IRQ_PEND = 11
SEQ_CTRL = 12
SEQ_COUNT = 13
PIXEL_KHZ = 14
PALETTE = 256

ST_INT = 1 << 0
ST_BUSY = 1 << 1
ST_DONE = 1 << 2
ST_NACK = 1 << 3
ST_INIT = 1 << 4
IRQ_FRAME = 1 << 0
IRQ_INT = 1 << 1
INDEXED_FLAG = 1 << 24
MASK32 = 0xFFFFFFFF
FULL_MASK = 0xF
PALETTE_MASK = 0x7
SYSTEM_NS = 13
SMALL_PIXEL_PS = 40_000
RESET_CYCLES = 30
RESET_INPUTS = {
    "i_rst": 1,
    "i_write": 0,
    "i_address": 0,
    "i_data_in": 0,
    "i_byteena": FULL_MASK,
    "i_tx_int": 1,
    "i_i2c_sda": 1,
}
PIXEL_PERIOD_PS = {1: 39682, 2: 37036, 4: 13468, 16: 6734}


class TxDut(OutputDut, ModeDut, Protocol):
    """Sinais do periférico HDMI."""

    o_irq: LogicObject
    o_data_out: LogicArrayObject
    i_write: LogicObject
    i_byteena: LogicArrayObject
    i_address: LogicArrayObject
    i_data_in: LogicArrayObject
    i_rst: LogicObject
    i_clk: LogicObject
    i_tx_int: LogicObject
    i_i2c_sda: LogicObject
    o_i2c_sda_out: LogicObject
    o_i2c_sda_oe: LogicObject
    o_i2c_scl_out: LogicObject
    o_i2c_scl_oe: LogicObject
    addr_width: LogicArrayObject
    mode_id: LogicArrayObject


@dataclass(frozen=True)
class Geometry:
    """Geometria e formato do framebuffer, lidos dos registradores.

    Attributes
    ----------
    width : int
        Largura em pixels.
    height : int
        Altura em pixels.
    scale : int
        Fator de ampliação.
    indexed : bool
        Formato indexado quando verdadeiro, RGB565 quando falso.
    window : int
        Endereço de palavra do início da janela do framebuffer.
    timing : Timing
        Temporização do modo.
    """

    width: int
    height: int
    scale: int
    indexed: bool
    window: int
    timing: Timing

    @property
    def pixel_bits(self) -> int:
        """Bits que cada pixel ocupa no framebuffer."""
        return 8 if self.indexed else 16

    @property
    def per_word(self) -> int:
        """Pixels por palavra de 32 bits."""
        return 32 // self.pixel_bits

    @property
    def x_off(self) -> int:
        """Primeira coluna da imagem na área visível."""
        return (self.timing.h_visible - self.width * self.scale) // 2

    @property
    def y_off(self) -> int:
        """Primeira linha da imagem na área visível."""
        return (self.timing.v_visible - self.height * self.scale) // 2


def timing_of(dut: TxDut) -> Timing:
    """Lê a temporização dos generics.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.

    Returns
    -------
    Timing
        A temporização do modo.
    """
    return Timing(
        Axis(
            int(dut.h_visible.value),
            int(dut.h_front_porch.value),
            int(dut.h_sync.value),
            int(dut.h_back_porch.value),
            bool(int(dut.h_sync_positive.value)),
        ),
        Axis(
            int(dut.v_visible.value),
            int(dut.v_front_porch.value),
            int(dut.v_sync.value),
            int(dut.v_back_porch.value),
            bool(int(dut.v_sync_positive.value)),
        ),
    )


async def cycles(dut: TxDut, count: int) -> None:
    """Espera ciclos do clock do sistema.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    count : int
        Número de bordas de subida.
    """
    for _ in range(count):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


async def start(
    dut: TxDut, pixel_ps: int = SMALL_PIXEL_PS, release: bool = True
) -> list[Task[None]]:
    """Inicia os dois clocks e aplica o reset.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    pixel_ps : int
        Período do clock de pixel em picossegundos.
    release : bool
        Solta o reset no fim quando verdadeiro.

    Returns
    -------
    list[Task[None]]
        As tarefas dos clocks.
    """
    tasks = [
        cocotb.start_soon(Clock(dut.i_clk, SYSTEM_NS, unit="ns").start()),
        cocotb.start_soon(Clock(dut.i_pixel_clk, pixel_ps, unit="ps").start()),
    ]
    drive(dut, **RESET_INPUTS)
    await cycles(dut, RESET_CYCLES)
    if release:
        await release_reset(dut)
    return tasks


async def release_reset(dut: TxDut) -> None:
    """Solta o reset e espera um ciclo do sistema.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    """
    dut.i_rst.value = 0
    await cycles(dut, 1)


async def write_access(dut: TxDut, access: tuple[int, int, int]) -> None:
    """Aplica um acesso de escrita durante um ciclo do sistema.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    access : tuple[int, int, int]
        Endereço de palavra, dado e máscara de bytes.
    """
    address, data, mask = access
    drive(dut, i_address=address, i_data_in=data & MASK32, i_byteena=mask)
    await RisingEdge(dut.i_clk)


async def write_burst(
    dut: TxDut, accesses: Iterable[tuple[int, int, int]]
) -> None:
    """Escreve acessos em sequência, um por ciclo do clock do sistema.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    accesses : Iterable[tuple[int, int, int]]
        Cada tupla traz endereço de palavra, dado e máscara de bytes.
    """
    dut.i_write.value = 1
    for access in accesses:
        await write_access(dut, access)
    await Timer(1, unit="ns")
    dut.i_write.value = 0
    # A escrita sai registrada: dois ciclos a levam até a memória.
    await cycles(dut, 2)


async def write(dut: TxDut, address: int, data: int) -> None:
    """Escreve uma palavra inteira, com os quatro bytes habilitados.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    address : int
        Endereço de palavra.
    data : int
        Dado de 32 bits.
    """
    await write_burst(dut, [(address, data, FULL_MASK)])


async def read(dut: TxDut, address: int) -> int:
    """Lê uma palavra do periférico, sem esperar clock.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    address : int
        Endereço de palavra.

    Returns
    -------
    int
        O dado lido, combinacional no endereço.
    """
    dut.i_address.value = address
    await Timer(1, unit="ns")
    return int(dut.o_data_out.value)


async def read_geometry(dut: TxDut) -> Geometry:
    """Lê a geometria e o formato dos registradores.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.

    Returns
    -------
    Geometry
        As dimensões e o formato do framebuffer.
    """
    size = await read(dut, GEOMETRY)
    fmt = await read(dut, FORMAT)
    return Geometry(
        width=size & 0xFFFF,
        height=size >> 16,
        scale=(fmt >> 8) & 0xFF,
        indexed=bool(fmt & INDEXED_FLAG),
        window=1 << (int(dut.addr_width.value) - 1),
        timing=timing_of(dut),
    )


def expand_565(pixel: int) -> int:
    """Expandir um pixel RGB565 para 24 bits.

    Parameters
    ----------
    pixel : int
        Pixel de 16 bits.

    Returns
    -------
    int
        A cor de 24 bits.
    """
    red, green, blue = (pixel >> 11) & 0x1F, (pixel >> 5) & 0x3F, pixel & 0x1F
    red8 = (red << 3) | (red >> 2)
    green8 = (green << 2) | (green >> 4)
    blue8 = (blue << 3) | (blue >> 2)
    return (red8 << 16) | (green8 << 8) | blue8


class Image:
    """Imagem de referência: o framebuffer e a paleta do teste."""

    def __init__(self, geometry: Geometry, seed: int) -> None:
        """Sorteia o conteúdo do framebuffer e da paleta.

        Parameters
        ----------
        geometry : Geometry
            Geometria do periférico.
        seed : int
            Semente do sorteio.
        """
        rng = random.Random(seed)  # noqa: S311
        self.geometry = geometry
        limit = 256 if geometry.indexed else 1 << 16
        self.pixels = [
            [rng.randrange(limit) for _ in range(geometry.width)]
            for _ in range(geometry.height)
        ]
        self.palette = [rng.randrange(1 << 24) for _ in range(256)]

    def color(self, x: int, y: int) -> int:
        """Cor de 24 bits do pixel do framebuffer.

        Parameters
        ----------
        x : int
            Coluna do framebuffer.
        y : int
            Linha do framebuffer.

        Returns
        -------
        int
            A cor que sai para o transmissor.
        """
        pixel = self.pixels[y][x]
        if self.geometry.indexed:
            return self.palette[pixel]
        return expand_565(pixel)

    def expected(self, column: int, line: int, lit: bool) -> int:
        """Cor esperada em uma posição da área visível.

        Parameters
        ----------
        column : int
            Coluna da área visível.
        line : int
            Linha da área visível.
        lit : bool
            A exibição está habilitada.

        Returns
        -------
        int
            A cor de 24 bits, preta fora da imagem ou sem exibição.
        """
        geo = self.geometry
        x = column - geo.x_off
        y = line - geo.y_off
        inside = (
            0 <= x < geo.width * geo.scale and 0 <= y < geo.height * geo.scale
        )
        if not (lit and inside):
            return 0
        return self.color(x // geo.scale, y // geo.scale)

    def words(self) -> list[int]:
        """Montar as palavras do framebuffer.

        O pixel de menor índice fica nos bits baixos.

        Returns
        -------
        list[int]
            As palavras na ordem do endereço.
        """
        geo = self.geometry
        flat = [p for row in self.pixels for p in row]
        result: list[int] = []
        for first in range(0, len(flat), geo.per_word):
            word = 0
            for k in range(geo.per_word):
                word |= flat[first + k] << (k * geo.pixel_bits)
            result.append(word)
        return result


async def load_image(dut: TxDut, image: Image) -> None:
    """Escreve o framebuffer e a paleta da imagem de referência.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    image : Image
        Imagem a escrever.
    """
    geo = image.geometry
    if geo.indexed:
        await write_burst(
            dut,
            [
                (PALETTE + i, color, PALETTE_MASK)
                for i, color in enumerate(image.palette)
            ],
        )
    await write_burst(
        dut,
        [(geo.window + i, w, FULL_MASK) for i, w in enumerate(image.words())],
    )


async def sample_for(dut: TxDut, timing: Timing, frames: int) -> list[Sample]:
    """Amostra as saídas durante um número de quadros.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    timing : Timing
        Temporização do modo.
    frames : int
        Número de quadros a amostrar.

    Returns
    -------
    list[Sample]
        As amostras, uma por ciclo de pixel.
    """
    return await sample_clocks(dut, frames * timing.frame_clocks)


def frame_origin(samples: list[Sample], timing: Timing) -> int:
    """Índice da amostra da coluna 0 da linha 0 do segundo quadro.

    Parameters
    ----------
    samples : list[Sample]
        Amostras de vários quadros.
    timing : Timing
        Temporização do modo.

    Returns
    -------
    int
        O índice, localizado pelo primeiro pulso de VS.
    """
    active = int(timing.v_positive)
    first = next(
        i
        for i in range(1, len(samples))
        if samples[i].vs == active and samples[i - 1].vs != active
    )
    begin_line = timing.v.visible + timing.v.front
    return first - begin_line * timing.h_total + timing.frame_clocks


def check_samples(
    samples: list[Sample], image: Image, lit: bool, frames: int = 2
) -> None:
    """Confere cada amostra de quadros completos contra a imagem.

    O quadro é localizado pelo primeiro pulso de VS; as amostras
    seguintes são comparadas, uma a uma, com a temporização e o
    framebuffer.

    Parameters
    ----------
    samples : list[Sample]
        Amostras de pelo menos frames + 1 quadros.
    image : Image
        Imagem de referência.
    lit : bool
        A exibição está habilitada.
    frames : int
        Quadros completos a conferir.
    """
    timing = image.geometry.timing
    origin = frame_origin(samples, timing)
    check(
        origin + frames * timing.frame_clocks <= len(samples),
        "amostras insuficientes",
    )
    for index in range(frames * timing.frame_clocks):
        line, column = divmod(index, timing.h_total)
        line %= timing.v_total
        got = samples[origin + index]
        frame = index // timing.frame_clocks
        where = f"quadro {frame} linha {line} coluna {column}"
        check(got.hs == timing.hs_level(column), f"HS em {where}")
        check(got.vs == timing.vs_level(line), f"VS em {where}")
        visible = timing.visible(column, line)
        check(got.de == int(visible), f"DE em {where}")
        want = image.expected(column, line, lit) if visible else 0
        check(
            got.data == want,
            f"pixel em {where}: obtido {got.data:#08x}, esperado {want:#08x}",
        )


def build_model(dut: TxDut) -> Adv7513Model:
    """Cria o modelo do escravo ligado aos pinos I2C do periférico.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.

    Returns
    -------
    Adv7513Model
        O modelo, ainda parado.
    """
    return Adv7513Model(
        I2cPins(dut.o_i2c_scl_oe, dut.o_i2c_sda_oe, dut.i_i2c_sda)
    )

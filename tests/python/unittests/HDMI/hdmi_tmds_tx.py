"""HDMI com TMDS direto: do framebuffer aos pares diferenciais.

O teste carrega uma imagem pelo barramento, liga a exibição, amostra os
pinos dos quatro pares nas duas bordas do clock serial e decodifica o
fluxo TMDS de volta em pixels e sincronismos. Cada pixel decodificado é
conferido contra o framebuffer com a mesma bancada do periférico para o
ADV7513. O pino de detecção de conexão é conferido pelo estado e pela
interrupção.
"""

from typing import Protocol, cast

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import FallingEdge, RisingEdge, Timer

from tests.python.unittests.HDMI import hdmi_bench as bench
from tests.python.unittests.HDMI.hdmi_bench import Image, TxDut
from tests.python.unittests.HDMI.monitor import Sample
from tests.python.utils.check import check
from tests.python.utils.tmds_reference import (
    CLOCK_TOKEN,
    CONTROL_TOKENS,
    TOKEN_BITS,
    decode,
    symbols,
)

PIXEL_PS = 40_000
SERIAL_PS = PIXEL_PS // 5
SYSTEM_NS = 13
RESET_CYCLES = 30
FULL_MASK = 0xF
FRAMES = 4
LANES = 4
CLOCK_LANE = 3
CHANNEL_SHIFT = (0, 8, 16)
CONTROL_OF = {token: pair for pair, token in CONTROL_TOKENS.items()}
IRQ_HPD = bench.IRQ_INT


class TmdsDut(Protocol):
    """Sinais do periférico HDMI com TMDS direto."""

    i_clk: LogicObject
    i_pixel_clk: LogicObject
    i_serial_clk: LogicObject
    i_rst: LogicObject
    i_hpd: LogicObject
    i_write: LogicObject
    i_address: LogicArrayObject
    i_data_in: LogicArrayObject
    i_byteena: LogicArrayObject
    o_data_out: LogicArrayObject
    o_irq: LogicObject
    o_tmds_d: LogicArrayObject
    o_tmds_clk: LogicObject


def as_bus(dut: TmdsDut) -> TxDut:
    """Vê o periférico pelos sinais de barramento da bancada.

    A bancada do ADV7513 só toca nas portas de barramento e nos generics
    de modo, que este periférico tem iguais.

    Parameters
    ----------
    dut : TmdsDut
        Periférico sob teste.

    Returns
    -------
    TxDut
        O mesmo objeto, com o tipo que as funções da bancada esperam.
    """
    return cast("TxDut", dut)


async def start(dut: TmdsDut) -> None:
    """Inicia os três clocks do PLL e libera o reset.

    Parameters
    ----------
    dut : TmdsDut
        Periférico sob teste.
    """
    dut.i_rst.value = 1
    dut.i_hpd.value = 0
    dut.i_write.value = 0
    dut.i_address.value = 0
    dut.i_data_in.value = 0
    dut.i_byteena.value = FULL_MASK
    cocotb.start_soon(Clock(dut.i_clk, SYSTEM_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.i_pixel_clk, PIXEL_PS, unit="ps").start())
    cocotb.start_soon(Clock(dut.i_serial_clk, SERIAL_PS, unit="ps").start())
    await bench.cycles(as_bus(dut), RESET_CYCLES)
    await bench.release_reset(as_bus(dut))


async def capture(dut: TmdsDut, fast_cycles: int) -> list[list[int]]:
    """Amostra os pinos dos pares, dois bits por ciclo do clock serial.

    Parameters
    ----------
    dut : TmdsDut
        Periférico sob teste.
    fast_cycles : int
        Número de ciclos do clock serial a amostrar.

    Returns
    -------
    list[list[int]]
        Para cada par (azul, verde, vermelho e clock), os bits na ordem
        de transmissão.
    """
    bits: list[list[int]] = [[] for _ in range(LANES)]
    for _ in range(fast_cycles):
        for edge in (RisingEdge, FallingEdge):
            await edge(dut.i_serial_clk)
            await Timer(1, unit="ns")
            data = dut.o_tmds_d.value
            levels = [int(data[lane]) for lane in range(LANES - 1)]
            levels.append(int(dut.o_tmds_clk.value))
            for lane, level in enumerate(levels):
                bits[lane].append(level)
    return bits


def clock_phase(stream: list[int]) -> int:
    """Acha a posição em que o símbolo do canal de clock começa.

    Parameters
    ----------
    stream : list[int]
        Bits do canal de clock.

    Returns
    -------
    int
        Posição do primeiro símbolo completo do clock.

    Raises
    ------
    AssertionError
        Se o padrão do clock não aparece.
    """
    pattern = [(CLOCK_TOKEN >> i) & 1 for i in range(TOKEN_BITS)]
    for first in range(len(stream) - TOKEN_BITS):
        last = first + TOKEN_BITS
        if stream[first:last] == pattern:
            return first
    message = "o par de clock não tem o padrão de cinco uns e cinco zeros"
    raise AssertionError(message)


def decode_pixel(
    tokens: tuple[int, int, int], idle: tuple[int, int]
) -> Sample:
    """Decodifica os símbolos dos três canais de um ciclo de pixel.

    Os sincronismos só viajam no apagamento, então num pixel de dados
    eles valem o nível de repouso do modo.

    Parameters
    ----------
    tokens : tuple[int, int, int]
        Símbolos dos canais azul, verde e vermelho.
    idle : tuple[int, int]
        Nível de repouso de HS e de VS.

    Returns
    -------
    Sample
        DE, HS, VS e a cor de 24 bits do ciclo.
    """
    data = [decode(token) for token in tokens]
    carries_data = [byte is not None for byte in data]
    check(
        all(carries_data) or not any(carries_data),
        "os três canais concordam se há dados",
    )
    if all(carries_data):
        color = sum(
            (byte or 0) << shift
            for byte, shift in zip(data, CHANNEL_SHIFT, strict=True)
        )
        return Sample(1, idle[0], idle[1], color)
    blue, green, red = tokens
    check(
        green == CONTROL_TOKENS[0] and red == CONTROL_TOKENS[0],
        "verde e vermelho enviam o símbolo de controle zero",
    )
    c1, c0 = divmod(CONTROL_OF[blue], 2)
    return Sample(0, c0, c1, 0)


def to_samples(lanes: list[list[int]], idle: tuple[int, int]) -> list[Sample]:
    """Decodifica os pares em um pixel por ciclo de pixel.

    Parameters
    ----------
    lanes : list[list[int]]
        Bits de cada par, na ordem de transmissão.
    idle : tuple[int, int]
        Nível de repouso de HS e de VS.

    Returns
    -------
    list[Sample]
        DE, HS, VS e a cor de 24 bits de cada ciclo de pixel.
    """
    phase = clock_phase(lanes[CLOCK_LANE])
    words = [symbols(lanes[lane], phase) for lane in range(LANES - 1)]
    clock_words = symbols(lanes[CLOCK_LANE], phase)
    check(
        all(word == CLOCK_TOKEN for word in clock_words),
        "o par de clock repete o símbolo",
    )
    return [
        decode_pixel((blue, green, red), idle)
        for blue, green, red in zip(*words, strict=True)
    ]


@cocotb.test()
async def test_framebuffer_reaches_the_pairs(dut: TmdsDut) -> None:
    """Cada pixel e sincronismo decodificado confere com o modo."""
    await start(dut)
    bus = as_bus(dut)
    geo = await bench.read_geometry(bus)
    image = Image(geo, seed=11)
    await bench.load_image(bus, image)
    await bench.write(bus, bench.CTRL, 1)
    frame = geo.timing.frame_clocks
    lanes = await capture(dut, FRAMES * frame * TOKEN_BITS // 2)
    timing = geo.timing
    idle = (int(not timing.h_positive), int(not timing.v_positive))
    samples = to_samples(lanes, idle)
    bench.check_samples(samples, image, lit=True)


@cocotb.test()
async def test_hot_plug_pin_and_missing_sequencer(dut: TmdsDut) -> None:
    """O pino de conexão aparece no estado e na interrupção."""
    await start(dut)
    bus = as_bus(dut)
    status = await bench.read(bus, bench.HDMI_STATUS)
    check(status & bench.ST_INT == 0, "monitor desconectado")
    check(status & bench.ST_INIT == 0, "sem sequenciador do ADV7513")
    await bench.write(bus, bench.IRQ_EN, IRQ_HPD)
    check(int(dut.o_irq.value) == 0, "sem interrupção desconectado")
    dut.i_hpd.value = 1
    await bench.cycles(bus, 6)
    status = await bench.read(bus, bench.HDMI_STATUS)
    check(status & bench.ST_INT != 0, "monitor conectado")
    check(int(dut.o_irq.value) == 1, "a conexão levanta a interrupção")
    await bench.write(bus, bench.IRQ_PEND, IRQ_HPD)
    check(int(dut.o_irq.value) == 0, "escrever 1 limpa a pendência")

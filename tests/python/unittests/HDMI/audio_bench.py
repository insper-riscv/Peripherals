"""Bancada do áudio HDMI: receptor I2S e medidas dos clocks."""

import itertools
from dataclasses import dataclass, field
from typing import Protocol

from cocotb.handle import LogicObject
from cocotb.triggers import RisingEdge

from tests.python.unittests.audio.common import (
    BCLK_DIV,
    CAPS,
    CLK_EN,
    CONTROL,
    SLOT_BITS,
    TX_DATA,
    TX_EN,
    XCK_MOD,
    XCK_STEP,
    control,
    pairs_of,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import IrqDut
from tests.python.utils.i2s_codec import I2sCodec, I2sWires, to_signed

SYSTEM_HZ = 100_000_000
SLOT = 32
SCLK_PER_FRAME = 2 * SLOT
SETTLE_FRAMES = 3
MEASURED_FRAMES = 12
JITTER_CYCLES = 2
WAIT_STEP = 1000
WAIT_LIMIT = 2000
CAPS_MASTER = 1
CAPS_TONE = 2
LEFT_RIGHT = [(0x1234, -0x0765), (-0x7000, 0x4321), (0x0001, -0x0001)]


class AudioPinsDut(IrqDut, Protocol):
    """Sinais do áudio HDMI."""

    o_mclk: LogicObject
    o_sclk: LogicObject
    o_lrclk: LogicObject
    o_i2s0: LogicObject


@dataclass(frozen=True)
class Rate:
    """Configuração de reset de uma instância.

    Attributes
    ----------
    sample_rate : int
        Taxa de amostragem em Hz.
    mclk_ratio : int
        Razão MCLK/LRCLK.
    word_bits : int
        Largura da palavra em bits.
    """

    sample_rate: int
    mclk_ratio: int
    word_bits: int

    @property
    def mclk_hz(self) -> int:
        """Frequência do clock mestre em Hz."""
        return self.sample_rate * self.mclk_ratio

    @property
    def bclk_div(self) -> int:
        """Inversões do mestre por inversão do SCLK."""
        return self.mclk_ratio // SCLK_PER_FRAME


@dataclass
class Half:
    """Medida de um semiciclo do LRCLK (um canal).

    Attributes
    ----------
    mclk : int
        Bordas de subida do MCLK no semiciclo.
    sclk : int
        Bordas de subida do SCLK no semiciclo.
    cycles : int
        Ciclos do clock do sistema no semiciclo.
    """

    mclk: int = 0
    sclk: int = 0
    cycles: int = 0


@dataclass
class Meter:
    """Contador dos clocks I2S, sempre amostrado na borda do sistema.

    Attributes
    ----------
    halves : list[Half]
        Semiciclos completos medidos, na ordem.
    """

    halves: list[Half] = field(default_factory=list[Half])

    async def run(self, dut: AudioPinsDut, count: int) -> None:
        """Meça count semiciclos completos do LRCLK.

        Parameters
        ----------
        dut : AudioPinsDut
            Periférico sob teste.
        count : int
            Semiciclos completos a medir, depois da primeira troca.
        """
        mclk, sclk, lrclk = 0, 0, 0
        current: Half | None = None
        while len(self.halves) < count:
            await RisingEdge(dut.i_clk)
            now = (
                int(dut.o_mclk.value),
                int(dut.o_sclk.value),
                int(dut.o_lrclk.value),
            )
            if current is not None:
                current.cycles += 1
                current.mclk += int(now[0] == 1 and mclk == 0)
                current.sclk += int(now[1] == 1 and sclk == 0)
            if now[2] != lrclk:
                if current is not None:
                    self.halves.append(current)
                current = Half()
            mclk, sclk, lrclk = now


async def start(dut: AudioPinsDut) -> None:
    """Reinicie o periférico parado.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste.
    """
    await bus.reset(dut)


def codec(dut: AudioPinsDut, word_bits: int) -> I2sCodec:
    """Crie o receptor I2S ligado aos pinos do transmissor.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste.
    word_bits : int
        Largura da palavra em bits.

    Returns
    -------
    I2sCodec
        Receptor já em execução.
    """
    wires = I2sWires(dut.o_sclk, dut.o_lrclk, dut.o_i2s0, None)
    receiver = I2sCodec(wires, word_bits)
    receiver.start()
    return receiver


async def wait_pairs(
    dut: AudioPinsDut, receiver: I2sCodec, count: int
) -> None:
    """Espere o receptor reunir count pares.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste.
    receiver : I2sCodec
        Receptor que captura os pinos.
    count : int
        Pares esperados.

    Raises
    ------
    TimeoutError
        Se os pares não chegarem dentro do limite.
    """
    for _ in range(WAIT_LIMIT):
        if len(pairs_of(receiver)) >= count:
            return
        await bus.cycles(dut, WAIT_STEP)
    message = "os pares não chegaram"
    raise TimeoutError(message)


async def check_reset(dut: AudioPinsDut, rate: Rate) -> None:
    """Confira o estado de reset e as contas que o definem.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste.
    rate : Rate
        Configuração esperada.
    """
    await start(dut)
    check(await bus.read(dut, CAPS) & CAPS_MASTER == 1, "modo mestre")
    check(await bus.read(dut, XCK_STEP) == 2 * rate.mclk_hz, "passo")
    check(await bus.read(dut, XCK_MOD) == SYSTEM_HZ, "módulo")
    check(await bus.read(dut, BCLK_DIV) == rate.bclk_div, "divisor do SCLK")
    check(await bus.read(dut, SLOT_BITS) == SLOT, "slot de 32 ciclos")
    check(await bus.read(dut, CONTROL) & 0x7F == 0, "parado")
    for name in ("o_mclk", "o_sclk", "o_lrclk", "o_i2s0"):
        check(int(getattr(dut, name).value) == 0, f"{name} em repouso")


async def check_counts(dut: AudioPinsDut, rate: Rate) -> None:
    """Meça as razões entre MCLK, SCLK e LRCLK e a taxa de amostragem.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste.
    rate : Rate
        Configuração esperada.
    """
    await start(dut)
    await bus.write(dut, CONTROL, control(rate.word_bits, CLK_EN))
    meter = Meter()
    await meter.run(dut, SETTLE_FRAMES + 2 * MEASURED_FRAMES)
    halves = meter.halves[SETTLE_FRAMES:]
    for half in halves:
        check(half.mclk == rate.mclk_ratio // 2, f"MCLK por canal {half}")
        check(half.sclk == SLOT, f"SCLK por canal {half}")
    total = sum(half.cycles for half in halves)
    want = len(halves) * SYSTEM_HZ / (2 * rate.sample_rate)
    check(abs(total - want) <= JITTER_CYCLES, f"{total} ciclos, {want:.1f}")
    check(
        all(abs(half.cycles - want / len(halves)) <= 1 for half in halves),
        "cada canal dura o esperado, com no máximo 1 ciclo de jitter",
    )


async def check_playback(dut: AudioPinsDut, rate: Rate) -> None:
    """Reconstrua no receptor as amostras escritas na fila.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste.
    rate : Rate
        Configuração esperada.
    """
    await start(dut)
    receiver = codec(dut, rate.word_bits)
    shift = rate.word_bits - 16
    mask = (1 << rate.word_bits) - 1
    for left, right in LEFT_RIGHT:
        await bus.write(dut, TX_DATA, (left << shift) & mask)
        await bus.write(dut, TX_DATA, (right << shift) & mask)
    want = LEFT_RIGHT
    await bus.write(dut, CONTROL, control(rate.word_bits, TX_EN | CLK_EN))
    await wait_pairs(dut, receiver, len(want) + 2)
    pairs = [
        (to_signed(a, rate.word_bits), to_signed(b, rate.word_bits))
        for a, b in pairs_of(receiver)
    ]
    start_at = pairs.index((want[0][0] << shift, want[0][1] << shift))
    end = start_at + len(want)
    got = pairs[start_at:end]
    check(got == [(a << shift, b << shift) for a, b in want], f"{got}")
    check(receiver.padding_clean, "preenchimento zerado")
    check(receiver.short_slots == 0, "todo canal tem 32 ciclos")
    receiver.stop()


async def check_rate_switch(
    dut: AudioPinsDut, rate: Rate, other: Rate
) -> None:
    """Troque a taxa por registradores e meça a nova.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste.
    rate : Rate
        Configuração de reset.
    other : Rate
        Configuração para a qual o software muda.
    """
    await start(dut)
    await bus.write(dut, CONTROL, control(rate.word_bits, CLK_EN))
    await bus.cycles(dut, 3 * SYSTEM_HZ // rate.sample_rate)
    await bus.write(dut, CONTROL, 0)
    await bus.write(dut, XCK_STEP, 2 * other.mclk_hz)
    await bus.write(dut, BCLK_DIV, other.bclk_div)
    await bus.write(dut, CONTROL, control(other.word_bits, CLK_EN))
    meter = Meter()
    await meter.run(dut, SETTLE_FRAMES + 2 * MEASURED_FRAMES)
    halves = meter.halves[SETTLE_FRAMES:]
    check(
        all(half.mclk == other.mclk_ratio // 2 for half in halves),
        "MCLK por canal na nova taxa",
    )
    check(all(half.sclk == SLOT for half in halves), "SCLK por canal")
    total = sum(half.cycles for half in halves)
    want = len(halves) * SYSTEM_HZ / (2 * other.sample_rate)
    check(abs(total - want) <= JITTER_CYCLES, f"{total} ciclos, {want:.1f}")


async def check_tone(
    dut: AudioPinsDut, rate: Rate, half: int, amplitude: int
) -> None:
    """Confira o tom de teste sem escrita nos registradores.

    Parameters
    ----------
    dut : AudioPinsDut
        Periférico sob teste, com início automático.
    rate : Rate
        Configuração esperada.
    half : int
        Quadros por semiciclo do tom.
    amplitude : int
        Amplitude do tom em escala de 16 bits.
    """
    await start(dut)
    check(await bus.read(dut, CAPS) & CAPS_TONE == CAPS_TONE, "tom presente")
    receiver = codec(dut, rate.word_bits)
    await wait_pairs(dut, receiver, SETTLE_FRAMES + 4 * half)
    left = [pair[0] for pair in pairs_of(receiver)][SETTLE_FRAMES:]
    high = amplitude << (rate.word_bits - 16)
    check(set(left) == {high, -high}, f"{set(left)}")
    edges = [i for i in range(1, len(left)) if left[i] != left[i - 1]]
    gaps = {b - a for a, b in itertools.pairwise(edges)}
    check(gaps == {half}, f"semiciclo {gaps}")
    receiver.stop()

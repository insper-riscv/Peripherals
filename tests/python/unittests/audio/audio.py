"""Áudio I2S: filas, serializadores, tom e interrupção."""

import itertools

import cocotb

from tests.python.unittests.audio.common import (
    BCLK_DIV,
    CAPS,
    CLK_EN,
    CONFIG,
    CONTROL,
    ERR_IRQ_EN,
    IRQ_LEVEL,
    LEVELS,
    RX_DATA,
    RX_EN,
    RX_FULL,
    RX_IRQ_EN,
    RX_NOT_EMPTY,
    RX_OVERFLOW,
    SLOT_BITS,
    STATUS,
    TONE_AMP,
    TONE_EN,
    TONE_HALF,
    TX_DATA,
    TX_DROPPED,
    TX_EMPTY,
    TX_EN,
    TX_IRQ_EN,
    TX_NOT_FULL,
    TX_UNDERFLOW,
    XCK_MOD,
    XCK_STEP,
    control,
    has_pairs,
    has_words,
    pairs_of,
    restart,
    setup,
    start_codec,
    usable,
    wait_rx_level,
    wait_until,
)
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioDut
from tests.python.utils.i2s_codec import to_signed

DEPTH = 8
XCK_HZ = 12_288_000
SAMPLE_HZ = 48_000
RESET_IRQ_LEVEL = 0x00010000
SYSTEM_HZ = 50_000_000
RESET_TONE_HALF = 24
RESET_TONE_AMP = 0x2000
HAS_TONE = 2
FRAME_WORDS = 2
TONE_FRAMES = 30
LEFT_RIGHT = [(0x1234, -0x0765), (-0x7000, 0x4321), (0x0001, -0x0001)]


async def word_sizes(dut: AudioDut) -> list[int]:
    """Devolva as larguras de palavra que cabem no canal.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.

    Returns
    -------
    list[int]
        Larguras de 16, 24 e 32 bits até o tamanho do canal.
    """
    slot = await bus.read(dut, SLOT_BITS)
    return [bits for bits in (16, 24, 32) if bits <= slot]


def scaled(value: int, bits: int) -> int:
    """Escale uma amostra de 16 bits para a largura da palavra.

    Parameters
    ----------
    value : int
        Amostra de 16 bits com sinal.
    bits : int
        Largura da palavra.

    Returns
    -------
    int
        Amostra ocupando os bits mais altos da palavra.
    """
    return value << (bits - 16)


@cocotb.test()
async def reset_state(dut: AudioDut) -> None:
    """Comece parado, com filas vazias e a configuração do reset."""
    await setup(dut)
    check(await bus.read(dut, CONTROL) & 0x7F == 0, "controle zerado")
    status = await bus.read(dut, STATUS)
    check(status == TX_NOT_FULL | TX_EMPTY, f"estado {status:#x}")
    check(await bus.read(dut, LEVELS) == 0, "níveis zerados")
    check(await bus.read(dut, CONFIG) == DEPTH | (DEPTH << 16), "filas")
    check(await bus.read(dut, CAPS) & HAS_TONE == HAS_TONE, "tom presente")
    check(await bus.read(dut, IRQ_LEVEL) == RESET_IRQ_LEVEL, "limiares")
    check(await bus.read(dut, XCK_STEP) == 2 * XCK_HZ, "passo")
    check(await bus.read(dut, XCK_MOD) == SYSTEM_HZ, "módulo")
    check(await bus.read(dut, TONE_HALF) == RESET_TONE_HALF, "tom de 1 kHz")
    check(await bus.read(dut, TONE_AMP) == RESET_TONE_AMP, "amplitude")
    div = await bus.read(dut, BCLK_DIV)
    slot = await bus.read(dut, SLOT_BITS)
    check(SAMPLE_HZ * div * 2 * slot == XCK_HZ, "48 kHz no reset")
    check(int(dut.o_irq.value) == 0, "sem interrupção")
    check(int(dut.o_xck.value) == 0, "clock mestre parado")


@cocotb.test()
async def plays_frames_in_order(dut: AudioDut) -> None:
    """Reconstrua no DAC as amostras escritas, para cada largura."""
    await setup(dut)
    codec = None
    for bits in await word_sizes(dut):
        await restart(dut, codec)
        codec = await start_codec(dut, bits, [])
        for left, right in LEFT_RIGHT:
            await bus.write(dut, TX_DATA, scaled(left, bits) & 0xFFFFFFFF)
            await bus.write(dut, TX_DATA, scaled(right, bits) & 0xFFFFFFFF)
        want = [scaled(v, bits) for pair in LEFT_RIGHT for v in pair]
        await bus.write(dut, CONTROL, control(bits, TX_EN | CLK_EN))
        await wait_until(dut, has_words(codec, len(want) + FRAME_WORDS))
        got = usable(codec)
        check(got[: len(want)] == want, f"{bits} bits: {got[:8]}")
        check(codec.padding_clean, "preenchimento zerado")
        start = len(want)
        tail = got[start:]
        check(set(tail) == {0}, "saída zerada sem dados")
        status = await bus.read(dut, STATUS)
        check(status & TX_UNDERFLOW != 0, "subfluxo marcado")
        await bus.write(dut, STATUS, TX_UNDERFLOW)
        await bus.write(dut, CONTROL, 0)
        check(await bus.read(dut, STATUS) & TX_UNDERFLOW == 0, "limpo")


@cocotb.test()
async def underflow_keeps_channels_aligned(dut: AudioDut) -> None:
    """Não consuma meio quadro: a palavra espera o par."""
    await setup(dut)
    bits = 16
    codec = await start_codec(dut, bits, [])
    await bus.write(dut, TX_DATA, 0x1111)
    await bus.write(dut, CONTROL, control(bits, TX_EN | CLK_EN))
    await bus.cycles(dut, 3000)
    status = await bus.read(dut, STATUS)
    check(status & TX_UNDERFLOW != 0, "subfluxo com meio quadro")
    check(await bus.read(dut, LEVELS) & 0xFFFF == 1, "palavra mantida")
    check(set(usable(codec)) <= {0}, "saída zerada")
    await bus.write(dut, TX_DATA, 0x2222)
    await wait_until(dut, has_words(codec, FRAME_WORDS))
    check(usable(codec)[:2] == [0x1111, 0x2222], f"{usable(codec)[:4]}")


@cocotb.test()
async def full_queue_drops_writes(dut: AudioDut) -> None:
    """Descarte a escrita na fila cheia e marque TX_DROPPED."""
    await setup(dut)
    for index in range(DEPTH):
        await bus.write(dut, TX_DATA, index)
    status = await bus.read(dut, STATUS)
    check(status & TX_NOT_FULL == 0, "fila cheia")
    check(status & TX_DROPPED == 0, "nada descartado")
    await bus.write(dut, TX_DATA, 0xFF)
    status = await bus.read(dut, STATUS)
    check(status & TX_DROPPED != 0, "descarte marcado")
    check(await bus.read(dut, LEVELS) & 0xFFFF == DEPTH, "nível mantido")
    await bus.write(dut, STATUS, 0)
    check(await bus.read(dut, STATUS) & TX_DROPPED != 0, "zero preserva")
    await bus.write(dut, STATUS, TX_DROPPED)
    check(await bus.read(dut, STATUS) & TX_DROPPED == 0, "um limpa")


@cocotb.test()
async def records_frames_with_sign(dut: AudioDut) -> None:
    """Receba as amostras do ADC com sinal, para cada largura."""
    await setup(dut)
    codec = None
    for bits in await word_sizes(dut):
        await restart(dut, codec)
        pairs = [(scaled(a, bits), scaled(b, bits)) for a, b in LEFT_RIGHT]
        codec = await start_codec(dut, bits, pairs)
        await bus.write(dut, CONTROL, control(bits, RX_EN | CLK_EN))
        want = [v for pair in pairs for v in pair]
        await wait_rx_level(dut, len(want))
        got: list[int] = []
        while await bus.read(dut, STATUS) & RX_NOT_EMPTY:
            got.append(to_signed(await bus.read(dut, RX_DATA), 32))
        check(got[: len(want)] == want, f"{bits} bits: {got}")
        await bus.write(dut, CONTROL, 0)


@cocotb.test()
async def record_overflow_drops_whole_frames(dut: AudioDut) -> None:
    """Descarte quadros inteiros com a fila cheia (RX_OVERFLOW)."""
    await setup(dut)
    bits = 16
    pairs = [(10 + index, -(20 + index)) for index in range(8)]
    await start_codec(dut, bits, pairs)
    await bus.write(dut, CONTROL, control(bits, RX_EN | CLK_EN))
    await wait_rx_level(dut, DEPTH)
    await bus.cycles(dut, 4000)
    status = await bus.read(dut, STATUS)
    check(status & RX_FULL != 0, "fila cheia")
    check(status & RX_OVERFLOW != 0, "sobrefluxo marcado")
    got = [to_signed(await bus.read(dut, RX_DATA), 32) for _ in range(DEPTH)]
    want = [v for pair in pairs[: DEPTH // 2] for v in pair]
    check(got == want, f"{got}")
    await bus.write(dut, STATUS, RX_OVERFLOW)
    check(await bus.read(dut, STATUS) & RX_OVERFLOW == 0, "limpo")


@cocotb.test()
async def interrupt_follows_thresholds(dut: AudioDut) -> None:
    """Gere interrupção por limiar das filas e por erro."""
    await setup(dut)
    bits = 16
    await bus.write(dut, IRQ_LEVEL, (2 << 16) | 2)
    await bus.write(dut, CONTROL, control(bits, TX_IRQ_EN))
    await bus.cycles(dut, 2)
    check(int(dut.o_irq.value) == 1, "reprodução com nível abaixo")
    for value in (1, 2, 3):
        await bus.write(dut, TX_DATA, value)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 0, "reprodução acima do limiar")
    await bus.write(dut, CONTROL, control(bits, RX_IRQ_EN))
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 0, "gravação abaixo do limiar")
    pairs = [(5, -5), (6, -6)]
    await start_codec(dut, bits, pairs)
    await bus.write(dut, CONTROL, control(bits, RX_EN | RX_IRQ_EN | CLK_EN))
    await wait_until(dut, lambda: int(dut.o_irq.value) == 1)
    while await bus.read(dut, STATUS) & RX_NOT_EMPTY:
        await bus.read(dut, RX_DATA)
    check(int(dut.o_irq.value) == 0, "cai ao esvaziar")
    await bus.write(dut, CONTROL, control(bits, ERR_IRQ_EN))
    await bus.write(dut, TX_DATA, 0)
    check(int(dut.o_irq.value) == 0, "sem erro")
    for _ in range(DEPTH):
        await bus.write(dut, TX_DATA, 0)
    await bus.cycles(dut, 1)
    check(int(dut.o_irq.value) == 1, "descarte interrompe")


@cocotb.test()
async def tone_is_a_square_wave(dut: AudioDut) -> None:
    """Gere a onda quadrada em hardware, sem escrever na fila."""
    await setup(dut)
    codec = None
    for bits in await word_sizes(dut):
        await restart(dut, codec)
        half = 4
        codec = await start_codec(dut, bits, [])
        await bus.write(dut, TONE_HALF, half)
        await bus.write(dut, TONE_AMP, 0x1000)
        flags = TONE_EN | TX_EN | CLK_EN
        await bus.write(dut, CONTROL, control(bits, flags))
        await wait_until(dut, has_pairs(codec, TONE_FRAMES))
        frames = pairs_of(codec)
        left = [pair[0] for pair in frames]
        right = [pair[1] for pair in frames]
        high = scaled(0x1000, bits)
        check(set(left[3:]) == {high, -high}, f"{bits}: {set(left)}")
        check(left[3:20] == right[3:20], "canais iguais")
        edges = [i for i in range(4, len(left)) if left[i] != left[i - 1]]
        gaps = {b - a for a, b in itertools.pairwise(edges)}
        check(gaps == {half}, f"semiciclo {gaps}")
        check(await bus.read(dut, STATUS) & TX_UNDERFLOW == 0, "sem subfluxo")
        await bus.write(dut, CONTROL, 0)

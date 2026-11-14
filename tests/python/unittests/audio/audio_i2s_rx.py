"""Desserializador I2S: larguras, canal justo e extensão de sinal."""

import cocotb

from tests.python.unittests.audio.common import SLAVE_HALF_NS
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioRxDut
from tests.python.utils.i2s_codec import (
    I2sCodec,
    I2sWires,
    drive_slave_clocks,
    to_signed,
)

PAIRS = [(0x1234, -0x0765), (-0x7000, 0x4321), (0x0001, -0x0001)]


async def receive(
    dut: AudioRxDut, bits: int, slot: int
) -> list[tuple[int, int]]:
    """Alimente o ADC e colete as palavras entregues.

    Parameters
    ----------
    dut : AudioRxDut
        Desserializador exercitado.
    bits : int
        Largura da palavra.
    slot : int
        Ciclos de BCLK por canal.

    Returns
    -------
    list[tuple[int, int]]
        Pares de canal e palavra com sinal, na ordem de chegada.
    """
    dut.i_enable.value = 1
    dut.i_word_bits.value = bits
    dut.i_bclk.value = 0
    dut.i_lrck.value = 0
    dut.i_sdata.value = 0
    await bus.hold_reset(dut)
    got: list[tuple[int, int]] = []

    async def collect() -> None:
        while True:
            await bus.cycles(dut, 1)
            if int(dut.o_valid.value):
                value = to_signed(int(dut.o_word.value), 32)
                got.append((int(dut.o_right.value), value))

    cocotb.start_soon(collect())
    pairs = [(a << (bits - 16), b << (bits - 16)) for a, b in PAIRS]
    wires = I2sWires(dut.i_bclk, dut.i_lrck, dut.i_sdata, dut.i_sdata)
    codec = I2sCodec(wires, bits, adc_pairs=pairs)
    codec.start()
    driver = cocotb.start_soon(
        drive_slave_clocks(dut.i_bclk, [dut.i_lrck], SLAVE_HALF_NS, slot)
    )
    await bus.cycles(dut, slot * 16 * 10)
    driver.cancel()
    codec.stop()
    return got


async def check_case(dut: AudioRxDut, bits: int, slot: int) -> None:
    """Confira as palavras, o sinal e o canal de uma configuração.

    Parameters
    ----------
    dut : AudioRxDut
        Desserializador exercitado.
    bits : int
        Largura da palavra.
    slot : int
        Ciclos de BCLK por canal.
    """
    got = await receive(dut, bits, slot)
    want = [
        (channel, value << (bits - 16))
        for pair in PAIRS
        for channel, value in enumerate(pair)
    ]
    first = 1
    stop = first + len(want)
    check(got[first:stop] == want, f"{bits}/{slot}")


@cocotb.test()
async def word_16_padded(dut: AudioRxDut) -> None:
    """Receba 16 bits com preenchimento."""
    await check_case(dut, 16, 32)


@cocotb.test()
async def word_24_padded(dut: AudioRxDut) -> None:
    """Receba 24 bits com preenchimento."""
    await check_case(dut, 24, 32)


@cocotb.test()
async def word_32_tight(dut: AudioRxDut) -> None:
    """Receba 32 bits com canal justo."""
    await check_case(dut, 32, 32)


@cocotb.test()
async def word_16_tight(dut: AudioRxDut) -> None:
    """Receba 16 bits com canal justo."""
    await check_case(dut, 16, 16)


@cocotb.test()
async def word_24_tight(dut: AudioRxDut) -> None:
    """Receba 24 bits com canal justo."""
    await check_case(dut, 24, 24)

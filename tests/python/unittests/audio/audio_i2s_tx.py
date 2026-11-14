"""Serializador I2S: formato, consumo por quadro e subfluxo."""

import cocotb
from cocotb.triggers import FallingEdge

from tests.python.unittests.audio.common import SLAVE_HALF_NS
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioTxDut
from tests.python.utils.i2s_codec import (
    I2sCodec,
    I2sWires,
    drive_slave_clocks,
)

WORD = 0xA5C30F81
FRAMES = 6


async def start(
    dut: AudioTxDut, slot: int, available: int
) -> tuple[I2sCodec, list[int]]:
    """Inicie os clocks, o codec simulado e a contagem de pulsos.

    Parameters
    ----------
    dut : AudioTxDut
        Serializador exercitado.
    slot : int
        Ciclos de BCLK por canal.
    available : int
        Valor de i_available.

    Returns
    -------
    tuple[I2sCodec, list[int]]
        Modelo do codec e contadores de carga, canal direito e subfluxo.
    """
    dut.i_enable.value = 1
    dut.i_available.value = available
    dut.i_data.value = WORD
    dut.i_bclk.value = 0
    dut.i_lrck.value = 0
    await bus.hold_reset(dut)
    counts = [0, 0, 0]

    async def count() -> None:
        while True:
            await FallingEdge(dut.i_clk)
            counts[0] += int(dut.o_load.value)
            counts[1] += int(dut.o_right_slot.value)
            counts[2] += int(dut.o_underflow.value)

    cocotb.start_soon(count())
    wires = I2sWires(dut.i_bclk, dut.i_lrck, dut.o_sdata, None)
    codec = I2sCodec(wires, 32)
    codec.start()
    cocotb.start_soon(
        drive_slave_clocks(dut.i_bclk, [dut.i_lrck], SLAVE_HALF_NS, slot)
    )
    await bus.cycles(dut, slot * 16 * (2 * FRAMES + 2))
    return codec, counts


async def play(dut: AudioTxDut, slot: int) -> None:
    """Envie a palavra nos dois canais, MSB primeiro.

    Parameters
    ----------
    dut : AudioTxDut
        Serializador exercitado.
    slot : int
        Ciclos de BCLK por canal.
    """
    codec, counts = await start(dut, slot, 1)
    words = [value & 0xFFFFFFFF for _, value in codec.dac_words]
    check(WORD in words, f"palavra ausente {slot}")
    check(counts[0] >= 2 * FRAMES - 2, f"cargas {counts}")
    check(counts[2] == 0, "sem subfluxo")
    check(codec.padding_clean, "preenchimento zerado")


@cocotb.test()
async def tight_slot(dut: AudioTxDut) -> None:
    """Envie com canal justo de 32 bits."""
    await play(dut, 32)


@cocotb.test()
async def padded_slot(dut: AudioTxDut) -> None:
    """Envie com 8 bits de preenchimento por canal."""
    await play(dut, 40)


@cocotb.test()
async def underflow_sends_silence(dut: AudioTxDut) -> None:
    """Saia zerado e pulse o subfluxo por quadro sem dados."""
    codec, counts = await start(dut, 32, 0)
    check({value for _, value in codec.dac_words} <= {0}, "silêncio")
    check(counts[0] == 0, "nada consumido")
    check(counts[2] >= FRAMES - 2, f"subfluxos {counts}")
    check(counts[1] >= FRAMES - 2, "canais direitos")

"""Áudio HDMI a 44,1 kHz, MCLK de 128 vezes e palavra de 16 bits."""

import cocotb

from tests.python.unittests.HDMI import audio_bench as bench
from tests.python.unittests.HDMI.audio_bench import AudioPinsDut, Rate

RATE = Rate(44_100, 128, 16)


@cocotb.test()
async def reset_state(dut: AudioPinsDut) -> None:
    """Comece parado, com os registradores de 44,1 kHz."""
    await bench.check_reset(dut, RATE)


@cocotb.test()
async def clock_counts(dut: AudioPinsDut) -> None:
    """Meça MCLK, SCLK e LRCLK em 44,1 kHz."""
    await bench.check_counts(dut, RATE)


@cocotb.test()
async def playback(dut: AudioPinsDut) -> None:
    """Reconstrua no receptor I2S as amostras escritas na fila."""
    await bench.check_playback(dut, RATE)

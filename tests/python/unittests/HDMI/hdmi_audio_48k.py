"""Áudio HDMI a 48 kHz, MCLK de 256 vezes e palavra de 24 bits."""

import cocotb

from tests.python.unittests.HDMI import audio_bench as bench
from tests.python.unittests.HDMI.audio_bench import AudioPinsDut, Rate

RATE = Rate(48_000, 256, 24)
OTHER = Rate(44_100, 128, 16)


@cocotb.test()
async def reset_state(dut: AudioPinsDut) -> None:
    """Comece parado, com os registradores de 48 kHz."""
    await bench.check_reset(dut, RATE)


@cocotb.test()
async def clock_counts(dut: AudioPinsDut) -> None:
    """Meça MCLK, SCLK e LRCLK em 48 kHz."""
    await bench.check_counts(dut, RATE)


@cocotb.test()
async def playback(dut: AudioPinsDut) -> None:
    """Reconstrua no receptor I2S as amostras escritas na fila."""
    await bench.check_playback(dut, RATE)


@cocotb.test()
async def rate_switch(dut: AudioPinsDut) -> None:
    """Troque para 44,1 kHz com MCLK de 128 vezes por registradores."""
    await bench.check_rate_switch(dut, RATE, OTHER)

"""Áudio HDMI com início automático: o tom sai sem software."""

import cocotb

from tests.python.unittests.HDMI import audio_bench as bench
from tests.python.unittests.HDMI.audio_bench import AudioPinsDut, Rate

RATE = Rate(44_100, 256, 24)
# Generics da instância: tom de 1 kHz e amplitude 0x2000 a 44,1 kHz.
HALF = 22
AMPLITUDE = 0x2000


@cocotb.test()
async def tone_without_software(dut: AudioPinsDut) -> None:
    """Toque o tom logo depois do reset, sem nenhuma escrita."""
    await bench.check_tone(dut, RATE, HALF, AMPLITUDE)

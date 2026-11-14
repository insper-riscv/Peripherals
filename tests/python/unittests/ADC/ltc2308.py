"""LTC2308 (DE10-Nano e DE0-Nano-SoC): varredura dos canais por SPI.

Um modelo do conversor (``Ltc2308Model``, com as suposições marcadas em
``adc_models``) liga-se aos pinos ADC_CONVST, ADC_SCK, ADC_SDI e
ADC_SDO. O teste confere o pulso de CONVST, a espera da conversão
antes do primeiro clock, a palavra de configuração de cada canal e as
leituras.
"""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.utils import bus
from tests.python.utils.adc_models import Ltc2308Model
from tests.python.utils.adc_regs import (
    CH_BASE,
    CONTROL,
    ENABLE,
    FRAMES_PER_SWEEP,
    IRQ_ENABLE,
    START,
    STATUS,
    SWEEP_DONE,
    VALID,
    VOLTS,
    wait_channel,
    wait_idle,
    wait_irq,
)
from tests.python.utils.check import check
from tests.python.utils.dut import Ltc2308Dut
from tests.python.utils.spi_slave import Wires

CLOCK_NS = 10
CONVST_NS = 100
CONVERSION_NS = 1600
NEW_VALUE = 0x0F0
CONFIG_UNIPOLAR_SINGLE = 0b100010


def expected_config(channel: int) -> int:
    """Devolva os seis bits de configuração de um canal.

    Parameters
    ----------
    channel : int
        Canal de 0 a 7.

    Returns
    -------
    int
        S/D, O/S, S1, S0, UNI e SLP, com S/D no bit mais alto.
    """
    odd, s0, s1 = channel & 1, (channel >> 1) & 1, (channel >> 2) & 1
    return CONFIG_UNIPOLAR_SINGLE | odd << 4 | s1 << 3 | s0 << 2


class Timing:
    """Tempos de um quadro vistos nos pinos."""

    def __init__(self) -> None:
        """Comece sem anotações."""
        self.convst_widths: list[int] = []
        self.convst_to_sck: list[int] = []


async def watch(dut: Ltc2308Dut, model: Ltc2308Model, timing: Timing) -> None:
    """Anote os pulsos de CONVST e o primeiro clock depois de cada um.

    Parameters
    ----------
    dut : Ltc2308Dut
        Controlador exercitado pelo teste.
    model : Ltc2308Model
        Conversor, que converte na subida de CONVST.
    timing : Timing
        Anotações dos tempos.
    """
    last_convst = 0
    rise_cycle = -1
    sck_seen = True
    cycle = 0
    while True:
        await RisingEdge(dut.i_clk)
        cycle += 1
        convst = int(dut.o_adc_convst.value)
        if convst and not last_convst:
            rise_cycle, sck_seen = cycle, False
            model.convst_rise()
        if not convst and last_convst:
            timing.convst_widths.append((cycle - rise_cycle) * CLOCK_NS)
        if int(dut.o_adc_sck.value) and not sck_seen:
            timing.convst_to_sck.append((cycle - rise_cycle) * CLOCK_NS)
            sck_seen = True
        last_convst = convst


async def setup(dut: Ltc2308Dut) -> tuple[Ltc2308Model, Timing]:
    """Reinicie o controlador e ligue o conversor simulado.

    Parameters
    ----------
    dut : Ltc2308Dut
        Controlador exercitado pelo teste.

    Returns
    -------
    tuple[Ltc2308Model, Timing]
        Conversor ligado aos pinos e anotações dos tempos.
    """
    dut.i_adc_sdo.value = 1
    await bus.reset(dut)
    pins = Wires(dut.o_adc_sck, dut.o_adc_sdi, dut.i_adc_sdo)
    model = Ltc2308Model(pins, list(VOLTS))
    model.start()
    timing = Timing()
    cocotb.start_soon(watch(dut, model, timing))
    return model, timing


@cocotb.test()
async def test_idle_pins(dut: Ltc2308Dut) -> None:
    """Em repouso CONVST e SCK ficam em nível baixo."""
    await setup(dut)
    await bus.cycles(dut, 5)
    check(int(dut.o_adc_convst.value) == 0, "CONVST baixo")
    check(int(dut.o_adc_sck.value) == 0, "SCK em repouso baixo")


@cocotb.test()
async def test_sweep_reads_each_channel(dut: Ltc2308Dut) -> None:
    """A varredura configura os oito canais e guarda cada tensão."""
    model, timing = await setup(dut)
    await bus.write(dut, CONTROL, START)
    await wait_idle(dut)
    want = [expected_config(channel) for channel in (*range(8), 0)]
    check(model.log == want, f"{model.log}")
    for channel, volts in enumerate(VOLTS):
        got = await bus.read(dut, CH_BASE + channel)
        check(got == volts, f"CH{channel} = {got:#x}, queria {volts:#x}")
    check(not model.errors, f"{model.errors}")
    check(len(timing.convst_widths) == FRAMES_PER_SWEEP, "um pulso por quadro")
    check(
        all(width >= CONVST_NS for width in timing.convst_widths),
        f"largura de CONVST {timing.convst_widths}",
    )
    check(
        all(gap >= CONVERSION_NS for gap in timing.convst_to_sck),
        f"conversão {timing.convst_to_sck}",
    )
    check(await bus.read(dut, STATUS) == SWEEP_DONE | VALID, "STATUS")


@cocotb.test()
async def test_continuous_sweep_tracks_a_changing_voltage(
    dut: Ltc2308Dut,
) -> None:
    """A varredura contínua acompanha a tensão e interrompe."""
    model, _ = await setup(dut)
    await bus.write(dut, CONTROL, ENABLE | IRQ_ENABLE)
    check(await wait_irq(dut), "interrupção de fim de varredura")
    await bus.write(dut, STATUS, SWEEP_DONE)
    model.values[0] = NEW_VALUE
    got = await wait_channel(dut, 0, NEW_VALUE)
    check(got == NEW_VALUE, "canal 0 acompanha")
    await bus.write(dut, CONTROL, 0)
    await wait_idle(dut)
    check(not model.errors, f"{model.errors}")

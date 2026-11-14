"""ADC128S022 (DE0-Nano): varredura dos oito canais por SPI.

Um modelo do conversor (``Adc128Model``, com as suposições marcadas em
``adc_models``) liga-se aos pinos ADC_CS_N, ADC_SCLK, ADC_SADDR e
ADC_SDAT. O teste confere o quadro de 16 clocks, o endereço de cada
canal e as leituras de tensão conhecida nos registradores.
"""

import cocotb

from tests.python.utils import bus
from tests.python.utils.adc_models import Adc128Model
from tests.python.utils.adc_regs import (
    CH_BASE,
    CONTROL,
    DIVIDER,
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
from tests.python.utils.dut import Adc128Dut
from tests.python.utils.spi_slave import Bit, Wires

CHANGED_VOLT = 0x321
MAX_SCLK_HZ = 3_200_000
CLOCK_HZ = 100_000_000


async def setup(dut: Adc128Dut) -> Adc128Model:
    """Reinicie o controlador e ligue o conversor simulado.

    Parameters
    ----------
    dut : Adc128Dut
        Controlador exercitado pelo teste.

    Returns
    -------
    Adc128Model
        Conversor ligado aos pinos.
    """
    dut.i_adc_sdat.value = 1
    await bus.reset(dut)
    pins = Wires(
        dut.o_adc_sclk, dut.o_adc_saddr, dut.i_adc_sdat, Bit(dut.o_adc_cs_n)
    )
    model = Adc128Model(pins, list(VOLTS))
    model.start()
    return model


@cocotb.test()
async def test_idle_pins(dut: Adc128Dut) -> None:
    """Em repouso CS fica alto, SCLK alto e SADDR em um."""
    await setup(dut)
    await bus.cycles(dut, 5)
    check(int(dut.o_adc_cs_n.value) == 1, "CS_N alto")
    check(int(dut.o_adc_sclk.value) == 1, "SCLK em repouso alto")
    check(await bus.read(dut, STATUS) == 0, "STATUS")


@cocotb.test()
async def test_sweep_reads_each_channel(dut: Adc128Dut) -> None:
    """A varredura endereça os oito canais e guarda cada tensão."""
    model = await setup(dut)
    await bus.write(dut, CONTROL, START)
    await wait_idle(dut)
    check(model.log == [*range(8), 0], f"{model.log}")
    for channel, volts in enumerate(VOLTS):
        got = await bus.read(dut, CH_BASE + channel)
        check(got == volts, f"CH{channel} = {got:#x}, queria {volts:#x}")
    check(model.frames == FRAMES_PER_SWEEP, f"{model.frames} quadros")
    check(not model.errors, f"{model.errors}")
    check(await bus.read(dut, STATUS) == SWEEP_DONE | VALID, "STATUS")


@cocotb.test()
async def test_continuous_sweep_tracks_a_changing_voltage(
    dut: Adc128Dut,
) -> None:
    """A varredura contínua acompanha a tensão e interrompe."""
    model = await setup(dut)
    await bus.write(dut, CONTROL, ENABLE | IRQ_ENABLE)
    check(await wait_irq(dut), "interrupção de fim de varredura")
    await bus.write(dut, STATUS, SWEEP_DONE)
    model.values[5] = CHANGED_VOLT
    got = await wait_channel(dut, 5, CHANGED_VOLT)
    check(got == CHANGED_VOLT, "canal 5 acompanha")
    check(await bus.read(dut, CH_BASE + 2) == VOLTS[2], "canal 2 igual")
    await bus.write(dut, CONTROL, 0)
    await wait_idle(dut)
    check(not model.errors, f"{model.errors}")
    check(int(dut.o_adc_cs_n.value) == 1, "CS alto no fim")


@cocotb.test()
async def test_sclk_frequency_does_not_exceed_the_chip(dut: Adc128Dut) -> None:
    """O divisor de reset mantém SCLK em no máximo 3,2 MHz."""
    await setup(dut)
    divider = await bus.read(dut, DIVIDER)
    check(CLOCK_HZ / (2 * (divider + 1)) <= MAX_SCLK_HZ, f"divisor {divider}")

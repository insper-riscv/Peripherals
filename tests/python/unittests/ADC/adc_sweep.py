"""Varredura dos oito canais: registradores e varreduras.

Um modelo no lado do quadro responde a cada pedido da varredura com o
resultado do canal, com o atraso de um quadro dos conversores reais
(``CHANNEL_LATENCY``, padrão 1) ou sem atraso, conforme o teste.
"""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.utils import bus
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
    wait_idle,
)
from tests.python.utils.check import check
from tests.python.utils.dut import AdcSweepDut

RESET_DIVIDER = 7
VALUES = (0x111, 0x222, 0x333, 0x444, 0x555, 0x666, 0x777, 0x888)
FRAME_DELAY = 3
NEW_VALUE = 0xABC


class FrameModel:
    """Chip no lado do quadro, com ``latency`` quadros de atraso."""

    def __init__(self, dut: AdcSweepDut, latency: int) -> None:
        """Crie o modelo.

        Parameters
        ----------
        dut : AdcSweepDut
            Varredura exercitada pelo teste.
        latency : int
            Quadros entre endereçar um canal e receber o resultado.
        """
        self.dut = dut
        self.latency = latency
        self.values: list[int] = list(VALUES)
        self.addressed: list[int] = []

    def start(self) -> None:
        """Inicie o processo que responde aos pedidos."""
        self.dut.i_frame_done.value = 0
        self.dut.i_frame_data.value = 0
        cocotb.start_soon(self._run())

    async def _run(self) -> None:
        """Responda a cada pedido de quadro depois de alguns ciclos."""
        dut = self.dut
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.o_frame_start.value):
                self.addressed.append(int(dut.o_frame_channel.value))
                for _ in range(FRAME_DELAY):
                    await RisingEdge(dut.i_clk)
                source = (
                    self.addressed[-1 - self.latency]
                    if (len(self.addressed) > self.latency)
                    else 0
                )
                dut.i_frame_data.value = self.values[source]
                dut.i_frame_done.value = 1
                await RisingEdge(dut.i_clk)
                dut.i_frame_done.value = 0


async def setup(dut: AdcSweepDut) -> FrameModel:
    """Reinicie a varredura e ligue o modelo do quadro.

    Parameters
    ----------
    dut : AdcSweepDut
        Varredura exercitada pelo teste.

    Returns
    -------
    FrameModel
        Modelo ligado aos sinais de quadro.
    """
    model = FrameModel(dut, int(dut.channel_latency.value))
    model.start()
    await bus.reset(dut)
    return model


@cocotb.test()
async def test_reset_values(dut: AdcSweepDut) -> None:
    """O reset zera os canais e deixa o divisor de reset."""
    await setup(dut)
    check(await bus.read(dut, STATUS) == 0, "STATUS")
    check(await bus.read(dut, CONTROL) == 0, "CONTROL")
    check(await bus.read(dut, DIVIDER) == RESET_DIVIDER, "DIVIDER")
    for channel in range(8):
        check(await bus.read(dut, CH_BASE + channel) == 0, f"CH{channel}")
    check(int(dut.o_irq.value) == 0, "sem interrupção")
    check(int(dut.o_frame_start.value) == 0, "sem pedido de quadro")


@cocotb.test()
async def test_one_shot_sweep(dut: AdcSweepDut) -> None:
    """START varre os oito canais com um quadro de preparo."""
    model = await setup(dut)
    await bus.write(dut, CONTROL, START)
    await wait_idle(dut)
    want = [*range(8), *([0] if model.latency else [])]
    check(model.addressed == want, f"{model.addressed}")
    for channel in range(8):
        got = await bus.read(dut, CH_BASE + channel)
        check(got == VALUES[channel], f"CH{channel} = {got:#x}")
    status = await bus.read(dut, STATUS)
    check(status == SWEEP_DONE | VALID, f"STATUS {status:#x}")
    await bus.write(dut, STATUS, SWEEP_DONE)
    check(await bus.read(dut, STATUS) == VALID, "W1C limpa SWEEP_DONE")
    check(await bus.read(dut, CONTROL) == 0, "START não fica gravado")


@cocotb.test()
async def test_continuous_sweep_follows_the_input(dut: AdcSweepDut) -> None:
    """Com ENABLE a varredura repete e acompanha a tensão de entrada."""
    model = await setup(dut)
    await bus.write(dut, CONTROL, ENABLE)
    for _ in range(40):
        await bus.cycles(dut, 25)
        if (await bus.read(dut, STATUS)) & SWEEP_DONE:
            break
    await bus.write(dut, STATUS, SWEEP_DONE)
    model.values[3] = NEW_VALUE
    for _ in range(80):
        await bus.cycles(dut, 25)
        if (await bus.read(dut, CH_BASE + 3)) == NEW_VALUE:
            break
    check(await bus.read(dut, CH_BASE + 3) == NEW_VALUE, "canal 3 atualizado")
    check(len(model.addressed) > FRAMES_PER_SWEEP, "varreduras repetidas")
    await bus.write(dut, CONTROL, 0)
    await wait_idle(dut)
    count = len(model.addressed)
    await bus.cycles(dut, 200)
    check(len(model.addressed) == count, "ENABLE em zero para a varredura")
    check(
        len(model.addressed) % (8 + model.latency) == 0,
        "termina a varredura em andamento",
    )


@cocotb.test()
async def test_interrupt(dut: AdcSweepDut) -> None:
    """A interrupção segue SWEEP_DONE com IRQ_ENABLE."""
    await setup(dut)
    await bus.write(dut, CONTROL, IRQ_ENABLE | START)
    check(int(dut.o_irq.value) == 0, "ainda varrendo")
    await wait_idle(dut)
    check(int(dut.o_irq.value) == 1, "fim de varredura")
    await bus.write(dut, STATUS, SWEEP_DONE)
    check(int(dut.o_irq.value) == 0, "limpa com W1C")
    await bus.write(dut, CONTROL, START)
    await wait_idle(dut)
    check(int(dut.o_irq.value) == 0, "sem habilitação")

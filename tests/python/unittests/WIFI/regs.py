"""Bloco de controle do módulo Wi-Fi: reset, boot, ACK e interrupção."""

import cocotb

from tests.python.unittests.WIFI.registers import (
    ACK,
    BOOT_LOW,
    CTRL,
    FALL,
    FALL_IRQ,
    PULSE,
    RESET_PULSE,
    RISE,
    RISE_IRQ,
    RUN,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.check import check_equal
from tests.python.utils.dut import WifiRegsDut

PULSE_CYCLES = 20


async def start(dut: WifiRegsDut) -> None:
    """Deixe ACK em baixo e reinicie o projeto.

    Parameters
    ----------
    dut : WifiRegsDut
        Projeto sob teste.
    """
    dut.i_wm_ack.value = 0
    await bus.reset(dut)


async def set_ack(dut: WifiRegsDut, level: int) -> None:
    """Mude ACK e espere o sincronizador.

    Parameters
    ----------
    dut : WifiRegsDut
        Projeto sob teste.
    level : int
        Novo nível do pino.
    """
    dut.i_wm_ack.value = level
    await bus.cycles(dut, 4)


@cocotb.test()
async def test_reset_state(dut: WifiRegsDut) -> None:
    """Depois do reset o módulo fica em reset, sem boot forçado."""
    await start(dut)
    check_equal(int(dut.o_wm_reset_n.value), 0)
    check_equal(int(dut.o_wm_gpio0_oe.value), 0)
    check_equal(int(dut.o_wm_gpio0.value), 0)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(await bus.read(dut, CTRL), 0)
    check_equal(await bus.read(dut, STATUS), 0)
    check_equal(await bus.read(dut, 5), 0)


@cocotb.test()
async def test_run_and_boot(dut: WifiRegsDut) -> None:
    """RUN solta o reset e BOOT_LOW puxa GPIO0 para baixo."""
    await start(dut)
    await bus.write(dut, CTRL, BOOT_LOW)
    check_equal(int(dut.o_wm_gpio0_oe.value), 1)
    check_equal(int(dut.o_wm_gpio0.value), 0)
    check_equal(int(dut.o_wm_reset_n.value), 0)
    await bus.write(dut, CTRL, BOOT_LOW | RUN)
    check_equal(int(dut.o_wm_reset_n.value), 1)
    check_equal(await bus.read(dut, CTRL), BOOT_LOW | RUN)
    await bus.write(dut, CTRL, RUN)
    check_equal(int(dut.o_wm_gpio0_oe.value), 0)


@cocotb.test()
async def test_reset_pulse(dut: WifiRegsDut) -> None:
    """O pulso segura o reset pelo tempo do generic e devolve a RUN."""
    await start(dut)
    await bus.write(dut, CTRL, RUN)
    await bus.write(dut, RESET_PULSE, 1)
    check_equal(int(dut.o_wm_reset_n.value), 0)
    check_equal(await bus.read(dut, STATUS) & PULSE, PULSE)
    low = 0
    while int(dut.o_wm_reset_n.value) == 0:
        await bus.cycles(dut, 1)
        low += 1
    check_equal(low, PULSE_CYCLES - 1)
    check_equal(await bus.read(dut, STATUS) & PULSE, 0)
    await bus.write(dut, CTRL, 0)
    await bus.write(dut, RESET_PULSE, 1)
    await bus.cycles(dut, PULSE_CYCLES + 2)
    check_equal(int(dut.o_wm_reset_n.value), 0)
    await bus.write(dut, RESET_PULSE, 0)
    check_equal(await bus.read(dut, STATUS) & PULSE, 0)


@cocotb.test()
async def test_ack_edges_and_irq(dut: WifiRegsDut) -> None:
    """As bordas de ACK ficam marcadas e interrompem com a máscara."""
    await start(dut)
    await set_ack(dut, 1)
    check_equal(await bus.read(dut, STATUS), ACK | RISE)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, CTRL, RISE_IRQ)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, STATUS, RISE)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(await bus.read(dut, STATUS), ACK)
    await set_ack(dut, 0)
    check_equal(await bus.read(dut, STATUS), FALL)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, CTRL, FALL_IRQ)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, STATUS, FALL)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(await bus.read(dut, STATUS), 0)


@cocotb.test()
async def test_reset_clears_flags(dut: WifiRegsDut) -> None:
    """O reset do sistema limpa as marcas e as máscaras."""
    await start(dut)
    await bus.write(dut, CTRL, RISE_IRQ | FALL_IRQ | RUN)
    await set_ack(dut, 1)
    check_equal(int(dut.o_irq.value), 1)
    dut.i_rst.value = 1
    await bus.cycles(dut, 2)
    dut.i_rst.value = 0
    await bus.cycles(dut, 1)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(await bus.read(dut, CTRL), 0)
    check_equal(await bus.read(dut, STATUS), ACK)

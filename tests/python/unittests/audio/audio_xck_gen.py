"""Gerador do clock mestre: razão fracionária exata e habilitação."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import AudioXckGenDut

WINDOW = 800


async def run(dut: AudioXckGenDut, step: int, modulus: int) -> int:
    """Conte as inversões de o_xck numa janela de ciclos.

    Parameters
    ----------
    dut : AudioXckGenDut
        Gerador exercitado.
    step : int
        Passo do acumulador.
    modulus : int
        Módulo do acumulador.

    Returns
    -------
    int
        Quantidade de pulsos de o_edge na janela.
    """
    dut.i_enable.value = 1
    dut.i_step.value = step
    dut.i_mod.value = modulus
    await bus.hold_reset(dut)
    flips = 0
    last = int(dut.o_xck.value)
    for _ in range(WINDOW):
        await bus.cycles(dut, 1)
        level = int(dut.o_xck.value)
        edge = int(dut.o_edge.value)
        check((level != last) == bool(edge), "o_edge acompanha a inversão")
        flips += edge
        last = level
    return flips


@cocotb.test()
async def ratio_is_exact(dut: AudioXckGenDut) -> None:
    """Inverta floor(janela * passo / módulo) vezes, dentro de uma."""
    flips = await run(dut, 3, 8)
    want = WINDOW * 3 // 8
    check(abs(flips - want) <= 1, f"{flips} contra {want}")


@cocotb.test()
async def full_rate_and_stop(dut: AudioXckGenDut) -> None:
    """Inverta a cada ciclo (passo igual ao módulo) e pare sem passo."""
    flips = await run(dut, 5, 5)
    check(flips >= WINDOW - 3, f"{flips}")
    dut.i_step.value = 0
    await bus.cycles(dut, 4)
    check(int(dut.o_xck.value) == 0, "parado sem passo")
    dut.i_step.value = 5
    dut.i_enable.value = 0
    await bus.cycles(dut, 4)
    check(int(dut.o_xck.value) == 0, "parado desabilitado")

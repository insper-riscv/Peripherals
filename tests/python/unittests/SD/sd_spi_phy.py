"""Mestre SPI de um byte: modo 0, divisor, ordem dos bits e fim do byte.

O teste liga MISO a um registrador de deslocamento que o modelo de
cartão do teste muda na borda de descida de SCLK, como um cartão real.
"""

from dataclasses import dataclass, field

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import SdSpiPhyDut

BYTE_BITS = 8
BYTE_TX = 0xA5
BYTE_RX = 0x3C
BYTE_FF = 0xFF
DIVIDERS = (1, 2, 5)
CYCLE_LIMIT = 2000
RESET_HOLD = 3
RESTART_CYCLES = 10


async def setup(dut: SdSpiPhyDut, divider: int) -> None:
    """Reinicie o mestre e programe o divisor.

    Parameters
    ----------
    dut : SdSpiPhyDut
        Mestre exercitado pelo teste.
    divider : int
        Metade do período de SCLK menos um, em ciclos.
    """
    dut.i_start.value = 0
    dut.i_tx_data.value = 0
    dut.i_miso.value = 1
    dut.i_divider.value = divider
    await bus.hold_reset(dut, RESET_HOLD)
    await bus.cycles(dut, 2)


@dataclass
class Capture:
    """O que o teste viu nos pinos durante um byte."""

    mosi: list[int] = field(default_factory=list[int])
    gaps: list[int] = field(default_factory=list[int])
    rx: int = -1
    done: int = 0
    moves: int = 0


def _watch(dut: SdSpiPhyDut, cap: Capture, state: list[int]) -> None:
    """Anote as bordas de SCLK e as mudanças de MOSI deste ciclo.

    Parameters
    ----------
    dut : SdSpiPhyDut
        Mestre exercitado pelo teste.
    cap : Capture
        Anotações do byte.
    state : list[int]
        SCLK e MOSI do ciclo anterior, ciclo da última borda de subida
        e ciclo atual.
    """
    sclk, mosi = int(dut.o_sclk.value), int(dut.o_mosi.value)
    previous_sclk, previous_mosi, last_rise, cycle = state
    if sclk == 1 and previous_sclk == 0:
        cap.mosi.append(mosi)
        if last_rise >= 0:
            cap.gaps.append(cycle - last_rise)
        state[2] = cycle
    elif sclk == 1 and mosi != previous_mosi:
        cap.moves += 1
    state[0], state[1], state[3] = sclk, mosi, cycle + 1


async def exchange(dut: SdSpiPhyDut, tx_value: int, rx_value: int) -> Capture:
    """Troque um byte e registre o que aconteceu nos pinos.

    O cartão simulado apresenta o próximo bit de ``rx_value`` em cada
    borda de descida de SCLK.

    Parameters
    ----------
    dut : SdSpiPhyDut
        Mestre exercitado pelo teste.
    tx_value : int
        Byte transmitido.
    rx_value : int
        Byte que o cartão simulado devolve.

    Returns
    -------
    Capture
        Bits de MOSI nas bordas de subida, períodos, byte recebido,
        pulsos de fim e mudanças de MOSI com SCLK em nível alto.
    """
    dut.i_tx_data.value = tx_value
    dut.i_start.value = 1
    await bus.cycles(dut, 1)
    dut.i_start.value = 0
    bits = [(rx_value >> (BYTE_BITS - 1 - i)) & 1 for i in range(BYTE_BITS)]
    dut.i_miso.value = bits[0]
    cap = Capture()
    state = [0, int(dut.o_mosi.value), -1, 0]
    for _ in range(CYCLE_LIMIT):
        await bus.cycles(dut, 1)
        falling = int(dut.o_sclk.value) == 0 and state[0] == 1
        _watch(dut, cap, state)
        if falling and len(cap.mosi) < BYTE_BITS:
            dut.i_miso.value = bits[len(cap.mosi)]
        if int(dut.o_done.value) == 1:
            cap.done += 1
            cap.rx = int(dut.o_rx_data.value)
            break
    return cap


@cocotb.test()
async def test_byte_in_mode_zero(dut: SdSpiPhyDut) -> None:
    """O byte sai do bit 7 ao 0 em modo 0 e o byte recebido chega."""
    await setup(dut, 2)
    check(int(dut.o_sclk.value) == 0, "SCLK em repouso em nível baixo")
    check(int(dut.o_mosi.value) == 1, "MOSI em repouso em nível alto")
    seen = await exchange(dut, BYTE_TX, BYTE_RX)
    bits = seen.mosi
    check(len(bits) == BYTE_BITS, f"{bits}")
    value = sum(bit << (BYTE_BITS - 1 - i) for i, bit in enumerate(bits))
    check(value == BYTE_TX, f"MOSI amostrado {value:#x}")
    check(seen.rx == BYTE_RX, f"recebido {seen.rx}")
    check(seen.done == 1, "um pulso de fim")
    check(seen.moves == 0, "MOSI só muda com SCLK em baixo")
    check(int(dut.o_busy.value) == 0, "ocioso depois do byte")
    check(int(dut.o_mosi.value) == 1, "MOSI volta ao nível alto")


@cocotb.test()
async def test_sclk_period_for_each_divider(dut: SdSpiPhyDut) -> None:
    """O período de SCLK vale 2 * (divisor + 1) ciclos."""
    for divider in DIVIDERS:
        await setup(dut, divider)
        seen = await exchange(dut, BYTE_FF, BYTE_FF)
        gaps = seen.gaps
        check(
            set(gaps) == {2 * (divider + 1)},
            f"divisor {divider}: períodos {set(gaps)}",
        )
        check(seen.rx == BYTE_FF)


@cocotb.test()
async def test_start_while_busy_is_ignored(dut: SdSpiPhyDut) -> None:
    """Um pedido de início durante um byte não o interrompe."""
    await setup(dut, 1)
    dut.i_tx_data.value = BYTE_TX
    dut.i_start.value = 1
    await bus.cycles(dut, 1)
    dut.i_tx_data.value = BYTE_RX
    bits: list[int] = []
    previous = 0
    for cycle in range(CYCLE_LIMIT):
        await bus.cycles(dut, 1)
        if cycle == RESTART_CYCLES:
            dut.i_start.value = 0
        sclk = int(dut.o_sclk.value)
        if sclk == 1 and previous == 0:
            bits.append(int(dut.o_mosi.value))
        previous = sclk
        if int(dut.o_done.value) == 1:
            break
    value = sum(bit << (BYTE_BITS - 1 - i) for i, bit in enumerate(bits))
    check(value == BYTE_TX, f"transmitiu {value:#x}")

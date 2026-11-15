"""Receptor de uma lane: sincronismo, fase do byte e destravamento."""

import cocotb

from tests.python.unittests.MIPI import csi2
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MipiLaneDut

PAYLOAD = [0x11, 0xB8, 0x00, 0xFF, 0x5A, 0xA5, 0x3C]


async def start(dut: MipiLaneDut) -> None:
    """Zere as entradas, arme a lane e solte o reset.

    Parameters
    ----------
    dut : MipiLaneDut
        Projeto sob teste.
    """
    dut.i_arm.value = 1
    dut.i_bit_early.value = 0
    dut.i_bit_late.value = 0
    await bus.hold_reset(dut)
    await bus.cycles(dut, 2)


async def feed(dut: MipiLaneDut, bits: list[int], arm: int = 1) -> list[int]:
    """Envie os bits aos pares e colete os bytes entregues.

    Parameters
    ----------
    dut : MipiLaneDut
        Projeto sob teste.
    bits : list[int]
        Bits em ordem de tempo.
    arm : int
        Valor de i_arm durante o envio.

    Returns
    -------
    list[int]
        Os bytes entregues, na ordem.
    """
    got: list[int] = []
    dut.i_arm.value = arm
    # Cinco ciclos a mais esvaziam a latência da lane.
    pairs = csi2.to_pairs(bits) + [(0, 0)] * 6
    for early, late in pairs:
        dut.i_bit_early.value = early
        dut.i_bit_late.value = late
        await bus.cycles(dut, 1)
        if int(dut.o_valid.value):
            got.append(int(dut.o_byte.value))
    return got


@cocotb.test()
async def test_even_phase(dut: MipiLaneDut) -> None:
    """Com o sincronismo na fase par, os bytes saem alinhados."""
    await start(dut)
    got = await feed(dut, csi2.lane_bits(PAYLOAD, 24, 0))
    check(got[: len(PAYLOAD)] == PAYLOAD, f"bytes {got}")


@cocotb.test()
async def test_odd_phase(dut: MipiLaneDut) -> None:
    """Com um bit a mais, a lane acha a fase ímpar e alinha os bytes."""
    await start(dut)
    got = await feed(dut, csi2.lane_bits(PAYLOAD, 25, 0))
    check(got[: len(PAYLOAD)] == PAYLOAD, f"bytes {got}")


@cocotb.test()
async def test_every_bit_offset(dut: MipiLaneDut) -> None:
    """Qualquer deslocamento de zeros antes do sincronismo alinha."""
    await start(dut)
    for lead in range(16, 24):
        got = await feed(dut, csi2.lane_bits(PAYLOAD, lead, 0), arm=1)
        check(got[: len(PAYLOAD)] == PAYLOAD, f"lead {lead}: {got}")
        await feed(dut, [0] * 8, arm=0)
        check_equal(int(dut.o_locked.value), 0)


@cocotb.test()
async def test_preamble_required(dut: MipiLaneDut) -> None:
    """Sem os zeros antes, o byte B8 não trava a lane."""
    await start(dut)
    bits = [1, 0, 1, 1, 0, 1, 1, 1] + csi2.byte_bits(csi2.SYNC) + [0] * 40
    got = await feed(dut, bits)
    check_equal(len(got), 0)
    check_equal(int(dut.o_locked.value), 0)
    short = [0] * 4 + csi2.byte_bits(csi2.SYNC) + [0] * 40
    check_equal(len(await feed(dut, [1] * 8 + short)), 0)


@cocotb.test()
async def test_sync_byte_in_data_ignored(dut: MipiLaneDut) -> None:
    """Travada, a lane não busca outro sincronismo no meio dos dados."""
    await start(dut)
    data = [0x00, 0xB8, 0x00, 0xB8, 0x12]
    got = await feed(dut, csi2.lane_bits(data, 24, 0))
    check(got[: len(data)] == data, f"bytes {got}")


@cocotb.test()
async def test_disarm_unlocks(dut: MipiLaneDut) -> None:
    """Com i_arm em zero a lane destrava e trava de novo."""
    await start(dut)
    await feed(dut, csi2.lane_bits([0x01], 24, 0))
    check_equal(int(dut.o_locked.value), 1)
    await feed(dut, [0] * 4, arm=0)
    check_equal(int(dut.o_locked.value), 0)
    got = await feed(dut, csi2.lane_bits(PAYLOAD, 30, 0))
    check(got[: len(PAYLOAD)] == PAYLOAD, f"bytes {got}")
    await feed(dut, csi2.lane_bits([0x01], 24, 0))
    check_equal(int(dut.o_locked.value), 1)
    dut.i_rst.value = 1
    await bus.cycles(dut, 1)
    dut.i_rst.value = 0
    await bus.cycles(dut, 1)
    check_equal(int(dut.o_locked.value), 0)

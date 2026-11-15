"""Registradores do receptor MIPI: estado, eventos e ponteiro."""

import cocotb

from tests.python.unittests.MIPI.registers import (
    BUSY,
    CONFIG,
    CTRL,
    DT_RAW8,
    ENABLE,
    ERROR,
    ERROR_IRQ,
    ERRORS,
    FRAME_COUNT,
    FRAME_IRQ,
    GEOMETRY,
    INFO,
    LAST_FRAME,
    RD_ADDR,
    RD_DATA,
    READY,
    SEEN,
    START,
    STATUS,
)
from tests.python.utils import bus
from tests.python.utils.check import check_equal
from tests.python.utils.dut import MipiRegsDut

LINE_BYTES = 16
LINES = 4
DEPTH = LINE_BYTES * LINES // 4
COUNT_MAX = 255
INPUTS = (
    "i_seen",
    "i_done_tog",
    "i_cap_ok",
    "i_cap_lines",
    "i_cap_wc",
    "i_ecc_tog",
    "i_crc_tog",
    "i_drop_tog",
    "i_rd_data",
)


async def start(dut: MipiRegsDut) -> None:
    """Zere as entradas do outro domínio e reinicie o projeto.

    Parameters
    ----------
    dut : MipiRegsDut
        Projeto sob teste.
    """
    for name in INPUTS:
        getattr(dut, name).value = 0
    await bus.reset(dut)


async def toggle(dut: MipiRegsDut, name: str) -> None:
    """Inverta uma entrada de toggle e espere o efeito.

    Parameters
    ----------
    dut : MipiRegsDut
        Projeto sob teste.
    name : str
        Nome da entrada de toggle.
    """
    signal = getattr(dut, name)
    signal.value = 1 - int(signal.value)
    await bus.cycles(dut, 2)


async def finish(
    dut: MipiRegsDut, ok: int, lines: int = 0, wc: int = 0
) -> None:
    """Entregue o resultado de uma captura, como o toggle de fim.

    Parameters
    ----------
    dut : MipiRegsDut
        Projeto sob teste.
    ok : int
        Quadro completo.
    lines : int
        Linhas guardadas.
    wc : int
        Contagem de palavras da última linha.
    """
    dut.i_cap_ok.value = ok
    dut.i_cap_lines.value = lines
    dut.i_cap_wc.value = wc
    await toggle(dut, "i_done_tog")


@cocotb.test()
async def test_reset_values(dut: MipiRegsDut) -> None:
    """O reset deixa os valores documentados e a geometria certa."""
    await start(dut)
    check_equal(await bus.read(dut, CTRL), 0)
    check_equal(await bus.read(dut, STATUS), 0)
    check_equal(await bus.read(dut, FRAME_COUNT), 0)
    check_equal(await bus.read(dut, CONFIG), 0x0100 | DT_RAW8)
    check_equal(await bus.read(dut, GEOMETRY), LINES << 16 | LINE_BYTES)
    check_equal(await bus.read(dut, LAST_FRAME), 0)
    check_equal(await bus.read(dut, ERRORS), 0)
    check_equal(await bus.read(dut, INFO), 2)
    check_equal(await bus.read(dut, RD_ADDR), 0)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(int(dut.o_enable.value), 0)
    check_equal(int(dut.o_dt.value), DT_RAW8)
    check_equal(int(dut.o_y_step.value), 1)
    check_equal(await bus.read(dut, 15), 0)


@cocotb.test()
async def test_capture_cycle(dut: MipiRegsDut) -> None:
    """Início, fim, contagem, resultado, interrupção e limpeza."""
    await start(dut)
    await bus.write(dut, CTRL, START)
    idle_status = await bus.read(dut, STATUS)
    check_equal(idle_status & BUSY, 0)
    check_equal(int(dut.o_start_tog.value), 0)
    await bus.write(dut, CTRL, ENABLE | FRAME_IRQ)
    check_equal(int(dut.o_enable.value), 1)
    await bus.write(dut, CTRL, ENABLE | FRAME_IRQ | START)
    check_equal(int(dut.o_start_tog.value), 1)
    check_equal(await bus.read(dut, STATUS) & BUSY, BUSY)
    await bus.write(dut, CTRL, ENABLE | FRAME_IRQ | START)
    check_equal(int(dut.o_start_tog.value), 1)
    await finish(dut, 1, 3, 12)
    status = await bus.read(dut, STATUS)
    check_equal(status & (BUSY | READY | ERROR), READY)
    check_equal(await bus.read(dut, FRAME_COUNT), 1)
    check_equal(await bus.read(dut, LAST_FRAME), 12 << 16 | 3)
    check_equal(int(dut.o_irq.value), 1)
    await bus.write(dut, STATUS, READY)
    check_equal(await bus.read(dut, STATUS) & READY, 0)
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, CTRL, ENABLE | START)
    check_equal(int(dut.o_start_tog.value), 0)


@cocotb.test()
async def test_incomplete_frame_is_error(dut: MipiRegsDut) -> None:
    """Um quadro incompleto levanta o erro e não soma no contador."""
    await start(dut)
    await bus.write(dut, CTRL, ENABLE | ERROR_IRQ)
    await bus.write(dut, CTRL, ENABLE | ERROR_IRQ | START)
    await finish(dut, 0, 1, 8)
    check_equal(int(dut.o_irq.value), 1)
    status = await bus.read(dut, STATUS)
    check_equal(status & (BUSY | READY | ERROR), ERROR)
    check_equal(await bus.read(dut, FRAME_COUNT), 0)
    await bus.write(dut, STATUS, ERROR)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(await bus.read(dut, STATUS), 0)


@cocotb.test()
async def test_error_counters(dut: MipiRegsDut) -> None:
    """Os contadores somam, saturam em 255 e limpam por escrita."""
    await start(dut)
    for _ in range(2):
        await toggle(dut, "i_ecc_tog")
    await toggle(dut, "i_crc_tog")
    for _ in range(3):
        await toggle(dut, "i_drop_tog")
    check_equal(await bus.read(dut, ERRORS), 3 << 16 | 1 << 8 | 2)
    check_equal(await bus.read(dut, STATUS) & ERROR, ERROR)
    for _ in range(COUNT_MAX + 5):
        await toggle(dut, "i_crc_tog")
    check_equal(await bus.read(dut, ERRORS) >> 8 & 0xFF, COUNT_MAX)
    await bus.write(dut, ERRORS, 0)
    check_equal(await bus.read(dut, ERRORS), 0)
    await bus.write(dut, STATUS, ERROR)
    check_equal(await bus.read(dut, STATUS) & ERROR, 0)
    await toggle(dut, "i_drop_tog")
    check_equal(await bus.read(dut, STATUS) & ERROR, 0)


@cocotb.test()
async def test_seen_and_masks(dut: MipiRegsDut) -> None:
    """O estado de cabeçalho visto aparece, e as máscaras valem."""
    await start(dut)
    check_equal(await bus.read(dut, STATUS) & SEEN, 0)
    dut.i_seen.value = 1
    await bus.cycles(dut, 1)
    check_equal(await bus.read(dut, STATUS) & SEEN, SEEN)
    await toggle(dut, "i_ecc_tog")
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, CTRL, ERROR_IRQ)
    check_equal(int(dut.o_irq.value), 1)
    check_equal(await bus.read(dut, CTRL), ERROR_IRQ)


@cocotb.test()
async def test_config_locked_while_busy(dut: MipiRegsDut) -> None:
    """A configuração só muda parada, e o passo zero vale um."""
    await start(dut)
    await bus.write(dut, CONFIG, 0x0300 | 0x12)
    check_equal(await bus.read(dut, CONFIG), 0x0312)
    check_equal(int(dut.o_dt.value), 0x12)
    check_equal(int(dut.o_y_step.value), 3)
    await bus.write(dut, CONFIG, 0x00FF)
    check_equal(await bus.read(dut, CONFIG), 0x013F)
    await bus.write(dut, CTRL, ENABLE)
    await bus.write(dut, CTRL, ENABLE | START)
    await bus.write(dut, CONFIG, 0x0500 | 0x2A)
    check_equal(await bus.read(dut, CONFIG), 0x013F)
    await bus.write(dut, CTRL, 0)
    check_equal(await bus.read(dut, STATUS) & BUSY, 0)
    check_equal(int(dut.o_enable.value), 0)
    await bus.write(dut, CONFIG, 0x0500 | 0x2A)
    check_equal(await bus.read(dut, CONFIG), 0x052A)


@cocotb.test()
async def test_read_pointer(dut: MipiRegsDut) -> None:
    """O ponteiro avança, dá a volta e recusa valor fora da faixa."""
    await start(dut)
    dut.i_rd_data.value = 0xA5A55A5A
    await bus.write(dut, RD_ADDR, 5)
    check_equal(await bus.read(dut, RD_ADDR), 5)
    check_equal(int(dut.o_rd_addr.value), 5)
    check_equal(await bus.read(dut, RD_DATA), 0xA5A55A5A)
    check_equal(await bus.read(dut, RD_ADDR), 6)
    await bus.write(dut, RD_ADDR, DEPTH)
    check_equal(await bus.read(dut, RD_ADDR), 6)
    await bus.write(dut, RD_ADDR, DEPTH - 1)
    await bus.read(dut, RD_DATA)
    check_equal(await bus.read(dut, RD_ADDR), 0)

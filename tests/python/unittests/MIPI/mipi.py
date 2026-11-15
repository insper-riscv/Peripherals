"""Receptor MIPI completo: quadros, erros, recorte e leitura."""

import cocotb
from cocotb.clock import Clock
from cocotb.task import Task
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.MIPI import csi2
from tests.python.unittests.MIPI.registers import (
    BUSY,
    CONFIG,
    CTRL,
    DT_EMBEDDED,
    DT_RAW8,
    ENABLE,
    ERROR,
    ERROR_IRQ,
    ERRORS,
    FRAME_COUNT,
    FRAME_IRQ,
    GEOMETRY,
    LAST_FRAME,
    RD_ADDR,
    RD_DATA,
    READY,
    SEEN,
    START,
    STATUS,
)
from tests.python.utils import bus, polling
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MipiDut

SYS_NS = 10
MIPI_NS = 37
LINE_BYTES = 16
LINES = 6
WORDS = LINE_BYTES * LINES // 4
WAIT_LIMIT = 60000
GAP_CYCLES = 14
SKEW_STEP_BITS = 3


def line_data(frame: int, index: int, size: int = LINE_BYTES) -> bytes:
    """Gere os bytes de uma linha de teste.

    Parameters
    ----------
    frame : int
        Número do quadro, que muda o padrão.
    index : int
        Índice da linha.
    size : int
        Quantidade de bytes.

    Returns
    -------
    bytes
        Bytes que dependem do quadro, da linha e da posição.
    """
    return bytes(
        (frame * 91 + index * 29 + x * 7 + 1) & 0xFF for x in range(size)
    )


async def stream(dut: MipiDut, packets: list[bytes]) -> None:
    """Envie os pacotes em rajadas, um par de bits por lane e por ciclo.

    Cada pacote muda a defasagem e a fase das lanes, e entre as
    rajadas a linha fica em zeros.

    Parameters
    ----------
    dut : MipiDut
        Projeto sob teste.
    packets : list[bytes]
        Bytes de cada pacote.
    """
    lanes = len(dut.i_mipi_early)
    for number, packet in enumerate(packets):
        skew = tuple(
            (lane * number * SKEW_STEP_BITS + lane) % 7
            for lane in range(lanes)
        )
        cycles = csi2.burst(packet, lanes, 24 + number % 3, skew)
        cycles += [[(0, 0)] * lanes] * GAP_CYCLES
        for pairs in cycles:
            await RisingEdge(dut.i_mipi_clk)
            await Timer(1, unit="ns")
            dut.i_mipi_early.value = sum(
                early << lane for lane, (early, _) in enumerate(pairs)
            )
            dut.i_mipi_late.value = sum(
                late << lane for lane, (_, late) in enumerate(pairs)
            )
    await RisingEdge(dut.i_mipi_clk)
    dut.i_mipi_early.value = 0
    dut.i_mipi_late.value = 0


async def start(dut: MipiDut) -> None:
    """Inicie os clocks, solte o reset e deixe as lanes em zero.

    Parameters
    ----------
    dut : MipiDut
        Projeto sob teste.
    """
    dut.i_mipi_early.value = 0
    dut.i_mipi_late.value = 0
    cocotb.start_soon(Clock(dut.i_mipi_clk, MIPI_NS, unit="ns").start())
    await bus.reset(dut, hold=10, period_ns=SYS_NS)


async def wait_status(dut: MipiDut, mask: int, value: int) -> int:
    """Leia o estado até os bits de mask valerem value.

    Parameters
    ----------
    dut : MipiDut
        Projeto sob teste.
    mask : int
        Bits do estado observados.
    value : int
        Valor esperado desses bits.

    Returns
    -------
    int
        O estado lido quando a condição vale.
    """
    return await polling.wait_status(dut, STATUS, mask, value, WAIT_LIMIT)


async def read_frame(dut: MipiDut) -> list[bytes]:
    """Leia a memória do quadro inteira e separe as linhas.

    Parameters
    ----------
    dut : MipiDut
        Projeto sob teste.

    Returns
    -------
    list[bytes]
        Os bytes de cada linha da memória.
    """
    await bus.write(dut, RD_ADDR, 0)
    data = b""
    for _ in range(WORDS):
        data += (await bus.read(dut, RD_DATA)).to_bytes(4, "little")
    return [
        data[start:][:LINE_BYTES] for start in range(0, len(data), LINE_BYTES)
    ]


async def capture(dut: MipiDut, packets: list[bytes]) -> Task[None]:
    """Habilite o receptor, peça a captura e comece o envio dos pacotes.

    Parameters
    ----------
    dut : MipiDut
        Projeto sob teste.
    packets : list[bytes]
        Pacotes do quadro.

    Returns
    -------
    Task[None]
        A tarefa que envia os pacotes.
    """
    await bus.write(dut, CTRL, ENABLE | FRAME_IRQ | ERROR_IRQ)
    await Timer(1, unit="us")
    await bus.write(dut, CTRL, ENABLE | FRAME_IRQ | ERROR_IRQ | START)
    return cocotb.start_soon(stream(dut, packets))


@cocotb.test()
async def test_frame(dut: MipiDut) -> None:
    """Um quadro inteiro chega pelas lanes e é lido pelo barramento."""
    await start(dut)
    check_equal(await bus.read(dut, GEOMETRY), LINES << 16 | LINE_BYTES)
    lines = [line_data(1, index) for index in range(LINES)]
    task = await capture(dut, csi2.frame_packets(lines))
    status = await wait_status(dut, BUSY, 0)
    check(status & READY != 0, f"quadro não ficou pronto: {status:#x}")
    check_equal(status & ERROR, 0)
    check(status & SEEN != 0, "cabeçalho visto")
    check_equal(int(dut.o_irq.value), 1)
    check_equal(await bus.read(dut, FRAME_COUNT), 1)
    check_equal(await bus.read(dut, LAST_FRAME), LINE_BYTES << 16 | LINES)
    check_equal(await bus.read(dut, ERRORS), 0)
    got = await read_frame(dut)
    check(got == lines, f"quadro lido {got}")
    await task


@cocotb.test()
async def test_crop_and_embedded_data(dut: MipiDut) -> None:
    """Linhas largas são recortadas e dados embutidos ignorados."""
    await start(dut)
    wide = [line_data(2, index, 20) for index in range(LINES + 2)]
    packets = [csi2.short_packet(0x00, 2)]
    packets.append(csi2.long_packet(DT_EMBEDDED, bytes(range(8))))
    packets += [csi2.long_packet(DT_RAW8, line) for line in wide]
    packets += [csi2.short_packet(0x01, 2)]
    task = await capture(dut, packets)
    status = await wait_status(dut, BUSY, 0)
    check(status & READY != 0, f"estado {status:#x}")
    check_equal(await bus.read(dut, LAST_FRAME), 20 << 16 | LINES)
    drops = await bus.read(dut, ERRORS) >> 16 & 0xFF
    check_equal(drops, LINES + 2)
    got = await read_frame(dut)
    check(got == [line[:LINE_BYTES] for line in wide[:LINES]], f"{got}")
    await task


@cocotb.test()
async def test_line_step(dut: MipiDut) -> None:
    """Com passo de duas linhas o quadro guarda uma sim, outra não."""
    await start(dut)
    await bus.write(dut, CONFIG, 0x0200 | DT_RAW8)
    lines = [line_data(3, index) for index in range(2 * LINES)]
    task = await capture(dut, csi2.frame_packets(lines))
    await wait_status(dut, BUSY, 0)
    got = await read_frame(dut)
    check(got == lines[::2], f"{got}")
    await task


@cocotb.test()
async def test_errors_are_counted(dut: MipiDut) -> None:
    """CRC e ECC errados contam, o erro sobe e o quadro segue."""
    await start(dut)
    lines = [line_data(4, index) for index in range(LINES)]
    packets = [csi2.short_packet(0x00, 4)]
    packets.append(csi2.long_packet(DT_RAW8, lines[0], bad_crc=1))
    good = csi2.long_packet(DT_RAW8, lines[1])
    packets.append(good[:3] + bytes([good[3] ^ 0x04]) + good[4:])
    packets += [csi2.long_packet(DT_RAW8, line) for line in lines[2:]]
    packets.append(csi2.short_packet(0x01, 4))
    task = await capture(dut, packets)
    status = await wait_status(dut, BUSY, 0)
    check(status & READY != 0, f"estado {status:#x}")
    check(status & ERROR != 0, "o erro não subiu")
    check_equal(await bus.read(dut, ERRORS), 1 << 8 | 1)
    check_equal(
        await bus.read(dut, LAST_FRAME), LINE_BYTES << 16 | (LINES - 1)
    )
    got = await read_frame(dut)
    check(got[0] == lines[0], "a linha com CRC errado é guardada")
    check(got[1:5] == lines[2:], "a linha com ECC errado se perde")
    await bus.write(dut, STATUS, READY | ERROR)
    check_equal(await bus.read(dut, STATUS) & (READY | ERROR), 0)
    check_equal(int(dut.o_irq.value), 0)
    await task


@cocotb.test()
async def test_two_frames(dut: MipiDut) -> None:
    """Dois quadros seguidos entram um por vez e o contador soma."""
    await start(dut)
    for frame in (5, 6):
        lines = [line_data(frame, index) for index in range(LINES)]
        task = await capture(dut, csi2.frame_packets(lines, frame=frame))
        await wait_status(dut, BUSY, 0)
        check_equal(await bus.read(dut, FRAME_COUNT), frame - 4)
        check(await read_frame(dut) == lines, f"quadro {frame}")
        await bus.write(dut, STATUS, READY)
        await task


@cocotb.test()
async def test_disabled_receiver(dut: MipiDut) -> None:
    """Desabilitado ignora a linha; habilitado vê o cabeçalho."""
    await start(dut)
    task = cocotb.start_soon(stream(dut, [csi2.short_packet(0x00, 1)]))
    await task
    await Timer(1, unit="us")
    check_equal(await bus.read(dut, STATUS) & SEEN, 0)
    await bus.write(dut, CTRL, ENABLE)
    await Timer(1, unit="us")
    task = cocotb.start_soon(stream(dut, [csi2.short_packet(0x00, 1)]))
    await task
    await Timer(1, unit="us")
    check_equal(await bus.read(dut, STATUS) & SEEN, SEEN)
    await bus.write(dut, CTRL, 0)
    await Timer(1, unit="us")
    check_equal(await bus.read(dut, STATUS) & SEEN, 0)

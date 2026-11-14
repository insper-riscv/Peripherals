"""HDMI: registradores, imagem, temporização e interrupções."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.HDMI import hdmi_bench as bench
from tests.python.unittests.HDMI.hdmi_bench import TxDut
from tests.python.unittests.HDMI.monitor import (
    EdgeLog,
    check_edges,
    log_edges,
)
from tests.python.utils.check import check

FRAME_LIMIT = 5
IRQ_ALL = 0b11
PIXEL_PERIOD_NS = 40


async def wait_frames(dut: TxDut, count: int) -> None:
    """Espera quadros completos do modo, contados no clock de pixel.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    count : int
        Número de quadros.
    """
    timing = bench.timing_of(dut)
    for _ in range(count * timing.frame_clocks):
        await RisingEdge(dut.i_pixel_clk)
    await Timer(1, unit="ns")


@cocotb.test()
async def test_register_map(dut: TxDut) -> None:
    """Os registradores leem modo, geometria e estado esperados."""
    await bench.start(dut)
    geo = await bench.read_geometry(dut)
    timing = geo.timing
    mode = await bench.read(dut, bench.HDMI_MODE)
    check(
        mode >> 8 == int(timing.h_positive) | (int(timing.v_positive) << 1),
        f"polaridades no modo: {mode:#x}",
    )
    check(await bench.read(dut, bench.PIXEL_KHZ) > 0, "clock de pixel em kHz")
    check(await bench.read(dut, bench.CTRL) == 0, "exibição desligada")
    check(await bench.read(dut, bench.IRQ_EN) == 0, "interrupções desligadas")
    check(await bench.read(dut, bench.IRQ_PEND) == 0, "nada pendente")
    for address in (15, 16, 100, 255):
        check(await bench.read(dut, address) == 0, f"palavra {address}")
    status = await bench.read(dut, bench.HDMI_STATUS)
    check(status & bench.ST_INT == 0, "pino de interrupção em repouso")
    for address in (bench.HDMI_MODE, bench.HDMI_STATUS, bench.PIXEL_KHZ):
        before = await bench.read(dut, address)
        await bench.write(dut, address, 0xFFFFFFFF)
        check(
            await bench.read(dut, address) == before,
            f"somente leitura {address}",
        )
    await bench.write(dut, bench.CTRL, 1)
    check(await bench.read(dut, bench.CTRL) == 1, "exibição ligada")
    await bench.write(dut, bench.IRQ_EN, 0xFFFFFFFF)
    check(
        await bench.read(dut, bench.IRQ_EN) == IRQ_ALL,
        "só dois bits de máscara",
    )


@cocotb.test()
async def test_output_timing(dut: TxDut) -> None:
    """HS, VS e DE têm a largura, a polaridade e os pórticos do modo."""
    tasks = await bench.start(dut, release=False)
    timing = bench.timing_of(dut)
    log = EdgeLog()
    cocotb.start_soon(log_edges(dut, log))
    dut.i_rst.value = 0
    await wait_frames(dut, 2)
    for _ in range(timing.frame_clocks // 2):
        await RisingEdge(dut.i_pixel_clk)
    check_edges(log, timing, bench.SMALL_PIXEL_PS)
    del tasks


@cocotb.test()
async def test_every_pixel_matches_framebuffer(dut: TxDut) -> None:
    """Cada pixel de dois quadros confere com o framebuffer."""
    await bench.start(dut)
    geo = await bench.read_geometry(dut)
    image = bench.Image(geo, seed=7)
    await bench.load_image(dut, image)
    await bench.write(dut, bench.CTRL, 1)
    samples = await bench.sample_for(dut, geo.timing, FRAME_LIMIT)
    bench.check_samples(samples, image, lit=True)
    await bench.write(dut, bench.CTRL, 0)
    await wait_frames(dut, 1)
    samples = await bench.sample_for(dut, geo.timing, FRAME_LIMIT)
    bench.check_samples(samples, image, lit=False)
    await bench.write(dut, bench.CTRL, 1)
    await wait_frames(dut, 1)
    samples = await bench.sample_for(dut, geo.timing, FRAME_LIMIT)
    bench.check_samples(samples, image, lit=True)


@cocotb.test()
async def test_frame_interrupt(dut: TxDut) -> None:
    """O fim de quadro fica pendente, sobe o_irq e é limpo."""
    await bench.start(dut)
    geo = await bench.read_geometry(dut)
    check(int(dut.o_irq.value) == 0, "sem interrupção no reset")
    await wait_frames(dut, 2)
    pending = await bench.read(dut, bench.IRQ_PEND)
    check(pending & bench.IRQ_FRAME != 0, "o fim de quadro fica pendente")
    check(int(dut.o_irq.value) == 0, "sem máscara não há interrupção")
    await bench.write(dut, bench.IRQ_PEND, bench.IRQ_FRAME)
    await bench.write(dut, bench.IRQ_EN, bench.IRQ_FRAME)
    count_before = await bench.read(dut, bench.FRAME_COUNT)
    for _ in range(2 * geo.timing.frame_clocks):
        await RisingEdge(dut.i_pixel_clk)
        if int(dut.o_irq.value):
            break
    await Timer(1, unit="ns")
    check(int(dut.o_irq.value) == 1, "a interrupção de fim de quadro sobe")
    await bench.write(dut, bench.IRQ_PEND, bench.IRQ_FRAME)
    check(await bench.read(dut, bench.IRQ_PEND) == 0, "escrever 1 limpa")
    check(int(dut.o_irq.value) == 0, "a interrupção cai")
    check(
        await bench.read(dut, bench.FRAME_COUNT) > count_before,
        "o contador de quadros avança",
    )
    await bench.write(dut, bench.IRQ_PEND, 0)
    await wait_frames(dut, 1)
    check(int(dut.o_irq.value) == 1, "o próximo quadro interrompe de novo")


@cocotb.test()
async def test_transmitter_int_pin(dut: TxDut) -> None:
    """O pino do transmissor é estado, evento e interrupção."""
    await bench.start(dut)
    await bench.write(dut, bench.IRQ_PEND, bench.IRQ_FRAME | bench.IRQ_INT)
    await bench.write(dut, bench.IRQ_EN, bench.IRQ_INT)
    check(int(dut.o_irq.value) == 0, "pino em repouso")
    dut.i_tx_int.value = 0
    await bench.cycles(dut, 6)
    status = await bench.read(dut, bench.HDMI_STATUS)
    check(status & bench.ST_INT != 0, "estado do pino ativo")
    check(int(dut.o_irq.value) == 1, "a interrupção sobe")
    pending = await bench.read(dut, bench.IRQ_PEND)
    check(pending & bench.IRQ_INT != 0, "pendência do pino")
    await bench.write(dut, bench.IRQ_PEND, bench.IRQ_INT)
    check(int(dut.o_irq.value) == 0, "limpa com o pino ainda ativo")
    await bench.cycles(dut, 6)
    check(
        await bench.read(dut, bench.IRQ_PEND) & bench.IRQ_INT == 0,
        "só a borda de ativação gera evento",
    )
    dut.i_tx_int.value = 1
    await bench.cycles(dut, 6)
    check(
        await bench.read(dut, bench.HDMI_STATUS) & bench.ST_INT == 0,
        "estado do pino em repouso",
    )
    dut.i_tx_int.value = 0
    await bench.cycles(dut, 6)
    check(int(dut.o_irq.value) == 1, "uma nova ativação interrompe")

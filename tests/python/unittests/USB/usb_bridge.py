"""Ponte USB: registradores, temporização, protocolo e interrupções."""

import cocotb

from tests.python.unittests.USB import registers as reg
from tests.python.unittests.USB.driver import (
    chip_read,
    chip_write,
    read_register,
    settle,
    start,
    transactions,
    wait_idle,
    write_register,
)
from tests.python.unittests.USB.model import (
    DC_ID,
    DC_ID_CMD,
    HC_ID,
    HC_ID_CMD,
)
from tests.python.unittests.USB.signals import UsbDut
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.rng import seeded

SEED = 0x1362
RANDOM_OPS = 150
ACTIVE_HIGH_INT: bool = True
MIN_READ_PULSE = 3
WRITE_SHARE = 0.5


def pack_timing(setup: int, pulse: int, recovery: int) -> int:
    """Monta o valor do registrador de temporização.

    Parameters
    ----------
    setup : int
        Ciclos de preparação.
    pulse : int
        Ciclos do pulso.
    recovery : int
        Ciclos de recuperação.

    Returns
    -------
    int
        O valor do registrador.
    """
    return setup | (pulse << 8) | (recovery << 16)


def level(raw: int) -> int:
    """Aplica a polaridade do teste ao nível do pino.

    Parameters
    ----------
    raw : int
        Valor ativo em '1' que o teste quer apresentar ao programa.

    Returns
    -------
    int
        O valor a aplicar no pino.
    """
    return raw if ACTIVE_HIGH_INT else raw ^ 0b11


@cocotb.test()
async def reset_state(dut: UsbDut) -> None:
    """Depois do reset o chip está em reset e os pinos estão ociosos."""
    model = await start(dut)
    check_equal(await bus.read(dut, reg.CTRL), reg.CTRL_CHIP_RESET)
    check_equal(int(dut.o_otg_rst_n.value), 0)
    check_equal(int(dut.o_otg_cs_n.value), 1)
    check_equal(int(dut.o_otg_rd_n.value), 1)
    check_equal(int(dut.o_otg_wr_n.value), 1)
    check_equal(int(dut.o_otg_data_oe.value), 0)
    check_equal(int(dut.o_otg_dack.value), 0)
    check_equal(int(dut.o_irq.value), 0)
    check_equal(await bus.read(dut, reg.STATUS), 0)
    check_equal(await bus.read(dut, reg.IRQ_MASK), 0)
    check_equal(
        await bus.read(dut, reg.TIMING),
        pack_timing(
            reg.DEFAULT_SETUP, reg.DEFAULT_PULSE, reg.DEFAULT_RECOVERY
        ),
    )
    model.stop()


@cocotb.test()
async def chip_reset_and_dack(dut: UsbDut) -> None:
    """O reset do chip e o reconhecimento de DMA seguem o controle."""
    model = await start(dut)
    await bus.write(dut, reg.CTRL, 0)
    check_equal(int(dut.o_otg_rst_n.value), 1)
    check_equal(await bus.read(dut, reg.CTRL), 0)
    await bus.write(dut, reg.CTRL, reg.CTRL_DACK)
    check_equal(int(dut.o_otg_dack.value), 1)
    check_equal(int(dut.o_otg_rst_n.value), 1)
    await bus.write(dut, reg.CTRL, reg.CTRL_CHIP_RESET)
    check_equal(int(dut.o_otg_rst_n.value), 0)
    check_equal(int(dut.o_otg_dack.value), 0)
    model.stop()


@cocotb.test()
async def read_chip_ids(dut: UsbDut) -> None:
    """O programa lê o identificador dos dois controladores."""
    model = await start(dut)
    check_equal(await read_register(dut, 0, HC_ID_CMD), HC_ID)
    check_equal(await read_register(dut, 1, DC_ID_CMD), DC_ID)
    check(not model.contention, "o barramento de dados teve contenção")
    model.stop()


@cocotb.test()
async def write_roundtrip(dut: UsbDut) -> None:
    """Uma escrita de registrador chega ao chip e volta numa leitura."""
    model = await start(dut)
    await write_register(dut, 0, 0x30, 0xBEEF)
    await write_register(dut, 1, 0x31, 0x1234)
    check_equal(model.regs[0][0x30], 0xBEEF)
    check_equal(model.regs[1][0x31], 0x1234)
    check_equal(await read_register(dut, 0, 0x30), 0xBEEF)
    check_equal(await read_register(dut, 1, 0x31), 0x1234)
    check_equal(await read_register(dut, 0, 0x31), 0)
    check_equal(await bus.read(dut, reg.HC_DATA), 0)
    check(not model.contention, "o barramento de dados teve contenção")
    model.stop()


@cocotb.test()
async def upper_bits_ignored(dut: UsbDut) -> None:
    """Só os 16 bits baixos do dado de escrita vão ao chip."""
    model = await start(dut)
    await chip_write(dut, reg.HC_CMD, 0xABCD_0040)
    check_equal(model.command[0], 0x0040)
    model.stop()


@cocotb.test()
async def pin_timing(dut: UsbDut) -> None:
    """Preparação, pulso, retenção e recuperação seguem o campo."""
    model = await start(dut)
    configs = ((1, 1, 1), (3, 5, 7), (2, 6, 4), (0, 0, 0), (9, 3, 2))
    for setup, pulse, recovery in configs:
        await bus.write(dut, reg.TIMING, pack_timing(setup, pulse, recovery))
        check_equal(
            await bus.read(dut, reg.TIMING),
            pack_timing(setup, pulse, recovery),
        )
        model.log.clear()
        await chip_write(dut, reg.HC_CMD, HC_ID_CMD)
        value = await chip_read(dut, reg.HC_DATA)
        await settle(dut, recovery + 3)
        seen = transactions(model.log)
        check_equal(len(seen), 2)
        for access in seen:
            check_equal(access.setup, max(setup, 1))
            check_equal(access.pulse, max(pulse, 1))
            check_equal(access.hold, 1)
        check_equal(seen[0].is_read, 0)
        check_equal(seen[0].addr, 1)
        check_equal(seen[0].data, HC_ID_CMD)
        check_equal(seen[1].is_read, 1)
        check_equal(seen[1].addr, 0)
        check(seen[1].gap >= recovery, "recuperação curta demais")
        if pulse >= MIN_READ_PULSE:
            check_equal(value, HC_ID)
    check(not model.contention, "o barramento de dados teve contenção")
    model.stop()


@cocotb.test()
async def short_pulse_read_misses(dut: UsbDut) -> None:
    """Com pulso menor que três ciclos o dado ainda não chegou."""
    model = await start(dut)
    await bus.write(dut, reg.TIMING, pack_timing(1, 2, 1))
    await chip_write(dut, reg.HC_CMD, HC_ID_CMD)
    check(await chip_read(dut, reg.HC_DATA) != HC_ID, "leu cedo demais")
    await bus.write(dut, reg.TIMING, pack_timing(1, 3, 1))
    check_equal(await chip_read(dut, reg.HC_DATA), HC_ID)
    model.stop()


@cocotb.test()
async def busy_and_error(dut: UsbDut) -> None:
    """Um pedido com a ponte ocupada é descartado e marca o erro."""
    model = await start(dut)
    await bus.write(dut, reg.HC_CMD, 0x40)
    status = await bus.read(dut, reg.STATUS)
    check(bool(status & reg.STATUS_BUSY), "deveria estar ocupada")
    check(not status & reg.STATUS_ERROR, "erro cedo demais")
    await bus.write(dut, reg.HC_CMD, 0x41)
    await bus.read(dut, reg.HC_DATA)
    await wait_idle(dut)
    check(bool(await bus.read(dut, reg.STATUS) & reg.STATUS_ERROR), "sem erro")
    check(model.writes == [(1, 0x40)], "só o primeiro acesso chega ao chip")
    await bus.write(dut, reg.STATUS, reg.STATUS_BUSY)
    check(bool(await bus.read(dut, reg.STATUS) & reg.STATUS_ERROR), "limpou")
    await bus.write(dut, reg.STATUS, reg.STATUS_ERROR)
    check_equal(await bus.read(dut, reg.STATUS), 0)
    model.stop()


async def check_interrupts(dut: UsbDut) -> None:
    """Confere as interrupções do chip no estado e na máscara.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.
    """
    model = await start(dut)
    steps = (
        (0b00, 0b00, 0, 0),
        (0b10, 0b00, reg.STATUS_INT1, 0),
        (0b10, 0b01, reg.STATUS_INT1, 0),
        (0b10, 0b10, reg.STATUS_INT1, 1),
        (0b01, 0b10, reg.STATUS_INT0, 0),
        (0b01, 0b11, reg.STATUS_INT0, 1),
        (0b00, 0b11, 0, 0),
    )
    for pins, mask, status, irq in steps:
        dut.i_otg_int.value = level(pins)
        await settle(dut, 4)
        await bus.write(dut, reg.IRQ_MASK, mask)
        check_equal(await bus.read(dut, reg.IRQ_MASK), mask)
        check_equal(await bus.read(dut, reg.STATUS), status)
        check_equal(int(dut.o_irq.value), irq)
    model.stop()


@cocotb.test()
async def interrupts(dut: UsbDut) -> None:
    """As interrupções do chip aparecem no estado e na máscara."""
    await check_interrupts(dut)


@cocotb.test()
async def dma_request(dut: UsbDut) -> None:
    """O pedido de DMA do dispositivo aparece no estado."""
    model = await start(dut)
    dut.i_otg_dreq.value = 1
    await settle(dut, 4)
    check_equal(await bus.read(dut, reg.STATUS), reg.STATUS_DREQ)
    dut.i_otg_dreq.value = 0
    await settle(dut, 4)
    check_equal(await bus.read(dut, reg.STATUS), 0)
    model.stop()


@cocotb.test()
async def random_traffic(dut: UsbDut) -> None:
    """Acessos aleatórios com temporização aleatória batem."""
    model = await start(dut)
    rng = seeded(SEED)
    expected: list[dict[int, int]] = [dict(r) for r in model.regs]
    for _ in range(RANDOM_OPS):
        pulse = rng.randint(3, 9)
        await bus.write(
            dut,
            reg.TIMING,
            pack_timing(rng.randint(0, 5), pulse, rng.randint(0, 5)),
        )
        controller = rng.randint(0, 1)
        command = rng.randint(0x40, 0x4F)
        if rng.random() < WRITE_SHARE:
            value = rng.randint(0, 0xFFFF)
            await write_register(dut, controller, command, value)
            expected[controller][command] = value
        else:
            got = await read_register(dut, controller, command)
            check_equal(got, expected[controller].get(command, 0))
    check(not model.contention, "o barramento de dados teve contenção")
    model.stop()

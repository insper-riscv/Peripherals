"""ADXL345: configuração, leitura dos eixos, INT1 e interrupção.

Um modelo do acelerômetro (``Adxl345Model``, com as suposições marcadas
em ``adxl345_model``) liga-se aos pinos de SPI e a INT1. O teste roda
com o fio de dados compartilhado e com os quatro fios, conforme o
parâmetro ``THREE_WIRE``, e confere a sequência de configuração, os
eixos com sinal, a leitura por tempo e por INT1 e a interrupção.
"""

import cocotb

from tests.python.utils import bus, polling
from tests.python.utils.adxl345_model import (
    DEVID_VALUE,
    REG_BW_RATE,
    REG_DATA_FORMAT,
    REG_INT_ENABLE,
    REG_POWER_CTL,
    Adxl345Model,
)
from tests.python.utils.check import check
from tests.python.utils.dut import Adxl345Dut
from tests.python.utils.spi_slave import Bit, Wires

X_AXIS, Y_AXIS, Z_AXIS, STATUS, CONTROL, PERIOD, DEVID, DIVIDER = range(8)
BUSY = 1 << 0
SAMPLE = 1 << 1
VALID = 1 << 2
CONFIGURED = 1 << 3
ENABLE = 1 << 0
IRQ_ENABLE = 1 << 1
FULL_RES = 1 << 4
USE_INT1 = 1 << 5
RANGE_SHIFT = 2
RATE_SHIFT = 8
RATE_100_HZ = 0xA
RATE_800_HZ = 0xD
LIMIT = 20000
ONE_G = 256
FIRST_AXES = (-3, 5, ONE_G)
EXTREME_AXES = (-4096, 4095, -1)
INT1_AXES = (10, 20, 30)
CONFIG_FRAMES = 5
RANGE_16G = 3
SPI_BIT = 0x40
MEASURE = 0x08
DEFAULT_PERIOD = 600
CLOCK_HZ = 4_000_000


async def setup(dut: Adxl345Dut) -> Adxl345Model:
    """Reinicie o controlador e ligue o acelerômetro simulado.

    Parameters
    ----------
    dut : Adxl345Dut
        Controlador exercitado pelo teste.

    Returns
    -------
    Adxl345Model
        Acelerômetro ligado aos pinos.
    """
    dut.i_adxl_miso.value = 1
    dut.i_adxl_int1.value = 0
    await bus.reset(dut)
    pins = Wires(
        dut.o_adxl_sclk,
        dut.o_adxl_mosi,
        dut.i_adxl_miso,
        Bit(dut.o_adxl_cs_n),
    )
    three_wire = bool(int(dut.three_wire.value))
    model = Adxl345Model(pins, dut.o_adxl_mosi_oe, dut.i_adxl_int1, three_wire)
    model.start()
    return model


async def wait_status(dut: Adxl345Dut, mask: int, value: int) -> int:
    """Leia STATUS até os bits de ``mask`` valerem ``value``.

    Parameters
    ----------
    dut : Adxl345Dut
        Controlador exercitado pelo teste.
    mask : int
        Bits observados.
    value : int
        Valor esperado dos bits observados.

    Returns
    -------
    int
        Último valor de STATUS lido.

    Raises
    ------
    AssertionError
        Se a condição não ocorrer dentro do limite.
    """
    return await polling.wait_status(dut, STATUS, mask, value, LIMIT)


def signed(value: int) -> int:
    """Interprete uma palavra de 32 bits como inteiro com sinal.

    Parameters
    ----------
    value : int
        Palavra lida.

    Returns
    -------
    int
        Valor com sinal.
    """
    return value - (1 << 32) if value & (1 << 31) else value


@cocotb.test()
async def test_reset_values(dut: Adxl345Dut) -> None:
    """O reset deixa o controlador desligado e os pinos em repouso."""
    await setup(dut)
    await bus.cycles(dut, 5)
    check(await bus.read(dut, STATUS) == 0, "STATUS")
    check(await bus.read(dut, CONTROL) == RATE_100_HZ << RATE_SHIFT, "CONTROL")
    check(await bus.read(dut, PERIOD) == DEFAULT_PERIOD, "PERIOD")
    check(int(dut.o_adxl_cs_n.value) == 1, "CS alto")
    check(int(dut.o_adxl_sclk.value) == 1, "SCLK em repouso alto")
    check(int(dut.o_irq.value) == 0, "sem interrupção")


@cocotb.test()
async def test_configuration_sequence(dut: Adxl345Dut) -> None:
    """ENABLE lê DEVID e escreve os quatro registradores do chip."""
    model = await setup(dut)
    value = ENABLE | (2 << RANGE_SHIFT) | FULL_RES | RATE_800_HZ << RATE_SHIFT
    await bus.write(dut, CONTROL, value)
    await wait_status(dut, CONFIGURED, CONFIGURED)
    spi = SPI_BIT if model.three_wire else 0
    want = [
        (REG_BW_RATE, RATE_800_HZ),
        (REG_DATA_FORMAT, spi | 0x08 | 2),
        (REG_INT_ENABLE, 0x80),
        (REG_POWER_CTL, MEASURE),
    ]
    check(model.writes == want, f"{model.writes}")
    check(await bus.read(dut, DEVID) == DEVID_VALUE, "DEVID lido")
    check(not model.errors, f"{model.errors}")


@cocotb.test()
async def test_axes_by_time(dut: Adxl345Dut) -> None:
    """A leitura periódica traz X, Y e Z com sinal, 1 g no eixo Z."""
    model = await setup(dut)
    await bus.write(dut, PERIOD, 400)
    await bus.write(dut, CONTROL, ENABLE | RATE_100_HZ << RATE_SHIFT)
    model.set_axes(*FIRST_AXES)
    await wait_status(dut, SAMPLE, SAMPLE)
    check(signed(await bus.read(dut, X_AXIS)) == FIRST_AXES[0], "X")
    check(signed(await bus.read(dut, Y_AXIS)) == FIRST_AXES[1], "Y")
    check(signed(await bus.read(dut, Z_AXIS)) == ONE_G, "Z de 1 g")
    check(bool(await bus.read(dut, STATUS) & VALID), "VALID")
    await bus.write(dut, STATUS, SAMPLE)
    check(await bus.read(dut, STATUS) & SAMPLE == 0, "W1C limpa SAMPLE")
    model.set_axes(*EXTREME_AXES)
    await wait_status(dut, SAMPLE, SAMPLE)
    check(
        signed(await bus.read(dut, X_AXIS)) == EXTREME_AXES[0], "X de 13 bits"
    )
    check(
        signed(await bus.read(dut, Y_AXIS)) == EXTREME_AXES[1], "Y de 13 bits"
    )
    check(signed(await bus.read(dut, Z_AXIS)) == -1, "Z negativo")
    check(not model.errors, f"{model.errors}")


@cocotb.test()
async def test_read_by_int1(dut: Adxl345Dut) -> None:
    """Com USE_INT1 a leitura só acontece com o dado pronto."""
    model = await setup(dut)
    await bus.write(
        dut, CONTROL, ENABLE | USE_INT1 | RATE_100_HZ << RATE_SHIFT
    )
    await wait_status(dut, CONFIGURED, CONFIGURED)
    await bus.cycles(dut, 1500)
    check(await bus.read(dut, STATUS) & SAMPLE == 0, "sem INT1 não lê")
    check(len(model.frames) == CONFIG_FRAMES, f"{model.frames}")
    model.set_axes(*INT1_AXES)
    await wait_status(dut, SAMPLE, SAMPLE)
    check(
        signed(await bus.read(dut, Z_AXIS)) == INT1_AXES[2], "Z lido por INT1"
    )
    check(int(dut.i_adxl_int1.value) == 0, "o modelo desliga INT1")


@cocotb.test()
async def test_interrupt_and_reconfiguration(dut: Adxl345Dut) -> None:
    """A interrupção segue SAMPLE e CONTROL reconfigura."""
    model = await setup(dut)
    await bus.write(dut, PERIOD, 400)
    await bus.write(dut, CONTROL, ENABLE | IRQ_ENABLE)
    model.set_axes(1, 2, 3)
    await wait_status(dut, SAMPLE, SAMPLE)
    check(int(dut.o_irq.value) == 1, "interrupção de amostra")
    await bus.write(dut, STATUS, SAMPLE)
    check(int(dut.o_irq.value) == 0, "limpa com W1C")
    writes = len(model.writes)
    await bus.write(dut, CONTROL, ENABLE | (RANGE_16G << RANGE_SHIFT))
    await wait_status(dut, CONFIGURED, CONFIGURED)
    await bus.cycles(dut, 3000)
    check(len(model.writes) == 2 * writes, "a configuração se repete")
    last_format = [v for a, v in model.writes if a == REG_DATA_FORMAT][-1]
    check(last_format & RANGE_16G == RANGE_16G, f"faixa nova {last_format:#x}")
    check(not model.errors, f"{model.errors}")

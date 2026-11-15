"""ADXL345 por I2C: configuração, eixos, interrupções e NACK.

Um modelo do acelerômetro (``Adxl345I2cModel``, com as suposições
marcadas em ``adxl345_i2c_model``) liga-se às linhas SCL e SDA e aos
pinos INT1 e INT2. O teste roda com SDO em nível baixo (endereço 0x53)
e em nível alto (0x1D), conforme o parâmetro ``ADDRESS_SELECT_HIGH``, e
confere a sequência de configuração, os eixos com sinal, a leitura por
tempo e por cada pino de interrupção, a interrupção e o NACK.
"""

import cocotb

from tests.python.unittests.ADXL345.adxl345 import (
    CONFIGURED,
    CONTROL,
    DEFAULT_PERIOD,
    DEVID,
    DIVIDER,
    ENABLE,
    EXTREME_AXES,
    FIRST_AXES,
    FULL_RES,
    IRQ_ENABLE,
    MEASURE,
    ONE_G,
    PERIOD,
    RANGE_16G,
    RANGE_SHIFT,
    RATE_100_HZ,
    RATE_800_HZ,
    RATE_SHIFT,
    SAMPLE,
    STATUS,
    VALID,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
    signed,
)
from tests.python.utils import bus, polling
from tests.python.utils.adxl345_i2c_model import (
    DEVID_VALUE,
    REG_BW_RATE,
    REG_DATA_FORMAT,
    REG_INT_ENABLE,
    REG_INT_MAP,
    REG_POWER_CTL,
    Adxl345I2cModel,
)
from tests.python.utils.check import check
from tests.python.utils.dut import Adxl345I2cDut

BUSY = 1 << 0
NACK = 1 << 4
ARB_LOST = 1 << 5
INT1_LEVEL = 1 << 6
INT2_LEVEL = 1 << 7
USE_INT = 1 << 5
INT_PIN = 1 << 6
LIMIT = 30000
INT_AXES = (10, 20, 30)
ADDRESS_LOW = 0x53
ADDRESS_HIGH = 0x1D
WRONG_ADDRESS = 0x2A
DEFAULT_DIVIDER = 3
CONFIG_STARTS = 7
CONFIG_STOPS = 6
REGISTERS = (
    REG_BW_RATE,
    REG_DATA_FORMAT,
    REG_INT_MAP,
    REG_INT_ENABLE,
    REG_POWER_CTL,
)


def slave_address(dut: Adxl345I2cDut) -> int:
    """Devolva o endereço de 7 bits que o generic escolhe.

    Parameters
    ----------
    dut : Adxl345I2cDut
        Bancada exercitada pelo teste.

    Returns
    -------
    int
        Endereço do escravo.
    """
    high = bool(int(dut.address_select_high.value))
    return ADDRESS_HIGH if high else ADDRESS_LOW


async def setup(
    dut: Adxl345I2cDut, address: int | None = None
) -> Adxl345I2cModel:
    """Reinicie o controlador e ligue o acelerômetro simulado.

    Parameters
    ----------
    dut : Adxl345I2cDut
        Bancada exercitada pelo teste.
    address : int | None
        Endereço do modelo, ou o que o generic escolhe quando omitido.

    Returns
    -------
    Adxl345I2cModel
        Acelerômetro ligado às linhas e aos pinos.
    """
    bus.set_inputs(dut, i_slave_scl_low=0, i_slave_sda_low=0)
    bus.set_inputs(dut, i_adxl_int1=0, i_adxl_int2=0)
    await bus.reset(dut)
    model = Adxl345I2cModel(
        dut, slave_address(dut) if address is None else address
    )
    model.start()
    return model


async def wait_status(dut: Adxl345I2cDut, mask: int, value: int) -> int:
    """Leia STATUS até os bits de ``mask`` valerem ``value``.

    Parameters
    ----------
    dut : Adxl345I2cDut
        Bancada exercitada pelo teste.
    mask : int
        Bits observados.
    value : int
        Valor esperado dos bits observados.

    Returns
    -------
    int
        Último valor de STATUS lido.
    """
    return await polling.wait_status(dut, STATUS, mask, value, LIMIT)


@cocotb.test()
async def test_reset_values(dut: Adxl345I2cDut) -> None:
    """O reset deixa o controlador desligado e as linhas soltas."""
    await setup(dut)
    await bus.cycles(dut, 5)
    expected = {
        STATUS: 0,
        CONTROL: RATE_100_HZ << RATE_SHIFT,
        PERIOD: DEFAULT_PERIOD,
        DIVIDER: DEFAULT_DIVIDER,
    }
    for address, want in expected.items():
        got = await bus.read(dut, address)
        check(got == want, f"registrador {address}: {got:#x}")
    check(int(dut.o_adxl_cs_n.value) == 1, "CS alto escolhe o modo I2C")
    high = int(dut.address_select_high.value)
    check(int(dut.o_adxl_sdo.value) == high, "SDO segue o generic")
    check(int(dut.o_scl.value) == 1 and int(dut.o_sda.value) == 1, "linhas")
    check(int(dut.o_irq.value) == 0, "sem interrupção")


@cocotb.test()
async def test_configuration_sequence(dut: Adxl345I2cDut) -> None:
    """ENABLE lê DEVID e escreve cinco registradores do chip."""
    model = await setup(dut)
    range_2g = 2 << RANGE_SHIFT
    control = ENABLE | FULL_RES | range_2g | RATE_800_HZ << RATE_SHIFT
    await bus.write(dut, CONTROL, control)
    await wait_status(dut, CONFIGURED, CONFIGURED)
    want = [
        (REG_BW_RATE, RATE_800_HZ),
        (REG_DATA_FORMAT, 0x08 | 2),
        (REG_INT_MAP, 0),
        (REG_INT_ENABLE, 0x80),
        (REG_POWER_CTL, MEASURE),
    ]
    check(model.writes == want, f"{model.writes}")
    check(await bus.read(dut, DEVID) == DEVID_VALUE, "DEVID lido")
    check(model.counts.starts == CONFIG_STARTS, f"{model.counts.starts}")
    check(model.counts.stops == CONFIG_STOPS, f"{model.counts.stops}")
    check(await bus.read(dut, STATUS) & (NACK | ARB_LOST) == 0, "sem erro")


@cocotb.test()
async def test_axes_by_time(dut: Adxl345I2cDut) -> None:
    """A leitura periódica traz X, Y e Z com sinal, 1 g no eixo Z."""
    model = await setup(dut)
    await bus.write(dut, PERIOD, 1500)
    await bus.write(dut, CONTROL, ENABLE | RATE_100_HZ << RATE_SHIFT)
    model.set_axes(*FIRST_AXES)
    await wait_status(dut, SAMPLE, SAMPLE)
    for address, want in zip(
        (X_AXIS, Y_AXIS, Z_AXIS), FIRST_AXES, strict=True
    ):
        check(signed(await bus.read(dut, address)) == want, f"eixo {address}")
    check(FIRST_AXES[2] == ONE_G, "1 g no eixo Z")
    await bus.write(dut, STATUS, SAMPLE)
    model.set_axes(*EXTREME_AXES)
    check(await bus.read(dut, STATUS) & SAMPLE == 0, "W1C limpa SAMPLE")
    await wait_status(dut, SAMPLE | VALID, SAMPLE | VALID)
    x_axis = signed(await bus.read(dut, X_AXIS))
    check(x_axis == EXTREME_AXES[0], "X de 13 bits")
    check(signed(await bus.read(dut, Z_AXIS)) == -1, "Z negativo")


async def read_by_pin(dut: Adxl345I2cDut, pin: int, level: int) -> None:
    """Confira a leitura disparada por um dos pinos de interrupção.

    Parameters
    ----------
    dut : Adxl345I2cDut
        Bancada exercitada pelo teste.
    pin : int
        Valor de INT_PIN no CONTROL, zero para INT1 e INT_PIN para INT2.
    level : int
        Bit de STATUS que espelha o nível do pino.
    """
    model = await setup(dut)
    rate = RATE_100_HZ << RATE_SHIFT
    await bus.write(dut, CONTROL, ENABLE | USE_INT | pin | rate)
    await wait_status(dut, CONFIGURED, CONFIGURED)
    want_map = 0x80 if pin else 0
    check((REG_INT_MAP, want_map) in model.writes, "INT_MAP escolhe o pino")
    await bus.cycles(dut, 3000)
    check(await bus.read(dut, STATUS) & SAMPLE == 0, "sem pino não lê")
    model.set_axes(*INT_AXES)
    await wait_status(dut, level, level)
    await wait_status(dut, SAMPLE, SAMPLE)
    check(signed(await bus.read(dut, Z_AXIS)) == INT_AXES[2], "Z lido")
    await bus.cycles(dut, 20)
    check(await bus.read(dut, STATUS) & level == 0, "o modelo desliga o pino")


@cocotb.test()
async def test_read_by_int1(dut: Adxl345I2cDut) -> None:
    """Com USE_INT e INT_PIN em zero a leitura segue INT1."""
    await read_by_pin(dut, 0, INT1_LEVEL)


@cocotb.test()
async def test_read_by_int2(dut: Adxl345I2cDut) -> None:
    """Com INT_PIN em um o dado pronto sai em INT2."""
    await read_by_pin(dut, INT_PIN, INT2_LEVEL)


@cocotb.test()
async def test_interrupt_and_reconfiguration(dut: Adxl345I2cDut) -> None:
    """A interrupção segue SAMPLE e CONTROL reconfigura."""
    model = await setup(dut)
    await bus.write(dut, PERIOD, 1500)
    fast = RATE_800_HZ << RATE_SHIFT
    await bus.write(dut, CONTROL, ENABLE | IRQ_ENABLE | fast)
    model.set_axes(7, 8, 9)
    await wait_status(dut, SAMPLE, SAMPLE)
    irq_before = int(dut.o_irq.value)
    await bus.write(dut, STATUS, SAMPLE)
    check(irq_before == 1, "interrupção de amostra")
    check(int(dut.o_irq.value) == 0, "limpa com W1C")
    writes = len(model.writes)
    range_16g = RANGE_16G << RANGE_SHIFT
    await bus.write(dut, CONTROL, ENABLE | range_16g)
    await wait_status(dut, CONFIGURED, CONFIGURED)
    await bus.cycles(dut, 6000)
    check(len(model.writes) >= 2 * writes, "a configuração se repete")
    last_format = [v for a, v in model.writes if a == REG_DATA_FORMAT][-1]
    check(last_format & RANGE_16G == RANGE_16G, f"faixa nova {last_format:#x}")


@cocotb.test()
async def test_nack_stops_the_sequence(dut: Adxl345I2cDut) -> None:
    """Um escravo ausente dá NACK, a linha é solta e o erro é sticky."""
    model = await setup(dut, WRONG_ADDRESS)
    await bus.write(dut, CONTROL, ENABLE)
    status = await wait_status(dut, NACK, NACK)
    check(status & CONFIGURED == 0, "não configurou")
    await bus.cycles(dut, 4000)
    status = await bus.read(dut, STATUS)
    check(status & BUSY == 0, "voltou ao repouso")
    check(int(dut.o_scl.value) == 1 and int(dut.o_sda.value) == 1, "linhas")
    check(model.counts.nacked_addresses == 1, "uma tentativa só")
    await bus.write(dut, STATUS, NACK)
    check(await bus.read(dut, STATUS) & NACK == 0, "W1C limpa NACK")
    model.address = slave_address(dut)
    await bus.write(dut, CONTROL, ENABLE)
    await wait_status(dut, CONFIGURED, CONFIGURED)
    check(len(model.writes) == len(REGISTERS), "reconfigurou")

"""Auxiliares dos testes do periférico de áudio I2S."""

from collections.abc import Callable

import cocotb

from tests.python.utils import bus
from tests.python.utils.dut import AudioDut
from tests.python.utils.i2s_codec import (
    I2sCodec,
    I2sWires,
    drive_slave_clocks,
)

(
    CONTROL,
    STATUS,
    LEVELS,
    TX_DATA,
    RX_DATA,
    IRQ_LEVEL,
    XCK_STEP,
    XCK_MOD,
    BCLK_DIV,
    SLOT_BITS,
    TONE_HALF,
    TONE_AMP,
    CONFIG,
    CAPS,
) = range(14)

TX_EN = 1 << 0
RX_EN = 1 << 1
TX_IRQ_EN = 1 << 2
RX_IRQ_EN = 1 << 3
ERR_IRQ_EN = 1 << 4
CLK_EN = 1 << 5
TONE_EN = 1 << 6
WORD_SHIFT = 8
WORD_CODE = {16: 0, 24: 1, 32: 2}

TX_NOT_FULL = 1 << 0
RX_NOT_EMPTY = 1 << 1
TX_EMPTY = 1 << 2
RX_FULL = 1 << 3
TX_UNDERFLOW = 1 << 4
RX_OVERFLOW = 1 << 5
TX_DROPPED = 1 << 6

SLAVE_HALF_NS = 80
POLL_STEP = 100
POLL_LIMIT = 1000


def control(word_bits: int, flags: int) -> int:
    """Monte o valor de CONTROL.

    Parameters
    ----------
    word_bits : int
        Largura da palavra em bits.
    flags : int
        Bits de habilitação.

    Returns
    -------
    int
        Valor do registrador.
    """
    return flags | (WORD_CODE[word_bits] << WORD_SHIFT)


def init_pins(dut: AudioDut) -> None:
    """Leve as entradas do codec ao repouso.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.
    """
    dut.i_bclk.value = 0
    dut.i_adclrck.value = 0
    dut.i_daclrck.value = 0
    dut.i_adcdat.value = 0


async def setup(dut: AudioDut) -> None:
    """Reinicie o periférico com as entradas em repouso.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.
    """
    init_pins(dut)
    await bus.reset(dut)


async def start_codec(
    dut: AudioDut, word_bits: int, pairs: list[tuple[int, int]]
) -> I2sCodec:
    """Inicie o codec simulado no modo do periférico.

    No modo mestre o codec observa os pinos do periférico; no modo
    escravo ele também gera BCLK e LRCK.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.
    word_bits : int
        Largura da palavra em bits.
    pairs : list[tuple[int, int]]
        Amostras esquerda e direita enviadas ao ADC.

    Returns
    -------
    I2sCodec
        Modelo em execução.
    """
    master = await bus.read(dut, CAPS) & 1
    driver = None
    slot = await bus.read(dut, SLOT_BITS)
    if master:
        wires = I2sWires(dut.o_bclk, dut.o_daclrck, dut.o_dacdat, dut.i_adcdat)
    else:
        wires = I2sWires(dut.i_bclk, dut.i_daclrck, dut.o_dacdat, dut.i_adcdat)
        driver = cocotb.start_soon(
            drive_slave_clocks(
                dut.i_bclk, [dut.i_daclrck, dut.i_adclrck], SLAVE_HALF_NS, slot
            )
        )
    codec = I2sCodec(wires, word_bits, adc_pairs=pairs)
    codec.start()
    if driver is not None:
        codec.tasks.append(driver)
    return codec


async def wait_until(dut: AudioDut, done: Callable[[], bool]) -> None:
    """Espere uma condição, consultando-a a cada POLL_STEP ciclos.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.
    done : Callable[[], bool]
        Função sem argumentos que devolve verdadeiro quando termina.

    Raises
    ------
    TimeoutError
        Se a condição não valer dentro do limite.
    """
    for _ in range(POLL_LIMIT):
        if done():
            return
        await bus.cycles(dut, POLL_STEP)
    raise TimeoutError("condição não ocorreu no limite")


def usable(codec: I2sCodec) -> list[int]:
    """Devolva as palavras capturadas a partir do primeiro quadro.

    Descarta as palavras zeradas do começo e termina na primeira
    palavra seguinte que tenha deixado de ser alinhada ao quadro.

    Parameters
    ----------
    codec : I2sCodec
        Modelo que capturou o DAC.

    Returns
    -------
    list[int]
        Valores com sinal, na ordem de captura.
    """
    values = [value for _, value in codec.dac_words]
    while values and values[0] == 0:
        values.pop(0)
    return values


def has_words(codec: I2sCodec, count: int) -> Callable[[], bool]:
    """Crie a condição de ter capturado ao menos count palavras úteis.

    Parameters
    ----------
    codec : I2sCodec
        Modelo que capturou o DAC.
    count : int
        Quantidade de palavras esperada.

    Returns
    -------
    Callable[[], bool]
        Função que diz se a captura já alcançou count.
    """
    return lambda: len(usable(codec)) >= count


def has_pairs(codec: I2sCodec, count: int) -> Callable[[], bool]:
    """Crie a condição de ter capturado ao menos count pares.

    Parameters
    ----------
    codec : I2sCodec
        Modelo que capturou o DAC.
    count : int
        Quantidade de pares esperada.

    Returns
    -------
    Callable[[], bool]
        Função que diz se a captura já alcançou count.
    """
    return lambda: len(pairs_of(codec)) >= count


async def wait_rx_level(dut: AudioDut, level: int) -> None:
    """Espere a fila de gravação alcançar um nível.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.
    level : int
        Nível mínimo esperado.

    Raises
    ------
    TimeoutError
        Se o nível não for alcançado dentro do limite.
    """
    for _ in range(POLL_LIMIT):
        if await bus.read(dut, LEVELS) >> 16 >= level:
            return
        await bus.cycles(dut, POLL_STEP)
    raise TimeoutError("fila de gravação não encheu")


async def restart(dut: AudioDut, codec: I2sCodec | None) -> None:
    """Pare o codec simulado e reinicie o periférico, sem outro clock.

    Parameters
    ----------
    dut : AudioDut
        Periférico exercitado.
    codec : I2sCodec | None
        Modelo a encerrar, se houver.
    """
    if codec is not None:
        codec.stop()
    dut.i_rst.value = 1
    init_pins(dut)
    await bus.cycles(dut, 3)
    dut.i_rst.value = 0
    await bus.cycles(dut, 2)


def pairs_of(codec: I2sCodec) -> list[tuple[int, int]]:
    """Agrupe as palavras capturadas em pares esquerda e direita.

    Parameters
    ----------
    codec : I2sCodec
        Modelo que capturou o DAC.

    Returns
    -------
    list[tuple[int, int]]
        Pares de canais consecutivos, esquerdo primeiro.
    """
    words = codec.dac_words
    return [
        (words[i][1], words[i + 1][1])
        for i in range(len(words) - 1)
        if words[i][0] == 0 and words[i + 1][0] == 1
    ]

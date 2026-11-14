"""Mestre SPI mapeado em memória: registradores, filas e interrupção.

A configuração do teste usa ``CLOCK_HZ=4000000`` e
``RESET_SCLK_HZ=1000000``, que dão o divisor de reset 1, três linhas de
seleção de chip e filas de quatro palavras. Um escravo simulado liga-se
aos pinos e troca palavras em cada modo.
"""

import cocotb

from tests.python.utils import bus, polling
from tests.python.utils.check import check
from tests.python.utils.dut import SpiDut
from tests.python.utils.polling import POLL_LIMIT
from tests.python.utils.spi_regs import (
    BUSY,
    CS_ASSERT,
    DONE,
    DONE_IRQ_ENABLE,
    ERROR_IRQ_ENABLE,
    RX_FULL,
    RX_IRQ_ENABLE,
    RX_OVERRUN,
    TX_DROPPED,
    TX_EMPTY,
    TX_EMPTY_IRQ_ENABLE,
    TX_READY,
)
from tests.python.utils.spi_slave import Bit, Wires, WordSlave

TX_DATA, RX_DATA, STATUS, CONTROL, DIVIDER, TX_LISTEN = range(6)
CPOL = 1 << 5
CPHA = 1 << 6
LSB_FIRST = 1 << 7
WORD_SHIFT = 8
SELECT_SHIFT = 16
RESET_DIVIDER = 1
RESET_WORD_BITS = 8
FAST_DIVIDER = 4
ALL_HIGH = 0b111
FIRST_REPLY = 0x11
SECOND_REPLY = 0xBEEF
LISTEN_REPLY = 0x7E
LISTEN_WORD = 0x80
DIVIDER_PATTERN = 0xBEEF
FIFO_DEPTH = 4
CS_COUNT = 3
MODES = ((0, 0), (0, 1), (1, 0), (1, 1))


def control(
    mode: tuple[int, int],
    bits: int,
    select: int = 0,
    lsb_first: bool = False,
    flags: int = CS_ASSERT,
) -> int:
    """Monte o valor do registrador CONTROL.

    Parameters
    ----------
    mode : tuple[int, int]
        Par (CPOL, CPHA).
    bits : int
        Largura da palavra.
    select : int
        Linha de seleção de chip.
    lsb_first : bool
        Verdadeiro para o bit menos significativo primeiro.
    flags : int
        Bits de seleção e de habilitação de interrupção.

    Returns
    -------
    int
        Valor a escrever em CONTROL.
    """
    value = flags | (bits << WORD_SHIFT) | (select << SELECT_SHIFT)
    value |= CPOL * mode[0] | CPHA * mode[1] | LSB_FIRST * int(lsb_first)
    return value


async def setup(dut: SpiDut) -> None:
    """Reinicie o periférico com MISO em nível alto.

    Parameters
    ----------
    dut : SpiDut
        Periférico exercitado pelo teste.
    """
    dut.i_miso.value = 1
    await bus.reset(dut)


async def wait_status(dut: SpiDut, mask: int, value: int) -> int:
    """Leia STATUS até os bits de ``mask`` valerem ``value``."""
    return await polling.wait_status(dut, STATUS, mask, value)


def slave_for(
    dut: SpiDut,
    fmt: tuple[tuple[int, int], int, bool],
    replies: list[int],
    line: int = 0,
) -> WordSlave:
    """Crie um escravo ligado à linha de seleção ``line``.

    Parameters
    ----------
    dut : SpiDut
        Periférico exercitado pelo teste.
    fmt : tuple[tuple[int, int], int, bool]
        Modo (CPOL, CPHA), largura da palavra e se o bit menos
        significativo vai primeiro.
    replies : list[int]
        Palavras que o escravo transmite.
    line : int
        Linha de seleção de chip do escravo.

    Returns
    -------
    WordSlave
        Escravo já iniciado.
    """
    pins = Wires(
        dut.o_sclk, dut.o_mosi, dut.i_miso, Bit(dut.o_cs_n, line, dut.i_clk)
    )
    mode, bits, lsb_first = fmt
    slave = WordSlave(pins, mode, bits, replies, lsb_first)
    slave.start()
    return slave


@cocotb.test()
async def test_reset_values(dut: SpiDut) -> None:
    """O reset deixa as filas vazias, 8 bits no modo 0 e o divisor."""
    await setup(dut)
    check(await bus.read(dut, STATUS) == TX_READY | TX_EMPTY, "STATUS")
    want = RESET_WORD_BITS << WORD_SHIFT
    check(await bus.read(dut, CONTROL) == want, "CONTROL")
    check(await bus.read(dut, DIVIDER) == RESET_DIVIDER, "DIVIDER")
    check(await bus.read(dut, RX_DATA) == 0, "RX_DATA vazio")
    check(int(dut.o_irq.value) == 0, "sem interrupção")
    check(int(dut.o_cs_n.value) == ALL_HIGH, "todas as seleções soltas")
    check(int(dut.o_sclk.value) == 0, "SCLK em repouso")


@cocotb.test()
async def test_control_readback(dut: SpiDut) -> None:
    """CONTROL e DIVIDER devolvem o que se escreveu."""
    await setup(dut)
    value = control((1, 1), 32, 2, True, 0x1F)
    await bus.write(dut, CONTROL, value)
    check(await bus.read(dut, CONTROL) == value, "CONTROL")
    await bus.write(dut, DIVIDER, DIVIDER_PATTERN)
    check(await bus.read(dut, DIVIDER) == DIVIDER_PATTERN, "DIVIDER")


@cocotb.test()
async def test_modes_widths_and_order(dut: SpiDut) -> None:
    """Cada modo, largura e ordem troca palavras pelas filas."""
    await setup(dut)
    await bus.write(dut, DIVIDER, FAST_DIVIDER)
    for mode in MODES:
        for bits, lsb_first in (
            (8, False),
            (12, True),
            (16, False),
            (32, True),
        ):
            full = (1 << bits) - 1
            tx_words = [0xA5C3_96E1 & full, 0x1234_5678 & full]
            rx_words = [0x5A3C_69B2 & full, 0x0F0F_F0F0 & full]
            await bus.write(dut, CONTROL, 0)
            await bus.write(dut, CONTROL, control(mode, bits, 0, lsb_first, 0))
            await bus.cycles(dut, 3)
            slave = slave_for(dut, (mode, bits, lsb_first), rx_words)
            await bus.write(dut, CONTROL, control(mode, bits, 0, lsb_first))
            for word in tx_words:
                await bus.write(dut, TX_DATA, word)
            await wait_status(dut, DONE, DONE)
            got = [await bus.read(dut, RX_DATA) for _ in tx_words]
            name = f"modo {mode} bits {bits} lsb {lsb_first}"
            check(slave.received == tx_words, f"{name} MOSI {slave.received}")
            check(got == rx_words, f"{name} MISO {got}")
            await bus.write(dut, STATUS, DONE)
            await bus.write(dut, CONTROL, 0)
            slave.stop()
            await bus.cycles(dut, 4)


@cocotb.test()
async def test_chip_select_lines(dut: SpiDut) -> None:
    """Só a linha escolhida desce, e só com CS_ASSERT em um."""
    await setup(dut)
    for line in range(CS_COUNT):
        await bus.write(dut, CONTROL, control((0, 0), 8, line))
        want = ALL_HIGH & ~(1 << line)
        check(
            int(dut.o_cs_n.value) == want, f"linha {line}: {dut.o_cs_n.value}"
        )
        await bus.write(dut, CONTROL, control((0, 0), 8, line, flags=0))
        check(int(dut.o_cs_n.value) == ALL_HIGH, "solta sem CS_ASSERT")
    await bus.write(dut, CONTROL, control((0, 0), 8, 7))
    check(int(dut.o_cs_n.value) == ALL_HIGH, "índice fora da faixa")


@cocotb.test()
async def test_two_slaves_share_the_bus(dut: SpiDut) -> None:
    """Dois escravos de modos diferentes só respondem à sua linha."""
    await setup(dut)
    await bus.write(dut, DIVIDER, FAST_DIVIDER)
    first = slave_for(dut, ((0, 0), 8, False), [FIRST_REPLY])
    await bus.write(dut, CONTROL, control((0, 0), 8, 0))
    await bus.write(dut, TX_DATA, 0xC4)
    await wait_status(dut, DONE, DONE)
    check(await bus.read(dut, RX_DATA) == FIRST_REPLY, "primeiro escravo")
    await bus.write(dut, STATUS, DONE)
    await bus.write(dut, CONTROL, 0)
    first.stop()
    await bus.write(dut, CONTROL, control((1, 1), 16, 2, flags=0))
    await bus.cycles(dut, 3)
    second = slave_for(dut, ((1, 1), 16, False), [SECOND_REPLY], 2)
    await bus.write(dut, CONTROL, control((1, 1), 16, 2))
    await bus.write(dut, TX_DATA, 0x1234)
    await wait_status(dut, DONE, DONE)
    check(await bus.read(dut, RX_DATA) == SECOND_REPLY, "segundo escravo")
    check(second.received == [0x1234], f"{second.received}")
    check(first.received == [0xC4], f"o primeiro viu {first.received}")


@cocotb.test()
async def test_listen_word_releases_mosi(dut: SpiDut) -> None:
    """A palavra enfileirada em TX_LISTEN solta MOSI."""
    await setup(dut)
    await bus.write(dut, DIVIDER, FAST_DIVIDER)
    await bus.write(dut, CONTROL, control((1, 1), 8, flags=0))
    await bus.cycles(dut, 3)
    slave = slave_for(dut, ((1, 1), 8, False), [0x00, LISTEN_REPLY])
    await bus.write(dut, CONTROL, control((1, 1), 8))
    await bus.write(dut, TX_DATA, LISTEN_WORD)
    await bus.write(dut, TX_LISTEN, 0xFF)
    seen_low = 0
    for _ in range(POLL_LIMIT):
        seen_low += 1 - int(dut.o_mosi_oe.value)
        if (await bus.read(dut, STATUS)) & DONE:
            break
    check(seen_low > 0, "o driver caiu durante a escuta")
    check(await bus.read(dut, RX_DATA) == 0x00, "primeira palavra")
    check(await bus.read(dut, RX_DATA) == LISTEN_REPLY, "palavra de escuta")
    check(slave.received[0] == LISTEN_WORD, "a escrita foi dirigida")
    slave.stop()


@cocotb.test()
async def test_status_flags_and_errors(dut: SpiDut) -> None:
    """As filas cheias marcam descarte e estouro, e o W1C limpa."""
    await setup(dut)
    await bus.write(dut, CONTROL, control((0, 0), 8))
    for index in range(FIFO_DEPTH + 3):
        await bus.write(dut, TX_DATA, index)
    status = await bus.read(dut, STATUS)
    check(status & TX_DROPPED != 0, f"descarte {status:#x}")
    await wait_status(dut, BUSY, 0)
    status = await bus.read(dut, STATUS)
    check(status & RX_OVERRUN != 0, f"estouro {status:#x}")
    check(status & RX_FULL != 0, "fila de recepção cheia")
    check((status >> 8) & 0xFF == FIFO_DEPTH, "nível da recepção")
    await bus.write(dut, STATUS, DONE | RX_OVERRUN | TX_DROPPED)
    status = await bus.read(dut, STATUS)
    check(status & (DONE | RX_OVERRUN | TX_DROPPED) == 0, "marcas limpas")


@cocotb.test()
async def test_interrupt_causes(dut: SpiDut) -> None:
    """Cada causa de interrupção tem a sua habilitação."""
    await setup(dut)
    await bus.write(dut, CONTROL, control((0, 0), 8, flags=0))
    check(int(dut.o_irq.value) == 0, "sem habilitação")
    await bus.write(
        dut, CONTROL, control((0, 0), 8, flags=TX_EMPTY_IRQ_ENABLE)
    )
    check(int(dut.o_irq.value) == 1, "fila de transmissão vazia")
    await bus.write(dut, CONTROL, control((0, 0), 8, flags=DONE_IRQ_ENABLE))
    check(int(dut.o_irq.value) == 0, "ainda sem fim")
    await bus.write(dut, TX_DATA, 0x55)
    await wait_status(dut, DONE, DONE)
    check(int(dut.o_irq.value) == 1, "fim de transferência")
    await bus.write(dut, STATUS, DONE)
    check(int(dut.o_irq.value) == 0, "limpa com W1C")
    await bus.write(dut, CONTROL, control((0, 0), 8, flags=RX_IRQ_ENABLE))
    check(int(dut.o_irq.value) == 1, "palavra recebida")
    await bus.read(dut, RX_DATA)
    check(int(dut.o_irq.value) == 0, "leitura esvazia")
    await bus.write(dut, CONTROL, control((0, 0), 8, flags=ERROR_IRQ_ENABLE))
    for index in range(FIFO_DEPTH + 2):
        await bus.write(dut, TX_DATA, index)
    check(int(dut.o_irq.value) == 1, "erro")

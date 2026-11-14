"""Mestre SPI genérico: modos, larguras, ordem dos bits e divisor.

Um escravo simulado (``WordSlave``) liga-se aos pinos e troca palavras
com o mestre. O teste confere o que o escravo amostrou em MOSI, o que o
mestre recebeu em MISO, o nível de repouso e o número de bordas de SCLK,
o período, e que SCLK só se move com o mestre ocupado.
"""

from dataclasses import dataclass, field

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import SpiMasterDut
from tests.python.utils.spi_slave import Wires, WordSlave

MODES = ((0, 0), (0, 1), (1, 0), (1, 1))
WIDTHS = (1, 5, 8, 12, 16, 24, 32)
PATTERN_TX = 0xA5C3_96E1
PATTERN_RX = 0x5A3C_69B2
CYCLE_LIMIT = 4000
RESET_HOLD = 3
WORD_MAX = 32
EDGES_PER_BIT = 2
RESTART_CYCLE = 10


@dataclass
class Capture:
    """O que o teste viu nos pinos durante uma palavra."""

    edges: int = 0
    done: int = 0
    rx: int = -1
    gaps: list[int] = field(default_factory=list[int])
    moved_idle: int = 0
    oe_low_cycles: int = 0
    busy_cycles: int = 0

    def sample(
        self, dut: SpiMasterDut, previous: int, last_edge: int, cycle: int
    ) -> tuple[int, int]:
        """Anote os pinos deste ciclo.

        Parameters
        ----------
        dut : SpiMasterDut
            Mestre exercitado pelo teste.
        previous : int
            Nível de SCLK no ciclo anterior.
        last_edge : int
            Ciclo da última borda de subida, ou -1.
        cycle : int
            Ciclo atual.

        Returns
        -------
        tuple[int, int]
            Nível de SCLK deste ciclo e ciclo da última subida.
        """
        busy = int(dut.o_busy.value)
        sclk = int(dut.o_sclk.value)
        self.busy_cycles += busy
        if busy and not int(dut.o_mosi_oe.value):
            self.oe_low_cycles += 1
        if sclk != previous:
            self.edges += 1
            if not busy and not int(dut.o_done.value):
                self.moved_idle += 1
            last_edge = self._rise(sclk, last_edge, cycle)
        return sclk, last_edge

    def _rise(self, sclk: int, last_edge: int, cycle: int) -> int:
        """Anote o período entre duas subidas de SCLK."""
        if sclk != 1:
            return last_edge
        if last_edge >= 0:
            self.gaps.append(cycle - last_edge)
        return cycle


def mask(bits: int) -> int:
    """Devolva a máscara dos ``bits`` bits baixos.

    Parameters
    ----------
    bits : int
        Largura da palavra.

    Returns
    -------
    int
        Máscara com os bits baixos em um.
    """
    return (1 << bits) - 1


async def setup(dut: SpiMasterDut) -> None:
    """Reinicie o mestre com a configuração neutra.

    Parameters
    ----------
    dut : SpiMasterDut
        Mestre exercitado pelo teste.
    """
    dut.i_start.value = 0
    dut.i_tx_data.value = 0
    dut.i_miso.value = 1
    dut.i_cpol.value = 0
    dut.i_cpha.value = 0
    dut.i_lsb_first.value = 0
    dut.i_word_bits.value = 8
    dut.i_divider.value = 1
    dut.i_tx_drive.value = 1
    await bus.hold_reset(dut, RESET_HOLD)
    await bus.cycles(dut, 2)


def configure(
    dut: SpiMasterDut,
    mode: tuple[int, int],
    bits: int,
    lsb_first: bool,
    divider: int,
) -> None:
    """Programe o modo, a largura, a ordem e o divisor.

    Parameters
    ----------
    dut : SpiMasterDut
        Mestre exercitado pelo teste.
    mode : tuple[int, int]
        Par (CPOL, CPHA).
    bits : int
        Largura da palavra.
    lsb_first : bool
        Verdadeiro para o bit menos significativo primeiro.
    divider : int
        Metade do período de SCLK menos um.
    """
    dut.i_cpol.value, dut.i_cpha.value = mode
    dut.i_lsb_first.value = int(lsb_first)
    dut.i_word_bits.value = bits
    dut.i_divider.value = divider


async def run_word(
    dut: SpiMasterDut,
    tx_value: int,
    cpol: int,
) -> Capture:
    """Dispare uma palavra e anote os pinos até o fim.

    Parameters
    ----------
    dut : SpiMasterDut
        Mestre exercitado pelo teste.
    tx_value : int
        Palavra transmitida.
    cpol : int
        Nível de repouso esperado de SCLK.

    Returns
    -------
    Capture
        Bordas, períodos, pulsos de fim e palavra recebida.
    """
    cap = Capture()
    dut.i_tx_data.value = tx_value
    dut.i_start.value = 1
    await bus.cycles(dut, 1)
    dut.i_start.value = 0
    previous = int(dut.o_sclk.value)
    last_edge = -1
    for cycle in range(CYCLE_LIMIT):
        previous, last_edge = cap.sample(dut, previous, last_edge, cycle)
        if int(dut.o_done.value):
            cap.done += 1
            cap.rx = int(dut.o_rx_data.value)
            break
        await bus.cycles(dut, 1)
    await bus.cycles(dut, 3)
    check(int(dut.o_sclk.value) == cpol, "SCLK volta ao repouso")
    return cap


async def start_slave(
    dut: SpiMasterDut,
    cfg: tuple[tuple[int, int], int, bool, int],
    replies: list[int],
    width: int = 0,
) -> WordSlave:
    """Programe o mestre e ligue um escravo simulado.

    Parameters
    ----------
    dut : SpiMasterDut
        Mestre exercitado pelo teste.
    cfg : tuple[tuple[int, int], int, bool, int]
        Modo (CPOL, CPHA), largura, ordem e divisor do mestre.
    replies : list[int]
        Palavras que o escravo transmite.
    width : int
        Largura da palavra do escravo, ou zero para a do mestre.

    Returns
    -------
    WordSlave
        Escravo já iniciado.
    """
    mode, bits, lsb_first, divider = cfg
    configure(dut, mode, bits, lsb_first, divider)
    await bus.cycles(dut, 3)
    pins = Wires(dut.o_sclk, dut.o_mosi, dut.i_miso)
    slave = WordSlave(pins, mode, width or bits, replies, lsb_first)
    slave.start()
    return slave


async def exchange(
    dut: SpiMasterDut,
    mode: tuple[int, int],
    bits: int,
    lsb_first: bool,
    divider: int,
) -> tuple[Capture, WordSlave]:
    """Troque uma palavra com um escravo simulado.

    Parameters
    ----------
    dut : SpiMasterDut
        Mestre exercitado pelo teste.
    mode : tuple[int, int]
        Par (CPOL, CPHA).
    bits : int
        Largura da palavra.
    lsb_first : bool
        Verdadeiro para o bit menos significativo primeiro.
    divider : int
        Metade do período de SCLK menos um.

    Returns
    -------
    tuple[Capture, WordSlave]
        Anotações dos pinos e o escravo, com a palavra que ele recebeu.
    """
    width = min(max(bits, 1), WORD_MAX)
    slave = await start_slave(
        dut,
        (mode, bits, lsb_first, divider),
        [PATTERN_RX & mask(width)],
        width,
    )
    cap = await run_word(dut, PATTERN_TX & mask(width), mode[0])
    slave.stop()
    return cap, slave


@cocotb.test()
async def test_idle_follows_cpol(dut: SpiMasterDut) -> None:
    """Em repouso SCLK acompanha CPOL e MOSI fica em nível alto."""
    await setup(dut)
    check(int(dut.o_sclk.value) == 0, "SCLK baixo com CPOL 0")
    dut.i_cpol.value = 1
    await bus.cycles(dut, 3)
    check(int(dut.o_sclk.value) == 1, "SCLK alto com CPOL 1")
    check(int(dut.o_mosi.value) == 1, "MOSI alto em repouso")
    check(int(dut.o_busy.value) == 0, "ocioso")


@cocotb.test()
async def test_four_modes_and_widths(dut: SpiMasterDut) -> None:
    """Cada modo e largura troca a palavra nos dois sentidos."""
    await setup(dut)
    for mode in MODES:
        for bits in WIDTHS:
            for lsb_first in (False, True):
                cap, slave = await exchange(dut, mode, bits, lsb_first, 2)
                name = f"modo {mode} bits {bits} lsb {lsb_first}"
                check(slave.received == [PATTERN_TX & mask(bits)], name)
                check(cap.rx == PATTERN_RX & mask(bits), f"{name} rx")
                check(cap.done == 1, f"{name} done")
                check(cap.edges == 2 * bits, f"{name} bordas {cap.edges}")
                check(cap.moved_idle == 0, f"{name} SCLK só com busy")


@cocotb.test()
async def test_sclk_period_for_each_divider(dut: SpiMasterDut) -> None:
    """O período de SCLK vale 2 * (divisor + 1) ciclos em todo modo."""
    await setup(dut)
    for mode in MODES:
        for divider in (1, 2, 5):
            cap, _ = await exchange(dut, mode, 8, False, divider)
            check(
                set(cap.gaps) == {2 * (divider + 1)},
                f"modo {mode} divisor {divider}: {set(cap.gaps)}",
            )


@cocotb.test()
async def test_word_bits_clamp(dut: SpiMasterDut) -> None:
    """Zero bits vira um bit e mais que a largura máxima vira 32."""
    await setup(dut)
    cap, _ = await exchange(dut, (0, 0), 0, False, 1)
    check(cap.edges == EDGES_PER_BIT, f"zero bits deu {cap.edges} bordas")
    cap, _ = await exchange(dut, (0, 0), 40, False, 1)
    check(cap.edges == 2 * WORD_MAX, f"40 bits deu {cap.edges} bordas")


@cocotb.test()
async def test_start_while_busy_is_ignored(dut: SpiMasterDut) -> None:
    """Um pedido de início durante a palavra não a interrompe."""
    await setup(dut)
    slave = await start_slave(dut, ((1, 1), 8, False, 1), [0x3C])
    dut.i_tx_data.value = 0xA5
    dut.i_start.value = 1
    await bus.cycles(dut, 1)
    dut.i_tx_data.value = 0x11
    for cycle in range(CYCLE_LIMIT):
        await bus.cycles(dut, 1)
        if cycle == RESTART_CYCLE:
            dut.i_start.value = 0
        if int(dut.o_done.value):
            break
    slave.stop()
    check(slave.received == [0xA5], f"recebeu {slave.received}")


@cocotb.test()
async def test_listen_word_releases_mosi(dut: SpiMasterDut) -> None:
    """Uma palavra de escuta solta MOSI até a palavra seguinte."""
    await setup(dut)
    check(int(dut.o_mosi_oe.value) == 1, "driver ligado no reset")
    dut.i_tx_drive.value = 0
    cap, slave = await exchange(dut, (1, 1), 8, False, 1)
    check(cap.oe_low_cycles == cap.busy_cycles, "solto durante a palavra")
    check(int(dut.o_mosi_oe.value) == 0, "continua solto depois")
    check(cap.rx == PATTERN_RX & 0xFF, "a escuta recebe")
    check(len(slave.received) == 1, "o escravo viu uma palavra")
    dut.i_tx_drive.value = 1
    cap, _ = await exchange(dut, (1, 1), 8, False, 1)
    check(cap.oe_low_cycles == 0, "palavra seguinte dirige MOSI")
    check(int(dut.o_mosi_oe.value) == 1, "driver ligado de novo")


@cocotb.test()
async def test_back_to_back_words(dut: SpiMasterDut) -> None:
    """Duas palavras seguidas chegam inteiras ao escravo."""
    await setup(dut)
    replies = [0x123, 0xABC]
    slave = await start_slave(dut, ((0, 1), 12, True, 1), replies)
    received: list[int] = []
    for tx_value in (0x5A5, 0xF0F):
        dut.i_tx_data.value = tx_value
        dut.i_start.value = 1
        await bus.cycles(dut, 1)
        dut.i_start.value = 0
        for _ in range(CYCLE_LIMIT):
            if int(dut.o_done.value):
                received.append(int(dut.o_rx_data.value))
                break
            await bus.cycles(dut, 1)
        await bus.cycles(dut, 1)
    slave.stop()
    check(slave.received == [0x5A5, 0xF0F], f"{slave.received}")
    check(received == [0x123, 0xABC], f"{received}")

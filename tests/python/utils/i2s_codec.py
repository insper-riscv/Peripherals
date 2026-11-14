"""Modelo comportamental do codec de áudio I2S para os testes.

O modelo reconstrói as amostras que o DAC recebe e alimenta o ADC com
amostras dadas, no formato I2S: o canal troca na borda de descida do
BCLK, o bit mais significativo sai um ciclo de BCLK depois e o
receptor amostra na borda de subida.
"""

from dataclasses import dataclass, field

import cocotb
from cocotb.handle import LogicObject
from cocotb.task import Task
from cocotb.triggers import FallingEdge, RisingEdge, Timer

SETTLE_NS = 5
LRCK_DELAY_NS = 3
PHASE_NS = 1


@dataclass
class I2sWires:
    """Fios observados pelo modelo."""

    bclk: LogicObject
    lrck: LogicObject
    dacdat: LogicObject
    adcdat: LogicObject | None


def to_signed(value: int, bits: int) -> int:
    """Interprete um valor de bits bits como inteiro com sinal.

    Parameters
    ----------
    value : int
        Valor sem sinal.
    bits : int
        Largura em bits.

    Returns
    -------
    int
        Valor com sinal.
    """
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def bit_of(word: int, index: int, bits: int) -> int:
    """Devolva o bit de índice index (1 é o mais significativo).

    Parameters
    ----------
    word : int
        Palavra de bits bits.
    index : int
        Posição desde o começo do canal, de 1 a bits.
    bits : int
        Largura da palavra.

    Returns
    -------
    int
        O bit, ou zero fora da palavra (preenchimento).
    """
    if 1 <= index <= bits:
        return (word >> (bits - index)) & 1
    return 0


@dataclass
class I2sCodec:
    """Codec simulado: captura o DAC e envia amostras ao ADC."""

    wires: I2sWires
    word_bits: int
    dac_words: list[tuple[int, int]] = field(
        default_factory=list[tuple[int, int]]
    )
    padding_clean: bool = True
    short_slots: int = 0
    adc_pairs: list[tuple[int, int]] = field(
        default_factory=list[tuple[int, int]]
    )
    tasks: list[Task[None]] = field(default_factory=list[Task[None]])

    def start(self) -> None:
        """Inicie as tarefas do modelo, a de alimentação só com ADC."""
        self.tasks.append(cocotb.start_soon(self._capture()))
        if self.wires.adcdat is not None:
            self.tasks.append(cocotb.start_soon(self._feed()))

    def stop(self) -> None:
        """Encerre todas as tarefas do modelo."""
        for task in self.tasks:
            task.cancel()
        self.tasks.clear()

    def _close(self, channel: int, bits: list[int]) -> None:
        """Feche um canal e registre a palavra recebida.

        Parameters
        ----------
        channel : int
            Canal do slot que terminou.
        bits : list[int]
            Bits amostrados no slot, do primeiro ao último.
        """
        if len(bits) < self.word_bits:
            self.short_slots += 1
            return
        raw = 0
        for bit in bits[: self.word_bits]:
            raw = (raw << 1) | bit
        start = self.word_bits
        padding = bits[start:]
        if any(padding):
            self.padding_clean = False
        self.dac_words.append((channel, to_signed(raw, self.word_bits)))

    async def _capture(self) -> None:
        """Amostre o DAC a cada borda de subida do BCLK."""
        bits: list[int] = []
        previous: int | None = None
        while True:
            await RisingEdge(self.wires.bclk)
            lrck = int(self.wires.lrck.value)
            bit = int(self.wires.dacdat.value)
            if previous is not None:
                bits.append(bit)
                if lrck != previous:
                    self._close(previous, bits)
                    bits = []
            previous = lrck

    async def _feed(self) -> None:
        """Troque o dado do ADC a cada borda de descida do BCLK."""
        previous: int | None = None
        index = 0
        current = 0
        stash = 0
        pairs = iter(self.adc_pairs)
        while True:
            await FallingEdge(self.wires.bclk)
            await Timer(SETTLE_NS, unit="ns")
            lrck = int(self.wires.lrck.value)
            index += 1
            out = bit_of(current, index, self.word_bits)
            if previous is not None and lrck != previous:
                index = 0
                if lrck == 0:
                    current, stash = next(pairs, (0, 0))
                else:
                    current = stash
            if self.wires.adcdat is not None:
                self.wires.adcdat.value = out
            previous = lrck


async def drive_slave_clocks(
    bclk: LogicObject,
    lrck_signals: list[LogicObject],
    half_ns: int,
    slot_bits: int,
) -> None:
    """Gere BCLK e LRCK como um codec mestre.

    Parameters
    ----------
    bclk : LogicObject
        Entrada de BCLK do periférico.
    lrck_signals : list[LogicObject]
        Entradas de LRCK do periférico.
    half_ns : int
        Meio período do BCLK em nanossegundos.
    slot_bits : int
        Ciclos de BCLK por canal.
    """
    falls = 0
    level = 0
    bclk.value = 0
    for signal in lrck_signals:
        signal.value = 0
    # O desvio de 1 ns tira as trocas da borda do clock do sistema, onde
    # o simulador resolveria a corrida de forma arbitrária.
    await Timer(PHASE_NS, unit="ns")
    shortened = 0
    while True:
        await Timer(half_ns - shortened, unit="ns")
        bclk.value = 1
        await Timer(half_ns, unit="ns")
        bclk.value = 0
        falls += 1
        shortened = 0
        if falls % slot_bits == 0:
            await Timer(LRCK_DELAY_NS, unit="ns")
            level ^= 1
            for signal in lrck_signals:
                signal.value = level
            shortened = LRCK_DELAY_NS

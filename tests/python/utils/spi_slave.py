"""Modelo comportamental de um escravo SPI nos quatro modos.

O modelo cuida só do relógio: observa SCLK e a seleção de chip,
entrega as palavras que o escravo transmite na ordem e na fase do modo
e junta as palavras que o mestre transmite. O comportamento do chip
fica nas subclasses, que decidem a próxima palavra e recebem a palavra
pronta.

Fases. Com CPHA 0 o escravo apresenta o primeiro bit assim que é
selecionado, o mestre amostra na borda leading e o escravo troca de
bit na borda trailing. Com CPHA 1 o escravo troca de bit na borda
leading e o mestre amostra na trailing.
"""

from typing import Protocol, override

import cocotb
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import First, RisingEdge, Trigger


class Bit:
    """Um bit de um sinal, com o evento de mudança do sinal inteiro."""

    def __init__(
        self,
        signal: LogicObject | LogicArrayObject,
        index: int = 0,
        clock: LogicObject | None = None,
    ) -> None:
        """Escolha o bit.

        Parameters
        ----------
        signal : LogicObject | LogicArrayObject
            Sinal, escalar ou vetor.
        index : int
            Posição do bit, zero para o menos significativo.
        clock : LogicObject | None
            Clock que sonda um vetor, que não tem gatilho de mudança.
        """
        self.signal = signal
        self.index = index
        self.clock = clock

    @property
    def level(self) -> int:
        """Nível atual do bit."""
        return (int(self.signal.value) >> self.index) & 1

    @property
    def changed(self) -> Trigger:
        """Gatilho que dispara quando o sinal pode ter mudado."""
        if self.clock is not None:
            return RisingEdge(self.clock)
        if not isinstance(self.signal, LogicObject):
            message = "um vetor precisa de clock para ser sondado"
            raise TypeError(message)
        return self.signal.value_change


class SlavePins(Protocol):
    """Pinos do escravo vistos do lado do mestre."""

    sclk: LogicObject
    mosi: LogicObject
    miso: LogicObject
    cs_n: Bit | None


class SpiSlave:  # pylint: disable=too-many-instance-attributes
    """Escravo SPI genérico, com as palavras da subclasse."""

    def __init__(
        self,
        pins: SlavePins,
        mode: tuple[int, int],
        bits: int,
        lsb_first: bool = False,
    ) -> None:
        """Crie o escravo.

        Parameters
        ----------
        pins : SlavePins
            Pinos SCLK, MOSI, MISO e seleção de chip do mestre.
        mode : tuple[int, int]
            Par (CPOL, CPHA).
        bits : int
            Bits de cada palavra.
        lsb_first : bool
            Verdadeiro se o bit menos significativo vai primeiro.
        """
        self.pins = pins
        self.cpol, self.cpha = mode
        self.bits = bits
        self.lsb_first = lsb_first
        self.errors: list[str] = []
        self.sample_edges = 0
        self._out: list[int] = []
        self._out_index = 0
        self._in: list[int] = []
        self._selected = False
        self._alive = False

    def start(self) -> None:
        """Inicie o processo que acompanha os pinos."""
        self.pins.miso.value = 1
        if self.pins.cs_n is None:
            self._select()
        self._alive = True
        cocotb.start_soon(self._run())

    def stop(self) -> None:
        """Encerre o processo que acompanha os pinos."""
        self._alive = False

    def load_word(self) -> int:
        """Devolva a próxima palavra que o escravo transmite.

        Returns
        -------
        int
            Palavra de ``bits`` bits.
        """
        return (1 << self.bits) - 1

    def store_word(self, value: int) -> None:
        """Receba uma palavra completa do mestre.

        Parameters
        ----------
        value : int
            Palavra recebida.
        """

    def frame_start(self) -> None:
        """Trate a seleção do escravo, antes do primeiro bit."""

    def frame_end(self) -> None:
        """Trate o fim da seleção do escravo."""

    def _order(self, value: int) -> list[int]:
        """Separe uma palavra em bits, na ordem de transmissão."""
        bits = [(value >> index) & 1 for index in range(self.bits)]
        return bits if self.lsb_first else bits[::-1]

    def _join(self, bits: list[int]) -> int:
        """Monte a palavra a partir dos bits na ordem de chegada."""
        ordered = bits if self.lsb_first else bits[::-1]
        return sum(bit << index for index, bit in enumerate(ordered))

    def _new_word(self) -> None:
        """Carregue a próxima palavra de saída."""
        self._out = self._order(self.load_word())
        self._out_index = 0

    def _drive_next(self) -> None:
        """Apresente o próximo bit da palavra de saída."""
        if self._out_index == self.bits:
            self._new_word()
        self.pins.miso.value = self._out[self._out_index]
        self._out_index += 1

    def _select(self) -> None:
        """Comece um quadro."""
        self._selected = True
        self._in = []
        self.frame_start()
        self._new_word()
        self._out_index = 0
        if self.cpha == 0:
            self._drive_next()

    def _deselect(self) -> None:
        """Termine o quadro e solte a linha."""
        if self._selected:
            self.frame_end()
        self._selected = False
        self.pins.miso.value = 1

    def _edge(self, level: int) -> None:
        """Trate uma borda de SCLK com o escravo selecionado."""
        leading = level != self.cpol
        if leading == (self.cpha == 0):
            self.sample_edges += 1
            self._in.append(int(self.pins.mosi.value))
            if len(self._in) == self.bits:
                self.store_word(self._join(self._in))
                self._in = []
        else:
            self._drive_next()

    def _triggers(self) -> list[Trigger]:
        """Devolva os gatilhos que podem mudar o escravo."""
        events: list[Trigger] = [self.pins.sclk.value_change]
        if self.pins.cs_n is not None:
            events.append(self.pins.cs_n.changed)
        return events

    def _follow_selection(self) -> bool:
        """Siga a seleção de chip e devolva se o escravo está ativo."""
        cs_n = self.pins.cs_n
        low = cs_n is None or cs_n.level == 0
        if low and not self._selected:
            self._select()
        elif not low and self._selected:
            self._deselect()
        return low

    async def _run(self) -> None:
        """Acompanhe SCLK e a seleção de chip."""
        last = int(self.pins.sclk.value)
        while self._alive:
            await First(*self._triggers())
            if not self._alive:
                break
            level = int(self.pins.sclk.value)
            if self._follow_selection() and level != last:
                self._edge(level)
            last = level


class Wires:
    """Pinos de um mestre, agrupados para o modelo do escravo."""

    def __init__(
        self,
        sclk: LogicObject,
        mosi: LogicObject,
        miso: LogicObject,
        cs_n: Bit | None = None,
    ) -> None:
        """Agrupe os pinos.

        Parameters
        ----------
        sclk : LogicObject
            Relógio serial do mestre.
        mosi : LogicObject
            Dado do mestre para o escravo.
        miso : LogicObject
            Dado do escravo para o mestre, dirigido pelo modelo.
        cs_n : Bit | None
            Seleção de chip em nível baixo, ou ``None`` sem seleção.
        """
        self.sclk = sclk
        self.mosi = mosi
        self.miso = miso
        self.cs_n = cs_n


class WordSlave(SpiSlave):
    """Escravo que transmite uma lista de palavras e guarda as lidas."""

    def __init__(
        self,
        pins: SlavePins,
        mode: tuple[int, int],
        bits: int,
        replies: list[int],
        lsb_first: bool = False,
    ) -> None:
        """Crie o escravo com as palavras que ele transmite.

        Parameters
        ----------
        pins : SlavePins
            Pinos do mestre.
        mode : tuple[int, int]
            Par (CPOL, CPHA).
        bits : int
            Bits de cada palavra.
        replies : list[int]
            Palavras transmitidas, em ordem; depois delas, só uns.
        lsb_first : bool
            Verdadeiro se o bit menos significativo vai primeiro.
        """
        super().__init__(pins, mode, bits, lsb_first)
        self.replies = list(replies)
        self.received: list[int] = []

    @override
    def load_word(self) -> int:
        """Devolva a próxima resposta, ou uns quando acabarem.

        Returns
        -------
        int
            Palavra transmitida.
        """
        if self.replies:
            return self.replies.pop(0)
        return (1 << self.bits) - 1

    @override
    def store_word(self, value: int) -> None:
        """Guarde a palavra recebida.

        Parameters
        ----------
        value : int
            Palavra recebida do mestre.
        """
        self.received.append(value)

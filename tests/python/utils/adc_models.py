"""Modelos comportamentais dos conversores ADC128S022 e LTC2308.

Os dois modelos são SUPOSIÇÕES a partir do que o manual diz e do que se
lembra das folhas de dados, que não estão no repositório: o formato das
palavras, o modo SPI e o atraso de um quadro entre configurar um canal e
receber o seu resultado. Cada suposição está marcada abaixo.
"""

from typing import ClassVar, override

from tests.python.utils.spi_slave import SlavePins, SpiSlave

ADC_MASK = 0xFFF


class AdcModel(SpiSlave):
    """Base dos conversores de oito canais com resultado de 12 bits."""

    MODE: ClassVar[tuple[int, int]] = (0, 0)
    BITS: ClassVar[int] = 12

    def __init__(self, pins: SlavePins, values: list[int]) -> None:
        """Crie o conversor.

        Parameters
        ----------
        pins : SlavePins
            Pinos SCLK, MOSI, MISO e seleção de chip.
        values : list[int]
            Resultado de 12 bits de cada um dos oito canais.
        """
        super().__init__(pins, self.MODE, self.BITS)
        self.values = values
        self.selected = 0
        self.latched = 0
        self.frames: int = 0
        self.log: list[int] = []


class Adc128Model(AdcModel):
    """ADC128S022: quadro de 16 clocks no modo 3.

    SUPOSIÇÃO: palavra recebida com o endereço do canal nos bits 13:11,
    palavra devolvida com quatro zeros e o resultado de 12 bits, e o
    resultado de um quadro é o do canal endereçado no quadro anterior
    (depois do reset, o canal 0).
    """

    MODE: ClassVar[tuple[int, int]] = (1, 1)
    BITS: ClassVar[int] = 16

    @override
    def load_word(self) -> int:
        """Devolva o resultado do canal selecionado no quadro anterior.

        Returns
        -------
        int
            Palavra de 16 bits.
        """
        return self.values[self.selected] & ADC_MASK

    @override
    def store_word(self, value: int) -> None:
        """Guarde o endereço do canal que o mestre enviou.

        Parameters
        ----------
        value : int
            Palavra recebida do mestre.
        """
        self.log.append((value >> 11) & 7)
        self.selected = (value >> 11) & 7

    @override
    def frame_end(self) -> None:
        """Conte o quadro e confira que ele teve 16 clocks."""
        self.frames += 1
        if self.sample_edges != 16 * self.frames:
            self.errors.append(f"quadro {self.frames}: {self.sample_edges}")


class Ltc2308Model(AdcModel):
    """LTC2308: palavra de 12 clocks no modo 0 com o pulso de CONVST.

    SUPOSIÇÃO: os seis primeiros bits recebidos são S/D, O/S, S1, S0,
    UNI e SLP, o canal de entrada única é ``O/S + 2 * S0 + 4 * S1``, e
    o resultado do quadro é o do canal configurado no quadro anterior
    (o canal 0 depois do reset).
    """

    MODE: ClassVar[tuple[int, int]] = (0, 0)
    BITS: ClassVar[int] = 12

    def convst_rise(self) -> None:
        """Converta o canal configurado quando ADC_CONVST sobe."""
        self.latched = self.values[self.selected] & ADC_MASK
        self._select()

    @override
    def load_word(self) -> int:
        """Devolva o resultado da última conversão.

        Returns
        -------
        int
            Palavra de 12 bits.
        """
        return self.latched

    @override
    def store_word(self, value: int) -> None:
        """Decodifique a configuração enviada pelo mestre.

        Parameters
        ----------
        value : int
            Palavra recebida do mestre.
        """
        config = value >> 6
        self.log.append(config)
        single, odd, s1, s0 = (config >> 5) & 1, (config >> 4) & 1, 0, 0
        s1, s0 = (config >> 3) & 1, (config >> 2) & 1
        uni, sleep = (config >> 1) & 1, config & 1
        if (single, uni, sleep) != (1, 1, 0):
            self.errors.append(f"configuração {config:#04x}")
        self.selected = odd + 2 * s0 + 4 * s1

"""Modelo comportamental do acelerômetro ADXL345 no SPI.

O modelo é uma SUPOSIÇÃO a partir do que se lembra da folha de dados,
que não está no repositório; o manual da DE10-Lite só confirma o bit SPI
de DATA_FORMAT (registrador 0x31) para os três fios e a saída de 16 bits
em complemento de dois. Cada suposição está marcada abaixo.

SUPOSIÇÕES. O SPI é o modo 3 (CPOL 1 e CPHA 1), bit mais significativo
primeiro, e o primeiro byte do quadro é o comando (bit 7 leitura, bit 6
rajada, bits 5:0 endereço, que avança a cada byte da rajada). DEVID vale
0xE5. Os eixos ficam em 0x32 a 0x37, byte baixo primeiro. INT_ENABLE em
0x2E com o bit 7 liga o dado pronto em INT1, e a leitura dos eixos o
desliga. Nos três fios o escravo dirige o fio nos bytes lidos, e o
modelo acusa conflito se o mestre ainda dirige.
"""

from typing import override

from cocotb.handle import LogicObject

from tests.python.utils.spi_slave import SlavePins, SpiSlave

REG_DEVID = 0x00
REG_BW_RATE = 0x2C
REG_POWER_CTL = 0x2D
REG_INT_ENABLE = 0x2E
REG_DATA_FORMAT = 0x31
REG_DATAX0 = 0x32
DEVID_VALUE = 0xE5
READ_BIT = 0x80
BURST_BIT = 0x40
ADDRESS_MASK = 0x3F
DATA_READY = 0x80
AXIS_BYTES = 6
WORD_MASK = 0xFFFF


class Adxl345Model(SpiSlave):  # pylint: disable=too-many-instance-attributes
    """ADXL345 com o arquivo de registradores e o pino INT1."""

    def __init__(
        self,
        pins: SlavePins,
        oe: LogicObject,
        int1: LogicObject,
        three_wire: bool,
    ) -> None:
        """Crie o acelerômetro.

        Parameters
        ----------
        pins : SlavePins
            Pinos SCLK, MOSI, MISO e seleção de chip.
        oe : LogicObject
            Habilitação do driver de MOSI do mestre.
        int1 : LogicObject
            Pino INT1, dirigido pelo modelo.
        three_wire : bool
            Verdadeiro se o fio de dados é compartilhado.
        """
        super().__init__(pins, (1, 1), 8)
        self.oe = oe
        self.int1 = int1
        self.three_wire = three_wire
        self.regs = {REG_DEVID: DEVID_VALUE}
        self.writes: list[tuple[int, int]] = []
        self.frames: list[str] = []
        self._command: int | None = None
        self._address = 0
        self._read = False
        self._touched_data = False

    def set_axes(self, x_axis: int, y_axis: int, z_axis: int) -> None:
        """Apresente uma amostra nova e, se habilitado, levante INT1.

        Parameters
        ----------
        x_axis : int
            Eixo X, inteiro de 16 bits com sinal.
        y_axis : int
            Eixo Y.
        z_axis : int
            Eixo Z.
        """
        for index, value in enumerate((x_axis, y_axis, z_axis)):
            self.regs[REG_DATAX0 + 2 * index] = value & 0xFF
            self.regs[REG_DATAX0 + 2 * index + 1] = (value >> 8) & 0xFF
        if self.regs.get(REG_INT_ENABLE, 0) & DATA_READY:
            self.int1.value = 1

    @override
    def frame_start(self) -> None:
        """Comece um quadro à espera do comando."""
        self._command = None
        self._touched_data = False

    @override
    def frame_end(self) -> None:
        """Termine o quadro e desligue INT1 se os eixos foram lidos."""
        if self._touched_data:
            self.int1.value = 0
        self.frames.append("leitura" if self._read else "escrita")

    @override
    def load_word(self) -> int:
        """Devolva o próximo byte lido, ou um sem efeito.

        Returns
        -------
        int
            Byte transmitido.
        """
        if self._command is None or not self._read:
            return 0xFF
        value = self.regs.get(self._address, 0)
        if REG_DATAX0 <= self._address < REG_DATAX0 + AXIS_BYTES:
            self._touched_data = True
        self._address += 1
        return value

    @override
    def store_word(self, value: int) -> None:
        """Receba o comando ou um byte escrito.

        Parameters
        ----------
        value : int
            Byte recebido do mestre.
        """
        if self._command is None:
            self._command = value
            self._read = bool(value & READ_BIT)
            self._address = value & ADDRESS_MASK
        elif not self._read:
            self.regs[self._address] = value
            self.writes.append((self._address, value))
            self._address += 1

    @override
    def _edge(self, level: int) -> None:
        """Trate uma borda e acuse conflito no fio de dados."""
        super()._edge(level)
        if self.three_wire and self._read and self._command is not None:
            data_phase = self._address > (self._command & ADDRESS_MASK)
            if data_phase and int(self.oe.value) == 1:
                self.errors.append("o mestre dirige o fio nos bytes lidos")

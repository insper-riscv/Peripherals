"""Modelo comportamental do acelerômetro ADXL345 no I2C.

O modelo é uma SUPOSIÇÃO a partir do que se lembra da folha de dados,
que não está no repositório; os manuais da DE10-Lite e da DE0-Nano só
dão a interface (endereços de 7 bits 0x1D e 0x53 conforme o pino SDO, e
a seleção de chip em nível alto para o modo I2C). Cada suposição está
marcada abaixo.

SUPOSIÇÕES. O primeiro byte depois do endereço de escrita é o ponteiro
de registrador e os seguintes são escritos com o ponteiro avançando; a
leitura devolve o registrador do ponteiro, que avança a cada byte.
DEVID vale 0xE5. Os eixos ficam em 0x32 a 0x37, byte baixo primeiro.
INT_ENABLE em 0x2E com o bit 7 liga o dado pronto, INT_MAP em 0x2F com o
bit 7 leva o dado pronto para INT2 em vez de INT1, e a leitura dos eixos
desliga o pino.
"""

from typing import override

from tests.python.utils.dut import Adxl345I2cDut
from tests.python.utils.i2c_eeprom import I2cEeprom

REG_DEVID = 0x00
REG_BW_RATE = 0x2C
REG_POWER_CTL = 0x2D
REG_INT_ENABLE = 0x2E
REG_INT_MAP = 0x2F
REG_DATA_FORMAT = 0x31
REG_DATAX0 = 0x32
DEVID_VALUE = 0xE5
REGISTER_COUNT = 0x40
DATA_READY = 0x80
INT2_BIT = 0x80
AXIS_BYTES = 6


class Adxl345I2cModel(I2cEeprom):
    """ADXL345 como escravo I2C, com o arquivo de registradores e INT.

    Attributes
    ----------
    address : int
        Endereço de 7 bits em que o modelo responde.
    writes : list[tuple[int, int]]
        Registradores escritos pelo mestre, na ordem.
    """

    def __init__(self, dut: Adxl345I2cDut, address: int) -> None:
        """Crie o acelerômetro.

        Parameters
        ----------
        dut : Adxl345I2cDut
            Bancada com as linhas e os pinos de interrupção.
        address : int
            Endereço de 7 bits do escravo.
        """
        super().__init__(dut, size=REGISTER_COUNT, page=REGISTER_COUNT)
        self.adxl = dut
        self.address = address
        self.writes: list[tuple[int, int]] = []
        self.memory[:] = bytes(REGISTER_COUNT)
        self.memory[REG_DEVID] = DEVID_VALUE

    def set_axes(self, x_axis: int, y_axis: int, z_axis: int) -> None:
        """Apresente uma amostra nova e, se habilitado, levante o pino.

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
            self.memory[REG_DATAX0 + 2 * index] = value & 0xFF
            self.memory[REG_DATAX0 + 2 * index + 1] = (value >> 8) & 0xFF
        if self.memory[REG_INT_ENABLE] & DATA_READY:
            self._drive_interrupt(1)

    def _drive_interrupt(self, level: int) -> None:
        """Dirija o pino escolhido por INT_MAP.

        Parameters
        ----------
        level : int
            Nível do pino.
        """
        if self.memory[REG_INT_MAP] & INT2_BIT:
            self.adxl.i_adxl_int2.value = level
        else:
            self.adxl.i_adxl_int1.value = level

    def _take_address(self, value: int) -> bool:
        """Confira o endereço e ajuste o sentido da transferência.

        Parameters
        ----------
        value : int
            Byte de endereço com o bit de leitura ou escrita.

        Returns
        -------
        bool
            Verdadeiro para ACK.
        """
        flags = self._s.f
        flags.sending = bool(value & 1)
        flags.writing = not flags.sending
        if (value >> 1) == self.address:
            return True
        flags.receiving = False
        flags.ignoring = True
        self.counts.nacked_addresses += 1
        return False

    @override
    def _take_byte(self) -> bool:
        """Receba um byte do mestre e devolva o ACK.

        Returns
        -------
        bool
            Verdadeiro para ACK.
        """
        s = self._s
        value = s.b.shift
        if s.b.byte_index == 0:
            return self._take_address(value)
        if s.b.byte_index == 1:
            s.pointer = value % REGISTER_COUNT
            return True
        self.memory[s.pointer] = value
        self.writes.append((s.pointer, value))
        s.pointer = (s.pointer + 1) % REGISTER_COUNT
        return True

    @override
    def _load_next(self) -> None:
        """Ponha o próximo byte na linha e desligue o pino nos eixos."""
        pointer = self._s.pointer
        super()._load_next()
        if REG_DATAX0 <= pointer < REG_DATAX0 + AXIS_BYTES:
            self._drive_interrupt(0)

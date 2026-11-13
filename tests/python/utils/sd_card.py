"""Modelo comportamental de um cartão SD SDHC no modo SPI.

O modelo responde ao CMD0, CMD8, CMD55, ACMD41, CMD58, CMD17 e CMD24 com
as respostas R1 e R7 do cartão real, deixa um byte de espera antes de
cada resposta, confere o CRC7 do CMD0 e do CMD8, o CRC16 do setor
escrito e a quantidade de clocks com a seleção de chip em nível alto.
"""

from collections import deque
from dataclasses import dataclass, field
from typing import Protocol

import cocotb
from cocotb.handle import LogicObject
from cocotb.triggers import First

SECTOR_BYTES = 512
CMD_BYTES = 6
BYTE_BITS = 8
CMD_MASK = 0xC0
CMD_START = 0x40
START_CLOCKS = 74
TOKEN_START = 0xFE
DATA_ACCEPTED = 0x05
DATA_CRC_ERROR = 0x0B
R1_IDLE = 0x01
R1_ILLEGAL = 0x04
R7_BODY = (0x00, 0x00, 0x01, 0xAA)
OCR_READY = (0xC0, 0xFF, 0x80, 0x00)
OCR_BUSY = (0x00, 0xFF, 0x80, 0x00)
ACMD41_BUSY_REPLIES = 2
WRITE_BUSY_BYTES = 3
CMD_GO_IDLE, CMD_SEND_IF, CMD_READ, CMD_WRITE = 0, 8, 17, 24
CMD_APP, CMD_OCR, CMD_ACMD41 = 55, 58, 41


class CardPins(Protocol):
    """Pinos do cartão vistos do lado do mestre."""

    o_sd_sclk: LogicObject
    o_sd_mosi: LogicObject
    o_sd_cs_n: LogicObject
    i_sd_miso: LogicObject


def crc7(data: bytes) -> int:
    """Obtenha o CRC7 de um comando SD (polinômio x^7 + x^3 + 1).

    Parameters
    ----------
    data : bytes
        Os cinco primeiros bytes do comando.

    Returns
    -------
    int
        O CRC de sete bits.
    """
    crc = 0
    for byte in data:
        for bit in range(7, -1, -1):
            feedback = ((crc >> 6) & 1) ^ ((byte >> bit) & 1)
            crc = (crc << 1) & 0x7F
            if feedback:
                crc ^= 0x09
    return crc


def crc16(data: bytes) -> int:
    """Obtenha o CRC16-CCITT de um bloco de dados (polinômio 0x1021).

    Parameters
    ----------
    data : bytes
        Os bytes do bloco.

    Returns
    -------
    int
        O CRC de dezesseis bits, com valor inicial zero.
    """
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


def command_frame(index: int, argument: int, crc: int = 0) -> bytes:
    """Monte o quadro de seis bytes de um comando.

    Parameters
    ----------
    index : int
        Número do comando.
    argument : int
        Argumento de 32 bits.
    crc : int
        CRC7 já calculado, ou zero para calcular.

    Returns
    -------
    bytes
        Quadro com o bit de parada no último byte.
    """
    body = bytes([0x40 | index]) + argument.to_bytes(4, "big")
    return body + bytes([((crc or crc7(body)) << 1) | 1])


@dataclass
class CardState:
    """Estado do protocolo do cartão."""

    frame: list[int] = field(default_factory=list[int])
    mode: str = "idle"
    prefix_app: bool = False
    ready: bool = False
    acmd41_calls: int = 0
    write_sector: int = 0
    rx_byte: int = 0
    rx_bits: int = 0


class SpiCard:
    """Cartão SD SDHC no modo SPI, ligado aos pinos do mestre."""

    def __init__(self, dut: CardPins, sectors: dict[int, bytes]) -> None:
        """Crie o cartão com o conteúdo inicial dos setores.

        Parameters
        ----------
        dut : CardPins
            Pinos do mestre.
        sectors : dict[int, bytes]
            Conteúdo dos setores, de 512 bytes cada.
        """
        self.dut = dut
        self.sectors = sectors
        self.errors: list[str] = []
        self.commands: list[int] = []
        self.start_clocks = 0
        self.state = CardState()
        self._out: deque[int] = deque()

    def start(self) -> None:
        """Inicie o processo que acompanha os pinos."""
        self.dut.i_sd_miso.value = 1
        cocotb.start_soon(self._run())

    def _queue(self, values: list[int]) -> None:
        """Enfileire bytes, do bit mais significativo ao menos."""
        for value in values:
            self._out.extend((value >> bit) & 1 for bit in range(7, -1, -1))

    async def _run(self) -> None:
        """Acompanhe SCLK e a seleção de chip."""
        sclk = self.dut.o_sd_sclk
        cs_n = self.dut.o_sd_cs_n
        last = int(sclk.value)
        while True:
            await First(sclk.value_change, cs_n.value_change)
            level = int(sclk.value)
            if int(cs_n.value) == 1:
                self._deselected(level, last)
            elif level != last:
                self._clock(level)
            last = level

    def _deselected(self, level: int, last: int) -> None:
        """Conte clocks sem seleção e abandone o quadro em andamento."""
        if level == 1 and last == 0:
            self.start_clocks += 1
        self.state.frame = []
        self.state.mode = "idle"
        self._out.clear()
        self.state.rx_bits = 0
        self.state.rx_byte = 0
        self.dut.i_sd_miso.value = 1

    def _clock(self, level: int) -> None:
        """Trate uma borda de SCLK com o cartão selecionado."""
        state = self.state
        if level == 1:
            state.rx_byte = (state.rx_byte << 1) | int(
                self.dut.o_sd_mosi.value
            )
            state.rx_bits += 1
            if state.rx_bits == BYTE_BITS:
                value, state.rx_byte, state.rx_bits = state.rx_byte, 0, 0
                self._on_byte(value)
        else:
            self.dut.i_sd_miso.value = self._out.popleft() if self._out else 1

    def _on_byte(self, value: int) -> None:
        """Trate um byte inteiro vindo do mestre."""
        handlers = {
            "idle": self._idle_byte,
            "cmd": self._cmd_byte,
            "token": self._token_byte,
            "block": self._block_byte,
        }
        handlers[self.state.mode](value)

    def _idle_byte(self, value: int) -> None:
        """Reconheça o início de um comando."""
        if value & CMD_MASK == CMD_START:
            self.state.frame = [value]
            self.state.mode = "cmd"

    def _cmd_byte(self, value: int) -> None:
        """Acumule os bytes de um comando e execute o quadro inteiro."""
        state = self.state
        state.frame.append(value)
        if len(state.frame) == CMD_BYTES:
            state.mode = "idle"
            self._command(bytes(state.frame))

    def _token_byte(self, value: int) -> None:
        """Espere o token de início do setor a escrever."""
        if value == TOKEN_START:
            self.state.mode = "block"
            self.state.frame = []

    def _block_byte(self, value: int) -> None:
        """Acumule o setor a escrever e o seu CRC16."""
        state = self.state
        state.frame.append(value)
        if len(state.frame) == SECTOR_BYTES + 2:
            state.mode = "idle"
            self._finish_write()

    def _command(self, frame: bytes) -> None:
        """Execute um comando completo e enfileire a resposta."""
        state = self.state
        index = frame[0] & 0x3F
        argument = int.from_bytes(frame[1:5], "big")
        self.commands.append(index)
        if frame[5] & 1 == 0:
            self.errors.append(f"CMD{index} sem bit de parada")
        if index in (CMD_GO_IDLE, CMD_SEND_IF) and (
            frame[5] >> 1 != crc7(frame[:5])
        ):
            self.errors.append(f"CRC7 errado no CMD{index}")
        app = state.prefix_app
        state.prefix_app = False
        reply = self._reply(index, argument, app)
        self._queue([0xFF, *reply])

    def _reply(self, index: int, argument: int, app: bool) -> list[int]:
        """Escolha os bytes de resposta a um comando."""
        state = self.state
        idle = 0x00 if state.ready else R1_IDLE
        if index == CMD_GO_IDLE:
            if self.start_clocks < START_CLOCKS:
                self.errors.append("menos de 74 clocks com CS alto")
            state.ready = False
            return [R1_IDLE]
        if index == CMD_SEND_IF:
            return [R1_IDLE, *R7_BODY]
        if index == CMD_APP:
            state.prefix_app = True
            return [idle]
        if index == CMD_ACMD41 and app:
            return [self._acmd41()]
        if index == CMD_OCR:
            return [idle, *(OCR_READY if state.ready else OCR_BUSY)]
        return self._block_command(index, argument, idle)

    def _acmd41(self) -> int:
        """Responda ao ACMD41 ficando pronto após algumas consultas."""
        state = self.state
        state.acmd41_calls += 1
        if state.acmd41_calls > ACMD41_BUSY_REPLIES:
            state.ready = True
        return 0x00 if state.ready else R1_IDLE

    def _block_command(
        self, index: int, argument: int, idle: int
    ) -> list[int]:
        """Responda ao CMD17 e ao CMD24."""
        state = self.state
        if index not in (CMD_READ, CMD_WRITE) or not state.ready:
            return [idle | R1_ILLEGAL]
        if index == CMD_WRITE:
            state.write_sector = argument
            state.mode = "token"
            return [0x00]
        data = self.sectors.get(argument, bytes(SECTOR_BYTES))
        crc = crc16(data)
        return [0x00, 0xFF, TOKEN_START, *data, crc >> 8, crc & 0xFF]

    def _finish_write(self) -> None:
        """Confira o CRC16 do setor escrito e guarde o conteúdo."""
        block = bytes(self.state.frame)
        data, crc = block[:SECTOR_BYTES], block[SECTOR_BYTES:]
        good = int.from_bytes(crc, "big") == crc16(data)
        if good:
            self.sectors[self.state.write_sector] = data
        else:
            self.errors.append("CRC16 errado no setor escrito")
        busy = [0x00] * WRITE_BUSY_BYTES
        self._queue([DATA_ACCEPTED if good else DATA_CRC_ERROR, *busy])

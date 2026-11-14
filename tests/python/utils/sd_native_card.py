"""Modelo comportamental de um cartão SD SDHC no modo nativo.

O modelo acompanha SD_CLK, amostra CMD e DAT[3:0] do mestre na borda de
subida e apresenta os bits do cartão logo depois dessa mesma borda, como
um cartão real. Os CRC7 e CRC16 são calculados por divisão polinomial
sobre inteiros, de forma independente do registrador de deslocamento do
VHDL, e a lista ``KNOWN_CRC7`` traz respostas conhecidas da
especificação SD Physical Layer (de memória, não de fonte local).

O cartão responde ao CMD0, CMD8, CMD55, ACMD41, CMD2, CMD3, CMD7,
ACMD6, CMD13, CMD17 e CMD24, e aceita falhas injetadas (resposta
ausente, CRC errado, índice trocado, dado corrompido, estado de CRC
forçado e ocupado preso).
"""

from collections import deque
from collections.abc import Sequence
from dataclasses import dataclass, field

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.utils.dut import SdNativeDut

SECTOR_BYTES = 512
CMD_BITS = 48
BYTE_BITS = 8
CRC_BITS = 16
CMD_HEADER_BITS = 40
START_CLOCKS = 74
RCA = 0x1234
OCR_VOLTAGE = 0x00FF8000
OCR_READY = 0x80000000
OCR_CCS = 0x40000000
HCS = 0x40000000
IF_COND = 0x1AA
ACMD41_BUSY_REPLIES = 2
NCR_CLOCKS = 3
NAC_CLOCKS = 4
NST_CLOCKS = 2
SELECT_BUSY_CLOCKS = 20
WRITE_BUSY_CLOCKS = 30
TOKEN_ACCEPTED = 0b010
TOKEN_CRC_ERROR = 0b101
TOKEN_WRITE_ERROR = 0b110
STATE_IDLE, STATE_READY, STATE_IDENT, STATE_STBY, STATE_TRAN = range(5)
CMD_GO_IDLE, CMD_ALL_SEND_CID, CMD_SEND_RCA = 0, 2, 3
CMD_SELECT, CMD_SEND_IF, CMD_STATUS = 7, 8, 13
CMD_READ, CMD_WRITE, CMD_APP = 17, 24, 55
ACMD_BUS_WIDTH, ACMD_OP_COND = 6, 41
APP_CMD_FLAG = 1 << 5
READY_FOR_DATA = 1 << 8
WIDE_ARGUMENT = 2
CID_BODY = bytes(
    (
        0x03,
        0x53,
        0x44,
        0x53,
        0x55,
        0x30,
        0x38,
        0x47,
        0x80,
        0x12,
        0x34,
        0x56,
        0x78,
        0x01,
        0x2A,
    )
)
IDLE_NIBBLE = 0xF
LANE0_LOW = 0xE

# Pares (mensagem, CRC7) da especificação, de memória: CMD0, CMD8 com
# 0x1AA, CMD17 com zero, CMD55 com zero e ACMD41 com HCS.
KNOWN_CRC7 = (
    (bytes((0x40, 0, 0, 0, 0)), 0x4A),
    (bytes((0x48, 0, 0, 0x01, 0xAA)), 0x43),
    (bytes((0x51, 0, 0, 0, 0)), 0x2A),
    (bytes((0x77, 0, 0, 0, 0)), 0x32),
    (bytes((0x69, 0x40, 0, 0, 0)), 0x3B),
)


# CRC16 conhecidos: 512 bytes 0xFF (0x7FA1 na especificação SD), 512
# bytes zero e a mensagem de verificação "123456789" do CRC-CCITT.
KNOWN_CRC16 = (
    (bytes([0xFF]) * SECTOR_BYTES, 0x7FA1),
    (bytes(SECTOR_BYTES), 0x0000),
    (b"123456789", 0x31C3),
)


def to_bits(value: int, width: int) -> list[int]:
    """Converta um inteiro em bits, o mais significativo primeiro.

    Parameters
    ----------
    value : int
        Valor a converter.
    width : int
        Quantidade de bits.

    Returns
    -------
    list[int]
        Os bits do valor.
    """
    return [(value >> bit) & 1 for bit in range(width - 1, -1, -1)]


def from_bits(bits: Sequence[int]) -> int:
    """Converta bits, o mais significativo primeiro, em inteiro.

    Parameters
    ----------
    bits : Sequence[int]
        Os bits.

    Returns
    -------
    int
        O valor.
    """
    value = 0
    for bit in bits:
        value = (value << 1) | bit
    return value


def crc_divide(bits: Sequence[int], polynomial: int, width: int) -> int:
    """Obtenha um CRC por divisão polinomial sobre um inteiro.

    A mensagem, seguida de ``width`` zeros, é dividida pelo polinômio
    gerador, e o resto é o CRC. Não há registrador de deslocamento.

    Parameters
    ----------
    bits : Sequence[int]
        Bits da mensagem, o mais significativo primeiro.
    polynomial : int
        Termos do gerador abaixo de ``x ** width``.
    width : int
        Grau do gerador.

    Returns
    -------
    int
        O resto da divisão, de ``width`` bits.
    """
    remainder = from_bits(bits) << width
    generator = (1 << width) | polynomial
    for shift in range(len(bits) - 1, -1, -1):
        if (remainder >> (shift + width)) & 1:
            remainder ^= generator << shift
    return remainder


def crc7(bits: Sequence[int]) -> int:
    """Obtenha o CRC7 (x^7 + x^3 + 1) de uma lista de bits.

    Parameters
    ----------
    bits : Sequence[int]
        Bits da mensagem, o mais significativo primeiro.

    Returns
    -------
    int
        O CRC7.
    """
    return crc_divide(bits, 0x09, 7)


def crc16(bits: Sequence[int]) -> int:
    """Obtenha o CRC16 (x^16 + x^12 + x^5 + 1) de uma lista de bits.

    Parameters
    ----------
    bits : Sequence[int]
        Bits da mensagem, o mais significativo primeiro.

    Returns
    -------
    int
        O CRC16.
    """
    return crc_divide(bits, 0x1021, 16)


def bytes_to_bits(data: bytes) -> list[int]:
    """Converta bytes em bits, o mais significativo primeiro.

    Parameters
    ----------
    data : bytes
        Os bytes.

    Returns
    -------
    list[int]
        Os bits.
    """
    return [bit for byte in data for bit in to_bits(byte, 8)]


def lane_streams(data: bytes, wide: bool) -> list[list[int]]:
    """Separe um bloco no fluxo de bits de cada linha de dados.

    Com quatro linhas o primeiro nibble de cada byte é o mais
    significativo e DAT3 leva o bit mais significativo do nibble.

    Parameters
    ----------
    data : bytes
        Os bytes do bloco.
    wide : bool
        Verdadeiro para quatro linhas.

    Returns
    -------
    list[list[int]]
        Os fluxos de DAT0, DAT1, DAT2 e DAT3 (um só com uma linha).
    """
    if not wide:
        return [bytes_to_bits(data)]
    nibbles = [n for byte in data for n in (byte >> 4, byte & 0xF)]
    return [[(nib >> line) & 1 for nib in nibbles] for line in range(4)]


def merge_streams(streams: Sequence[Sequence[int]]) -> list[int]:
    """Junte os fluxos das linhas em palavras de quatro bits por clock.

    Parameters
    ----------
    streams : Sequence[Sequence[int]]
        Fluxos de bits, da linha 0 em diante; as ausentes valem 1.

    Returns
    -------
    list[int]
        Um valor de 4 bits por clock.
    """
    units: list[int] = []
    for index in range(len(streams[0])):
        value = 0xF
        for line, stream in enumerate(streams):
            value = (value & ~(1 << line)) | (stream[index] << line)
        units.append(value)
    return units


def split_streams(units: Sequence[int], wide: bool) -> list[list[int]]:
    """Desfaça ``merge_streams`` a partir do que o mestre enviou.

    Parameters
    ----------
    units : Sequence[int]
        Um valor de 4 bits por clock.
    wide : bool
        Verdadeiro para quatro linhas.

    Returns
    -------
    list[list[int]]
        O fluxo de cada linha ativa.
    """
    lines = 4 if wide else 1
    return [[(unit >> line) & 1 for unit in units] for line in range(lines)]


def streams_to_bytes(streams: Sequence[Sequence[int]], wide: bool) -> bytes:
    """Reconstrua os bytes de um bloco a partir dos fluxos das linhas.

    Parameters
    ----------
    streams : Sequence[Sequence[int]]
        Fluxos das linhas ativas.
    wide : bool
        Verdadeiro para quatro linhas.

    Returns
    -------
    bytes
        Os bytes do bloco.
    """
    if not wide:
        bits = streams[0]
        return bytes(
            from_bits(bits[index:][:BYTE_BITS])
            for index in range(0, len(bits), BYTE_BITS)
        )
    nibbles = [
        sum(streams[line][index] << line for line in range(4))
        for index in range(len(streams[0]))
    ]
    return bytes(
        (nibbles[index] << 4) | nibbles[index + 1]
        for index in range(0, len(nibbles), 2)
    )


def data_units(data: bytes, wide: bool) -> list[int]:
    """Monte os valores de DAT[3:0] de um bloco que o cartão envia.

    Parameters
    ----------
    data : bytes
        Os 512 bytes do bloco.
    wide : bool
        Verdadeiro para quatro linhas.

    Returns
    -------
    list[int]
        Início, dados, CRC16 de cada linha e fim, um valor por clock.
    """
    streams = lane_streams(data, wide)
    crcs = [to_bits(crc16(stream), 16) for stream in streams]
    start = IDLE_NIBBLE & ~(IDLE_NIBBLE if wide else 1)
    return [
        start,
        *merge_streams(streams),
        *merge_streams(crcs),
        IDLE_NIBBLE,
    ]


def short_response(
    index: int, argument: int, bad_crc: bool = False, end: int = 1
) -> list[int]:
    """Monte uma resposta curta com CRC7 (R1, R6 ou R7).

    Parameters
    ----------
    index : int
        Índice da resposta.
    argument : int
        Argumento de 32 bits.
    bad_crc : bool
        Verdadeiro para estragar o CRC7.
    end : int
        Valor do bit de fim.

    Returns
    -------
    list[int]
        Os 48 bits da resposta.
    """
    body = [0, 0, *to_bits(index, 6), *to_bits(argument, 32)]
    crc = crc7(body) ^ (0x55 if bad_crc else 0)
    return [*body, *to_bits(crc, 7), end]


def long_response(body: list[int], bad_crc: bool = False) -> list[int]:
    """Monte uma resposta longa (R2) com o CRC7 do corpo.

    Parameters
    ----------
    body : list[int]
        Os 120 bits do CID ou CSD.
    bad_crc : bool
        Verdadeiro para estragar o CRC7.

    Returns
    -------
    list[int]
        Os 136 bits da resposta.
    """
    crc = crc7(body) ^ (0x55 if bad_crc else 0)
    return [0, 0, *([1] * 6), *body, *to_bits(crc, 7), 1]


@dataclass
class CardState:
    """Estado do protocolo do cartão."""

    state: int = STATE_IDLE
    frame: list[int] = field(default_factory=list[int])
    app_next: bool = False
    acmd41_calls: int = 0
    wide: bool = False
    write_sector: int = 0
    receiving: bool = False
    units: list[int] = field(default_factory=list[int])


@dataclass
class Wires:
    """Filas dos bits do cartão e contagem de clocks."""

    cmd: deque[int] = field(default_factory=deque[int])
    dat: deque[int] = field(default_factory=deque[int])
    clocks: int = 0
    start_clocks: int | None = None


@dataclass
class Faults:
    """Falhas que o teste pede ao cartão para a próxima oportunidade."""

    silent: bool = False
    bad_crc: bool = False
    wrong_index: bool = False
    bad_data_crc: bool = False
    no_data: bool = False
    token: int | None = None
    stuck_busy: bool = False


class NativeCard:
    """Cartão SD SDHC no modo nativo, ligado aos pinos do mestre."""

    def __init__(self, dut: SdNativeDut, sectors: dict[int, bytes]) -> None:
        """Crie o cartão com o conteúdo inicial dos setores.

        Parameters
        ----------
        dut : SdNativeDut
            Pinos do mestre.
        sectors : dict[int, bytes]
            Conteúdo dos setores, de 512 bytes cada.
        """
        self.dut = dut
        self.sectors = sectors
        self.errors: list[str] = []
        self.commands: list[tuple[int, int]] = []
        self.state = CardState()
        self.faults = Faults()
        self.wires = Wires()
        self._handlers = {
            (False, CMD_GO_IDLE): self._go_idle,
            (False, CMD_SEND_IF): self._send_if,
            (False, CMD_APP): self._app,
            (False, CMD_ALL_SEND_CID): self._all_send_cid,
            (False, CMD_SEND_RCA): self._send_rca,
            (False, CMD_SELECT): self._select,
            (False, CMD_STATUS): self._read_status,
            (False, CMD_READ): self._read_block,
            (False, CMD_WRITE): self._write_block,
            (True, ACMD_OP_COND): self._acmd41,
            (True, ACMD_BUS_WIDTH): self._bus_width,
        }

    def start(self) -> None:
        """Inicie o processo que acompanha SD_CLK."""
        self.dut.i_sd_cmd.value = 1
        self.dut.i_sd_dat.value = IDLE_NIBBLE
        cocotb.start_soon(self._run())

    def _host_cmd(self) -> int:
        """Devolva o bit que o mestre aplica a CMD."""
        if int(self.dut.o_sd_cmd_oe.value) == 1:
            return int(self.dut.o_sd_cmd.value)
        return 1

    def _host_dat(self) -> int:
        """Devolva os bits que o mestre aplica a DAT[3:0]."""
        enable = int(self.dut.o_sd_dat_oe.value)
        return (int(self.dut.o_sd_dat.value) & enable) | (~enable & 0xF)

    async def _run(self) -> None:
        """Trate cada borda de subida de SD_CLK."""
        while True:
            await RisingEdge(self.dut.o_sd_clk)
            self.wires.clocks += 1
            self._receive_cmd(self._host_cmd())
            self._receive_data(self._host_dat())
            cmd = self.wires.cmd.popleft() if self.wires.cmd else 1
            dat = self.wires.dat.popleft() if self.wires.dat else IDLE_NIBBLE
            self.dut.i_sd_cmd.value = cmd
            self.dut.i_sd_dat.value = dat

    def _receive_cmd(self, bit: int) -> None:
        """Acumule um bit do comando e execute o quadro completo."""
        state = self.state
        if not state.frame:
            if bit == 0:
                state.frame = [0]
                if self.wires.start_clocks is None:
                    self.wires.start_clocks = self.wires.clocks - 1
            return
        state.frame.append(bit)
        if len(state.frame) == CMD_BITS:
            frame = state.frame
            state.frame = list[int]()
            self._command(frame)

    def _command(self, frame: list[int]) -> None:
        """Confira um quadro de comando e responda a ele."""
        state = self.state
        index = from_bits(frame[2:8])
        argument = from_bits(frame[8:40])
        if frame[1] != 1 or frame[47] != 1:
            self.errors.append(f"CMD{index} com bit de transmissão ou fim")
        if from_bits(frame[40:47]) != crc7(frame[:40]):
            self.errors.append(f"CRC7 errado no CMD{index}")
            return
        app = state.app_next
        state.app_next = False
        self.commands.append((index + (100 if app else 0), argument))
        if self.faults.silent:
            self.faults.silent = False
            return
        self._execute(index, argument, app)

    def _status(self) -> int:
        """Monte o estado do cartão da resposta R1."""
        flag = APP_CMD_FLAG if self.state.app_next else 0
        return (self.state.state << 9) | READY_FOR_DATA | flag

    def _short(self, index: int, argument: int) -> list[int]:
        """Monte uma resposta curta com CRC7 (R1, R6 ou R7)."""
        if self.faults.wrong_index:
            self.faults.wrong_index = False
            index ^= 0x01
        return short_response(index, argument, self._take_bad_crc())

    def _take_bad_crc(self) -> bool:
        """Consuma o pedido de CRC errado, se houver."""
        bad = self.faults.bad_crc
        self.faults.bad_crc = False
        return bad

    def _long(self) -> list[int]:
        """Monte a resposta R2 com o CID e o seu CRC7."""
        return long_response(bytes_to_bits(CID_BODY), self._take_bad_crc())

    def _send(self, response: list[int], busy: int = 0) -> None:
        """Enfileire a resposta e o ocupado que a segue em DAT0."""
        self.wires.cmd.extend([1] * (NCR_CLOCKS - 1))
        self.wires.cmd.extend(response)
        if busy:
            lead = NCR_CLOCKS - 1 + len(response) + NST_CLOCKS
            self.wires.dat.extend([IDLE_NIBBLE] * lead)
            self.wires.dat.extend([LANE0_LOW] * busy)
            if self.faults.stuck_busy:
                self.wires.dat.extend([LANE0_LOW] * 100000)
                self.faults.stuck_busy = False

    def _execute(self, index: int, argument: int, app: bool) -> None:
        """Escolha o tratador do comando e deixe-o responder."""
        handler = self._handlers.get((app, index))
        if handler is None:
            self.errors.append(f"comando {index} ilegal (app {app})")
            return
        handler(argument)

    def _go_idle(self, _argument: int) -> None:
        """Trate o CMD0: volte ao estado ocioso, sem resposta."""
        if (self.wires.start_clocks or 0) < START_CLOCKS:
            self.errors.append("menos de 74 clocks antes do CMD0")
        self.state.state = STATE_IDLE

    def _send_if(self, argument: int) -> None:
        """Trate o CMD8: devolva o R7 com o eco do argumento."""
        if self.state.state == STATE_IDLE:
            self._send(self._short(CMD_SEND_IF, argument & 0xFFF))

    def _app(self, _argument: int) -> None:
        """Trate o CMD55: o comando seguinte é de aplicação."""
        self.state.app_next = True
        self._send(self._short(CMD_APP, self._status()))

    def _all_send_cid(self, _argument: int) -> None:
        """Trate o CMD2: devolva o CID em R2."""
        if self.state.state == STATE_READY:
            self.state.state = STATE_IDENT
            self._send(self._long())

    def _send_rca(self, _argument: int) -> None:
        """Trate o CMD3: publique o RCA em R6."""
        if self.state.state == STATE_IDENT:
            self.state.state = STATE_STBY
            status = (self.state.state << 9) | READY_FOR_DATA
            self._send(self._short(CMD_SEND_RCA, (RCA << 16) | status))

    def _select(self, argument: int) -> None:
        """Trate o CMD7: selecione o cartão e fique ocupado em DAT0."""
        if argument >> 16 == RCA:
            self.state.state = STATE_TRAN
            self._send(
                self._short(CMD_SELECT, self._status()), SELECT_BUSY_CLOCKS
            )

    def _bus_width(self, argument: int) -> None:
        """Trate o ACMD6: escolha entre uma e quatro linhas de dados."""
        self.state.wide = argument & 3 == WIDE_ARGUMENT
        self._send(self._short(ACMD_BUS_WIDTH, self._status()))

    def _acmd41(self, argument: int) -> None:
        """Responda ao ACMD41 ficando pronto após algumas consultas."""
        state = self.state
        state.acmd41_calls += 1
        ready = state.acmd41_calls > ACMD41_BUSY_REPLIES
        ocr = OCR_VOLTAGE
        if ready:
            ocr |= OCR_READY | (OCR_CCS if argument & HCS else 0)
            state.state = STATE_READY
        body = [0, 0, *([1] * 6), *to_bits(ocr, 32), *([1] * 7), 1]
        self._send(body)

    def _in_transfer_state(self, index: int) -> bool:
        """Aceite o comando de bloco só em transferência."""
        if self.state.state != STATE_TRAN:
            self.errors.append(f"CMD{index} fora do estado de transferência")
            return False
        self._send(self._short(index, self._status()))
        return True

    def _read_status(self, _argument: int) -> None:
        """Trate o CMD13: devolva o estado do cartão em R1."""
        self._in_transfer_state(CMD_STATUS)

    def _read_block(self, argument: int) -> None:
        """Trate o CMD17: devolva R1 e o bloco pelas linhas de dados."""
        if not self._in_transfer_state(CMD_READ):
            return
        if self.faults.no_data:
            self.faults.no_data = False
            return
        data = self.sectors.get(argument, bytes(SECTOR_BYTES))
        units = data_units(data, self.state.wide)
        if self.faults.bad_data_crc:
            self.faults.bad_data_crc = False
            units[-3] ^= 0x1
        lead = NCR_CLOCKS - 1 + CMD_BITS + NAC_CLOCKS
        self.wires.dat.extend([IDLE_NIBBLE] * lead)
        self.wires.dat.extend(units)

    def _write_block(self, argument: int) -> None:
        """Trate o CMD24: devolva R1 e espere o bloco do mestre."""
        if self._in_transfer_state(CMD_WRITE):
            self.state.write_sector = argument
            self.state.receiving = True
            self.state.units = []

    def _receive_data(self, dat: int) -> None:
        """Acumule os clocks de um bloco escrito pelo mestre."""
        state = self.state
        if not state.receiving:
            return
        wide = state.wide
        if not state.units:
            if dat & 1 == 0:
                state.units = [dat]
            return
        state.units.append(dat)
        total = 1 + (1024 if wide else 4096) + 16 + 1
        if len(state.units) == total:
            state.receiving = False
            self._finish_write(state.units[1:], wide)
            state.units = []

    def _finish_write(self, units: list[int], wide: bool) -> None:
        """Confira o bloco escrito e responda com o estado de CRC."""
        count = 1024 if wide else 4096
        streams = split_streams(units[:count], wide)
        received = split_streams(units[count:][:CRC_BITS], wide)
        end = units[count + CRC_BITS]
        good = all(
            from_bits(received[line]) == crc16(streams[line])
            for line in range(len(streams))
        )
        if end & (0xF if wide else 1) != (0xF if wide else 1):
            self.errors.append("bit de fim do bloco escrito")
        if good:
            self.sectors[self.state.write_sector] = streams_to_bytes(
                streams, wide
            )
        else:
            self.errors.append("CRC16 errado no bloco escrito")
        token = TOKEN_ACCEPTED if good else TOKEN_CRC_ERROR
        if self.faults.token is not None:
            token, self.faults.token = self.faults.token, None
        reply = [0, *to_bits(token, 3), 1]
        self.wires.dat.extend([IDLE_NIBBLE] * (NST_CLOCKS - 1))
        self.wires.dat.extend(0xE | bit for bit in reply)
        self.wires.dat.extend([0xE] * WRITE_BUSY_CLOCKS)

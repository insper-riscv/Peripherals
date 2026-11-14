"""Controle de dados do SD: leitura e escrita de bloco, CRC16 e erros.

O teste faz o papel do gerador de clock, com um pulso de subida e um de
descida em ciclos alternados, do buffer, uma memória de leitura
síncrona, e do cartão, que responde pelas linhas DAT nas subidas. Os
CRC16 são calculados por divisão polinomial, de forma independente do
registrador de deslocamento do VHDL.
"""

from collections import deque

import cocotb

from tests.python.utils.check import check
from tests.python.utils.dut import SdDataDut
from tests.python.utils.sd_native_card import (
    SECTOR_BYTES,
    data_units,
    split_streams,
    streams_to_bytes,
    to_bits,
)
from tests.python.utils.sd_strobe import (
    Strobes,
    flags,
    reset_block,
    run_until_done,
)

LIMIT = 40000
TIMEOUT = 50
PATTERN = bytes((index * 11 + 5) & 0xFF for index in range(SECTOR_BYTES))
E_TIMEOUT, E_CRC, E_FRAME, E_WRITE_CRC, E_WRITE = 1, 2, 4, 8, 16
ERROR_SIGNALS = (
    "o_err_timeout",
    "o_err_crc",
    "o_err_frame",
    "o_err_write_crc",
    "o_err_write",
)
IDLE = 0xF
LANE0_LOW = 0xE
BLOCK_WORDS = 128
WIDE_UNITS = 1024
NARROW_UNITS = 4096
TOKEN_OK = 0b010


class Bench:
    """Gerador de pulsos, buffer, cartão simples e monitor dos dados."""

    def __init__(self, dut: SdDataDut) -> None:
        """Ligue o banco ao controle de dados.

        Parameters
        ----------
        dut : SdDataDut
            Controle exercitado pelo teste.
        """
        self.dut = dut
        self.strobes = Strobes(dut)
        self.launched: list[int] = []
        self.memory: dict[int, int] = {}
        self.line: deque[int] = deque()
        self.token_reply: list[int] = []

    async def cycle(self) -> bool:
        """Avance um ciclo e devolva o valor de ``o_done`` depois dele.

        Returns
        -------
        bool
            Verdadeiro se a transferência terminou neste ciclo.
        """
        dut = self.dut
        rising = self.strobes.drive()
        if rising:
            dut.i_dat.value = self.line.popleft() if self.line else IDLE
        write = int(dut.o_buf_we.value) == 1
        address = int(dut.o_buf_address.value)
        data = int(dut.o_buf_data.value)
        old = self.memory.get(address, 0)
        await self.strobes.edge()
        if write:
            self.memory[address] = data
        dut.i_buf_data.value = old
        if not rising:
            self._watch_lines()
        return int(dut.o_done.value) == 1

    def _watch_lines(self) -> None:
        """Registre os valores lançados e arme o estado de CRC."""
        dut = self.dut
        enable = int(dut.o_dat_oe.value)
        if enable != 0:
            self.launched.append(int(dut.o_dat.value) & enable)
        elif self.launched and self.token_reply:
            self.line.extend(self.token_reply)
            self.token_reply = []

    async def transfer(self, write: bool, wide: bool) -> list[int]:
        """Inicie uma transferência de bloco e espere o fim.

        Parameters
        ----------
        write : bool
            Verdadeiro para escrever no cartão.
        wide : bool
            Verdadeiro para quatro linhas.

        Returns
        -------
        list[int]
            Valores lançados nas linhas DAT pelo mestre, um por clock.
        """
        dut = self.dut
        self.launched = []
        dut.i_write.value = int(write)
        dut.i_wide.value = int(wide)
        dut.i_timeout.value = TIMEOUT
        dut.i_start.value = 1
        await self.cycle()
        dut.i_start.value = 0
        await run_until_done(self.cycle, LIMIT)
        return self.launched

    def errors(self) -> int:
        """Devolva os erros da última transferência, como máscara."""
        return flags(self.dut, *ERROR_SIGNALS)

    def load(self, data: bytes) -> None:
        """Grave um bloco na memória do buffer, palavra a palavra.

        Parameters
        ----------
        data : bytes
            Os 512 bytes do bloco.
        """
        for word in range(BLOCK_WORDS):
            start = 4 * word
            chunk = data[start:][:4]
            self.memory[word] = int.from_bytes(chunk, "little")

    def stored(self) -> bytes:
        """Devolva o conteúdo do buffer como bytes do bloco."""
        return b"".join(
            self.memory.get(word, 0).to_bytes(4, "little")
            for word in range(BLOCK_WORDS)
        )


async def setup(dut: SdDataDut) -> Bench:
    """Reinicie o controle e crie o banco de teste.

    Parameters
    ----------
    dut : SdDataDut
        Controle exercitado pelo teste.

    Returns
    -------
    Bench
        Banco ligado ao controle.
    """
    for name in ("i_abort", "i_start", "i_write", "i_wide", "i_buf_data"):
        getattr(dut, name).value = 0
    dut.i_dat.value = IDLE
    await reset_block(dut)
    return Bench(dut)


@cocotb.test()
async def test_block_read_in_both_widths(dut: SdDataDut) -> None:
    """O bloco lido chega inteiro ao buffer, com uma e quatro linhas."""
    bench = await setup(dut)
    for wide in (True, False):
        bench.memory.clear()
        bench.line.extend([IDLE] * 6 + data_units(PATTERN, wide))
        await bench.transfer(write=False, wide=wide)
        check(bench.errors() == 0, f"largura {wide}: {bench.errors()}")
        check(bench.stored() == PATTERN, f"conteúdo, largura {wide}")


@cocotb.test()
async def test_read_errors(dut: SdDataDut) -> None:
    """CRC16 errado, bit de fim errado e bloco ausente são acusados."""
    bench = await setup(dut)
    units = data_units(PATTERN, wide=True)
    bad = list(units)
    bad[-3] ^= 0x2
    bench.line.extend(bad)
    await bench.transfer(write=False, wide=True)
    check(bench.errors() == E_CRC, f"CRC16: {bench.errors()}")
    bad = [*units[:-1], 0xE]
    bench.line.extend(bad)
    await bench.transfer(write=False, wide=True)
    check(bench.errors() == E_FRAME, f"fim: {bench.errors()}")
    bench.line.clear()
    await bench.transfer(write=False, wide=True)
    check(bench.errors() == E_TIMEOUT, f"ausente: {bench.errors()}")


@cocotb.test()
async def test_block_write_in_both_widths(dut: SdDataDut) -> None:
    """O bloco escrito sai com o CRC16 de cada linha e é aceito."""
    bench = await setup(dut)
    for wide in (True, False):
        bench.load(PATTERN)
        bench.token_reply = [
            IDLE,
            0xE,
            *[0xE | b for b in to_bits(2, 3)],
            IDLE,
        ]
        sent = await bench.transfer(write=True, wide=wide)
        check(bench.errors() == 0, f"largura {wide}: {bench.errors()}")
        mask = 0xF if wide else 0x1
        expected = [unit & mask for unit in data_units(PATTERN, wide)]
        check(sent == expected, f"quadro enviado, largura {wide}")
        units = WIDE_UNITS if wide else NARROW_UNITS
        streams = split_streams(sent[1:][:units], wide)
        check(streams_to_bytes(streams, wide) == PATTERN, "dados enviados")
        check(int(dut.o_token.value) == TOKEN_OK, "estado de CRC")


@cocotb.test()
async def test_write_status_and_busy(dut: SdDataDut) -> None:
    """Os estados 101 e 110, o ocupado preso e a falta de estado."""
    bench = await setup(dut)
    for token, errors in ((0b101, E_WRITE_CRC), (0b110, E_WRITE)):
        bench.load(PATTERN)
        bench.token_reply = [IDLE, 0xE, *[0xE | b for b in to_bits(token, 3)]]
        bench.token_reply.append(IDLE)
        await bench.transfer(write=True, wide=True)
        check(bench.errors() == errors, f"estado {token:03b}")
        check(int(dut.o_token.value) == token)
    bench.load(PATTERN)
    bench.token_reply = [IDLE, 0xE, 0xE, 0xF, 0xE, 0xF]
    bench.token_reply += [LANE0_LOW] * (10 * TIMEOUT)
    await bench.transfer(write=True, wide=False)
    check(bench.errors() == E_TIMEOUT, "ocupado preso")
    bench.load(PATTERN)
    await bench.transfer(write=True, wide=False)
    check(bench.errors() == E_TIMEOUT, "sem estado de CRC")

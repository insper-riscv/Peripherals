"""Controle de comando do SD: quadro, respostas, ocupado e aborto.

O teste faz o papel do gerador de clock, com um pulso de subida e um de
descida em ciclos alternados, e do cartão, que responde pela linha CMD
nas subidas. O quadro enviado é comparado com um quadro montado com o
CRC7 calculado de forma independente.
"""

from collections import deque

import cocotb

from tests.python.utils.check import check
from tests.python.utils.dut import SdCmdDut
from tests.python.utils.sd_native_card import (
    CID_BODY,
    bytes_to_bits,
    crc7,
    long_response,
    short_response,
    to_bits,
)
from tests.python.utils.sd_strobe import (
    Strobes,
    flags,
    reset_block,
    run_until_done,
)

RSP_NONE, RSP_SHORT, RSP_SHORT_NO_CRC, RSP_LONG = range(4)
NCR = 64
GAP = 8
SHORT_BUSY = 10
LIMIT = 3000
TIMEOUT = 20
ARG = 0x1AA
IDX = 8
ERR_TIMEOUT, ERR_CRC, ERR_INDEX, ERR_FRAME = 1, 2, 4, 8
ERROR_SIGNALS = ("o_err_timeout", "o_err_crc", "o_err_index", "o_err_frame")
HEADER_BITS = 40
FRAME_BITS = 48
VECTORS = (
    (0, 0),
    (8, 0x1AA),
    (17, 0),
    (55, 0),
    (41, 0x40000000),
    (63, 0xFFFFFFFF),
    (2, 0x12345678),
)


class Bench:
    """Gerador de pulsos, cartão simples e monitor do controle."""

    def __init__(self, dut: SdCmdDut) -> None:
        """Ligue o banco ao controle de comando.

        Parameters
        ----------
        dut : SdCmdDut
            Controle exercitado pelo teste.
        """
        self.dut = dut
        self.strobes = Strobes(dut)
        self.launched: list[int] = []
        self.reply: list[int] = []
        self.line: deque[int] = deque()
        self.resp_seen = False
        self.dat_low = 0
        self.dat0: deque[int] = deque()

    async def cycle(self) -> bool:
        """Avance um ciclo e devolva o valor de `o_done` depois dele.

        Returns
        -------
        bool
            Verdadeiro se o comando terminou neste ciclo.
        """
        dut = self.dut
        rising = self.strobes.drive()
        if rising:
            dut.i_cmd.value = self.line.popleft() if self.line else 1
            dut.i_dat0.value = self.dat0.popleft() if self.dat0 else 1
        await self.strobes.edge()
        self.resp_seen = self.resp_seen or int(dut.o_resp_ok.value) == 1
        if not rising:
            self._watch_line()
        return int(dut.o_done.value) == 1

    def _watch_line(self) -> None:
        """Registre o bit lançado e arme a resposta ao soltar."""
        if int(self.dut.o_cmd_oe.value) == 1:
            self.launched.append(int(self.dut.o_cmd.value))
        elif self.launched and self.reply:
            self.line.extend(self.reply)
            self.dat0.extend([0] * self.dat_low)
            self.reply = []

    async def command(
        self, index: int, argument: int, response: int, wait_busy: int = 0
    ) -> list[int]:
        """Envie um comando e espere o fim.

        Parameters
        ----------
        index : int
            Índice do comando.
        argument : int
            Argumento do comando.
        response : int
            Formato da resposta esperada.
        wait_busy : int
            Espera por ocupado depois da resposta.

        Returns
        -------
        list[int]
            Bits lançados na linha CMD pelo mestre.
        """
        dut = self.dut
        self.launched = []
        self.line.clear()
        self.dat0.clear()
        dut.i_index.value = index
        dut.i_argument.value = argument
        dut.i_response.value = response
        dut.i_wait_busy.value = wait_busy
        dut.i_timeout.value = TIMEOUT
        dut.i_start.value = 1
        await self.cycle()
        dut.i_start.value = 0
        self.resp_seen = False
        await run_until_done(self.cycle, LIMIT)
        return self.launched

    def errors(self) -> int:
        """Devolva os erros do último comando, como máscara."""
        return flags(self.dut, *ERROR_SIGNALS)


async def setup(dut: SdCmdDut) -> Bench:
    """Reinicie o controle e crie o banco de teste.

    Parameters
    ----------
    dut : SdCmdDut
        Controle exercitado pelo teste.

    Returns
    -------
    Bench
        Banco ligado ao controle.
    """
    for name in ("i_abort", "i_start", "i_wait_busy"):
        getattr(dut, name).value = 0
    dut.i_cmd.value = 1
    dut.i_dat0.value = 1
    await reset_block(dut)
    return Bench(dut)


def expected_frame(index: int, argument: int) -> list[int]:
    """Monte o quadro de 48 bits do comando.

    Parameters
    ----------
    index : int
        Índice do comando.
    argument : int
        Argumento do comando.

    Returns
    -------
    list[int]
        Início, transmissão, índice, argumento, CRC7 e fim.
    """
    head = [0, 1, *to_bits(index, 6), *to_bits(argument, 32)]
    return [*head, *to_bits(crc7(head), 7), 1]


@cocotb.test()
async def test_command_frame_and_crc7(dut: SdCmdDut) -> None:
    """O quadro enviado tem 48 bits com o CRC7 da divisão polinomial."""
    bench = await setup(dut)
    for index, argument in VECTORS:
        sent = await bench.command(index, argument, RSP_NONE)
        check(len(sent) == FRAME_BITS, f"CMD{index}: {len(sent)} bits")
        check(sent == expected_frame(index, argument), f"CMD{index}")
        check(bench.errors() == 0 and not bench.resp_seen, "sem resposta")
        check(int(dut.o_cmd_oe.value) == 0 and int(dut.o_busy.value) == 0)


@cocotb.test()
async def test_short_response_and_its_checks(dut: SdCmdDut) -> None:
    """A resposta curta é aceita e cada erro de formato é acusado."""
    bench = await setup(dut)
    cases = (
        ("boa", short_response(IDX, ARG), 0, False),
        ("CRC7", short_response(IDX, ARG, bad_crc=True), ERR_CRC, True),
        ("índice", short_response(IDX ^ 1, ARG), ERR_INDEX, True),
        ("fim", short_response(IDX, ARG, end=0), ERR_FRAME, True),
    )
    for name, bits, errors, failed in cases:
        bench.reply = bits
        await bench.command(IDX, ARG, RSP_SHORT)
        check(bench.errors() == errors, f"{name}: erros {bench.errors()}")
        check(bench.resp_seen != failed, f"{name}: resposta válida")
    bench.reply = short_response(IDX, ARG)
    await bench.command(IDX, 0, RSP_SHORT)
    resp = int(dut.o_response.value)
    check(resp & 0xFFFFFFFF == ARG, "argumento da resposta")
    check((resp >> 32) & 0x3F == IDX, "índice da resposta")


@cocotb.test()
async def test_r3_is_not_checked(dut: SdCmdDut) -> None:
    """A resposta R3 não tem CRC7 nem índice a conferir."""
    bench = await setup(dut)
    ocr = 0xC0FF8000
    frame = [0, 0, *([1] * 6), *to_bits(ocr, 32), *([1] * 7), 1]
    bench.reply = list(frame)
    await bench.command(41, 0x40FF8000, RSP_SHORT_NO_CRC)
    check(bench.errors() == 0 and bench.resp_seen, "R3 aceita")
    check(int(dut.o_response.value) & 0xFFFFFFFF == ocr, "OCR")
    bench.reply = list(frame)
    await bench.command(41, 0x40FF8000, RSP_SHORT)
    check(bench.errors() & (ERR_CRC | ERR_INDEX) != 0, "R3 como R1 falha")


@cocotb.test()
async def test_long_response(dut: SdCmdDut) -> None:
    """A resposta R2 guarda os 120 bits e confere o CRC7 do corpo."""
    bench = await setup(dut)
    body = bytes_to_bits(CID_BODY)
    bench.reply = long_response(body)
    await bench.command(2, 0, RSP_LONG)
    check(bench.errors() == 0 and bench.resp_seen, "R2 aceita")
    value = int.from_bytes(CID_BODY, "big")
    check(int(dut.o_response.value) == value, "corpo da resposta")
    bench.reply = long_response(body, bad_crc=True)
    await bench.command(2, 0, RSP_LONG)
    check(bench.errors() == ERR_CRC and not bench.resp_seen, "CRC7 do R2")


@cocotb.test()
async def test_response_window(dut: SdCmdDut) -> None:
    """O bit de início vale até a 64a subida, e depois vem o prazo."""
    bench = await setup(dut)
    await bench.command(IDX, ARG, RSP_SHORT)
    check(bench.errors() == ERR_TIMEOUT, "sem resposta")
    for delay, errors in ((0, 0), (NCR - 1, 0), (NCR, ERR_TIMEOUT)):
        bench.reply = [1] * delay + short_response(IDX, ARG)
        await bench.command(IDX, ARG, RSP_SHORT)
        check(bench.errors() == errors, f"atraso {delay}: {bench.errors()}")


@cocotb.test()
async def test_busy_wait_and_abort(dut: SdCmdDut) -> None:
    """O R1b espera DAT0 subir, o prazo vence e o aborto solta."""
    bench = await setup(dut)
    bench.reply = short_response(IDX, ARG)
    bench.dat_low = len(bench.reply) + GAP + SHORT_BUSY
    await bench.command(IDX, ARG, RSP_SHORT, wait_busy=1)
    check(bench.errors() == 0, f"ocupado curto: {bench.errors()}")
    bench.reply = short_response(IDX, ARG)
    bench.dat_low = len(bench.reply) + GAP + 10 * TIMEOUT
    await bench.command(IDX, ARG, RSP_SHORT, wait_busy=1)
    check(bench.errors() == ERR_TIMEOUT, "ocupado preso")
    bench.dat_low = 0
    dut.i_index.value = IDX
    dut.i_response.value = RSP_SHORT
    dut.i_start.value = 1
    await bench.cycle()
    dut.i_start.value = 0
    for _ in range(30):
        await bench.cycle()
    check(int(dut.o_busy.value) == 1, "comando em andamento")
    dut.i_abort.value = 1
    await bench.cycle()
    dut.i_abort.value = 0
    check(int(dut.o_busy.value) == 0 and int(dut.o_cmd_oe.value) == 0)
    check(int(dut.o_done.value) == 0, "o aborto não sinaliza fim")

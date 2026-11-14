"""SD no modo nativo: comandos, respostas, blocos, erros e interrupções.

A configuração do teste usa ``CLOCK_HZ=3200000``, que dá o divisor de
reset 3 (SD_CLK de 400 kHz com o clock de 3,2 MHz). O software do teste
faz a inicialização e as leituras e escritas de setor que o exemplo em C
da documentação faz, contra o modelo de cartão nativo, que calcula os
CRC7 e CRC16 de forma independente.
"""

from itertools import pairwise

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import SdNativeDut
from tests.python.utils.sd_native_card import (
    CID_BODY,
    HCS,
    IF_COND,
    OCR_READY,
    OCR_VOLTAGE,
    RCA,
    SECTOR_BYTES,
    NativeCard,
)

ARG, CMD, RESP0, RESP1, RESP2, RESP3 = range(6)
STATUS, ERROR, CONTROL, DIVIDER, TIMEOUT, DATA, PTR = range(6, 13)

CMD_BUSY = 1 << 0
DATA_BUSY = 1 << 1
CMD_DONE = 1 << 2
DATA_DONE = 1 << 3
CARD_BUSY = 1 << 4
CMD_LINE = 1 << 5
TOKEN_SHIFT = 16
TOKEN_MASK = 0x7
TOKEN_ACCEPTED = 0b010
MIN_EDGES = 3
STATE_TRAN = 4
PATTERN_ARG = 0xDEADBEEF
PATTERN_DIVIDER = 0xBEEF
PATTERN_TIMEOUT = 0xABCDEF
PATTERN_WORD = 0x12345678
PATTERN_PTR = 0x55
CONTROL_ALL = 0x1F

E_CMD_TIMEOUT = 1 << 0
E_CMD_CRC = 1 << 1
E_CMD_INDEX = 1 << 2
E_CMD_FRAME = 1 << 3
E_DATA_TIMEOUT = 1 << 4
E_DATA_CRC = 1 << 5
E_DATA_FRAME = 1 << 6
E_WRITE_CRC = 1 << 7
E_WRITE_ERROR = 1 << 8
E_DROPPED = 1 << 9
E_ALL = (1 << 10) - 1

CLK_ENABLE = 1 << 0
WIDE_BUS = 1 << 1
CMD_IRQ_ENABLE = 1 << 2
DATA_IRQ_ENABLE = 1 << 3
ERROR_IRQ_ENABLE = 1 << 4
ABORT = 1 << 8

RSP_NONE, RSP_SHORT, RSP_SHORT_NO_CRC, RSP_LONG = range(4)
WAIT_BUSY = 1 << 8
DATA_EN = 1 << 9
DATA_WRITE = 1 << 10

CMD0, CMD2, CMD3, CMD7, CMD8 = 0, 2, 3, 7, 8
CMD13, CMD17, CMD24, CMD55, CMD41, CMD6 = 13, 17, 24, 55, 41, 6

RESET_DIVIDER = 3
FAST_DIVIDER = 0
DEFAULT_TIMEOUT = 2_500_000
POLL_LIMIT = 40000
POLL_STEP = 12
SECTOR = 7
SECTOR_PATTERN = bytes((index * 7 + 3) & 0xFF for index in range(SECTOR_BYTES))
WRITTEN_PATTERN = bytes((index ^ 0x5A) & 0xFF for index in range(SECTOR_BYTES))
SHORT_TIMEOUT = 300
WORD_MASK = 0xFFFFFFFF
CID_WORDS = 4
BLOCK_WORDS = SECTOR_BYTES // 4


async def setup(dut: SdNativeDut, attach: bool = True) -> NativeCard:
    """Reinicie o periférico e, se pedido, ligue o cartão.

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    attach : bool
        Falso para deixar as linhas do cartão em repouso, sem cartão.

    Returns
    -------
    NativeCard
        Cartão ligado aos pinos, com o setor de leitura gravado.
    """
    dut.i_sd_cmd.value = 1
    dut.i_sd_dat.value = 0xF
    await bus.reset(dut)
    card = NativeCard(dut, {SECTOR: SECTOR_PATTERN})
    if attach:
        card.start()
    return card


async def wait_status(dut: SdNativeDut, mask: int, value: int) -> int:
    """Leia STATUS até os bits de ``mask`` valerem ``value``.

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    mask : int
        Bits observados.
    value : int
        Valor esperado dos bits observados.

    Returns
    -------
    int
        Último valor de STATUS lido.

    """
    status = await bus.read(dut, STATUS)
    polls = 0
    while status & mask != value and polls < POLL_LIMIT:
        await bus.cycles(dut, POLL_STEP)
        status = await bus.read(dut, STATUS)
        polls += 1
    check(
        status & mask == value, f"STATUS {status:#x} sob a máscara {mask:#x}"
    )
    return status


async def command(
    dut: SdNativeDut, index: int, argument: int, flags: int = RSP_SHORT << 6
) -> int:
    """Envie um comando, espere o fim e devolva os erros (e os limpe).

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    index : int
        Índice do comando.
    argument : int
        Argumento do comando.
    flags : int
        Bits 10:6 do registrador CMD (formato, ocupado e dados).

    Returns
    -------
    int
        Valor lido de ERROR, depois de limpar o registrador.
    """
    await bus.write(dut, ARG, argument)
    await bus.write(dut, CMD, index | flags)
    await wait_status(dut, CMD_DONE, CMD_DONE)
    await bus.write(dut, STATUS, CMD_DONE)
    errors = await bus.read(dut, ERROR)
    await bus.write(dut, ERROR, errors)
    return errors


async def app_command(
    dut: SdNativeDut, index: int, argument: int, flags: int, rca: int = 0
) -> int:
    """Envie o CMD55 e depois o comando de aplicação.

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    index : int
        Índice do comando de aplicação.
    argument : int
        Argumento do comando de aplicação.
    flags : int
        Bits 10:6 do registrador CMD do comando de aplicação.
    rca : int
        Endereço relativo do cartão, no CMD55.

    Returns
    -------
    int
        Erros do conjunto.
    """
    errors = await command(dut, CMD55, rca << 16)
    return errors | await command(dut, index, argument, flags)


async def initialize(dut: SdNativeDut, card: NativeCard) -> None:
    """Execute a inicialização até o estado de transferência.

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    card : NativeCard
        Cartão ligado aos pinos.
    """
    await bus.write(dut, CONTROL, CLK_ENABLE)
    await bus.cycles(dut, 100 * 2 * (RESET_DIVIDER + 1))
    await bus.write(dut, CONTROL, 0)
    await wait_status(dut, DATA_BUSY | CMD_BUSY, 0)
    check(await command(dut, CMD0, 0, RSP_NONE << 6) == 0, "CMD0")
    check(await command(dut, CMD8, IF_COND) == 0, "CMD8")
    check(await bus.read(dut, RESP0) == IF_COND, "eco do CMD8")
    ready = 0
    for _ in range(10):
        errors = await app_command(
            dut, CMD41, HCS | OCR_VOLTAGE, RSP_SHORT_NO_CRC << 6
        )
        check(errors == 0, f"ACMD41 erros {errors:#x}")
        ocr = await bus.read(dut, RESP0)
        if ocr & OCR_READY:
            ready = ocr
            break
    check(ready & HCS != 0, "OCR sem CCS")
    check(await command(dut, CMD2, 0, RSP_LONG << 6) == 0, "CMD2")
    body = int.from_bytes(CID_BODY, "big")
    words = [await bus.read(dut, RESP0 + word) for word in range(CID_WORDS)]
    check(
        words == [(body >> (32 * word)) & WORD_MASK for word in range(4)],
        f"CID {words}",
    )
    check(await command(dut, CMD3, 0) == 0, "CMD3")
    check(await bus.read(dut, RESP0) >> 16 == RCA, "RCA")
    check(
        await command(dut, CMD7, RCA << 16, (RSP_SHORT << 6) | WAIT_BUSY) == 0,
        "CMD7",
    )
    errors = await app_command(dut, CMD6, 2, RSP_SHORT << 6, RCA)
    check(errors == 0, "ACMD6")
    await bus.write(dut, CONTROL, WIDE_BUS)
    await bus.write(dut, DIVIDER, FAST_DIVIDER)
    check(card.errors == [], f"erros do cartão {card.errors}")


async def read_block(dut: SdNativeDut, sector: int) -> tuple[int, bytes]:
    """Leia um setor com o CMD17 e traga o buffer, como o exemplo em C.

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    sector : int
        Número do setor.

    Returns
    -------
    tuple[int, bytes]
        Os erros e os 512 bytes do buffer.
    """
    await bus.write(dut, ARG, sector)
    await bus.write(dut, CMD, CMD17 | (RSP_SHORT << 6) | DATA_EN)
    await wait_status(dut, CMD_DONE | DATA_DONE, CMD_DONE | DATA_DONE)
    await bus.write(dut, STATUS, CMD_DONE | DATA_DONE)
    errors = await bus.read(dut, ERROR)
    await bus.write(dut, ERROR, errors)
    await bus.write(dut, PTR, 0)
    words = [await bus.read(dut, DATA) for _ in range(BLOCK_WORDS)]
    return errors, b"".join(word.to_bytes(4, "little") for word in words)


async def write_block(dut: SdNativeDut, sector: int, data: bytes) -> int:
    """Escreva um setor com o CMD24, como o exemplo em C.

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    sector : int
        Número do setor.
    data : bytes
        Os 512 bytes a gravar.

    Returns
    -------
    int
        Os erros lidos de ERROR, depois de limpos.
    """
    await bus.write(dut, PTR, 0)
    for index in range(BLOCK_WORDS):
        first = 4 * index
        last = first + 4
        word = int.from_bytes(data[first:last], "little")
        await bus.write(dut, DATA, word)
    await bus.write(dut, ARG, sector)
    flags = (RSP_SHORT << 6) | DATA_EN | DATA_WRITE
    await bus.write(dut, CMD, CMD24 | flags)
    await wait_status(dut, CMD_DONE | DATA_DONE, CMD_DONE | DATA_DONE)
    await bus.write(dut, STATUS, CMD_DONE | DATA_DONE)
    errors = await bus.read(dut, ERROR)
    await bus.write(dut, ERROR, errors)
    return errors


async def clock_levels(dut: SdNativeDut, cycles: int) -> list[int]:
    """Amostre o nível de SD_CLK a cada ciclo do clock do módulo.

    Parameters
    ----------
    dut : SdNativeDut
        Controlador exercitado pelo teste.
    cycles : int
        Quantidade de ciclos observados.

    Returns
    -------
    list[int]
        O nível de SD_CLK depois de cada borda do clock do módulo.
    """
    levels: list[int] = []
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        levels.append(int(dut.o_sd_clk.value))
    return levels


@cocotb.test()
async def test_reset_state_and_register_map(dut: SdNativeDut) -> None:
    """Os registradores assumem os valores definidos para o reset."""
    await setup(dut)
    check(await bus.read(dut, STATUS) & 0xFF == CMD_LINE)
    check(await bus.read(dut, ERROR) == 0)
    check(await bus.read(dut, CONTROL) == 0)
    check(await bus.read(dut, DIVIDER) == RESET_DIVIDER)
    check(await bus.read(dut, TIMEOUT) == DEFAULT_TIMEOUT)
    check(await bus.read(dut, PTR) == 0)
    check(await bus.read(dut, ARG) == 0)
    for word in (RESP0, RESP1, RESP2, RESP3):
        check(await bus.read(dut, word) == 0)
    check(int(dut.o_sd_clk.value) == 0, "SD_CLK em repouso em nível baixo")
    check(int(dut.o_sd_cmd_oe.value) == 0, "CMD solta")
    check(int(dut.o_sd_dat_oe.value) == 0, "DAT soltas")
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_register_readback(dut: SdNativeDut) -> None:
    """ARG, CONTROL, DIVIDER, TIMEOUT e PTR guardam o que se escreve."""
    await setup(dut)
    await bus.write(dut, ARG, PATTERN_ARG)
    check(await bus.read(dut, ARG) == PATTERN_ARG)
    await bus.write(dut, CONTROL, CONTROL_ALL)
    check(await bus.read(dut, CONTROL) == CONTROL_ALL)
    await bus.write(dut, CONTROL, 0)
    await bus.write(dut, DIVIDER, PATTERN_DIVIDER)
    check(await bus.read(dut, DIVIDER) == PATTERN_DIVIDER)
    await bus.write(dut, TIMEOUT, PATTERN_TIMEOUT)
    check(await bus.read(dut, TIMEOUT) == PATTERN_TIMEOUT)
    await bus.write(dut, PTR, PATTERN_PTR)
    check(await bus.read(dut, PTR) == PATTERN_PTR)
    await bus.write(dut, DATA, PATTERN_WORD)
    check(
        await bus.read(dut, PTR) == PATTERN_PTR + 1,
        "a escrita avança o ponteiro",
    )
    await bus.write(dut, PTR, PATTERN_PTR)
    check(await bus.read(dut, DATA) == PATTERN_WORD, "palavra guardada")
    check(
        await bus.read(dut, PTR) == PATTERN_PTR + 1,
        "a leitura avança o ponteiro",
    )
    await bus.write(dut, PTR, 0x7F)
    await bus.write(dut, DATA, 0x1)
    check(await bus.read(dut, PTR) == 0, "o ponteiro dá a volta")


@cocotb.test()
async def test_clock_period_and_stop(dut: SdNativeDut) -> None:
    """SD_CLK segue o divisor, roda sob pedido e para em nível baixo."""
    await setup(dut)
    for divider in (1, 3):
        await bus.write(dut, DIVIDER, divider)
        await bus.write(dut, CONTROL, CLK_ENABLE)
        levels = await clock_levels(dut, 12 * (divider + 1) + 8)
        stamps = [
            cycle
            for cycle in range(1, len(levels))
            if levels[cycle] == 1 and levels[cycle - 1] == 0
        ]
        gaps = {b - a for a, b in pairwise(stamps)}
        check(len(stamps) >= MIN_EDGES, "SD_CLK não oscilou")
        check(gaps == {2 * (divider + 1)}, f"períodos {gaps}")
        await bus.write(dut, CONTROL, 0)
        await bus.cycles(dut, 4 * (divider + 1))
        levels = await clock_levels(dut, 8 * (divider + 1))
        check(sum(levels) == 0, "SD_CLK parou em nível baixo")


@cocotb.test()
async def test_init_sequence_and_four_bit_sector_io(dut: SdNativeDut) -> None:
    """Inicialize o cartão e leia e grave um setor com quatro linhas."""
    card = await setup(dut)
    await initialize(dut, card)
    seen = [index for index, _ in card.commands]
    check(seen[:3] == [0, 8, 55], f"comandos {seen}")
    check(seen[-5:] == [2, 3, 7, 55, 106], f"fim da inicialização {seen}")
    errors, data = await read_block(dut, SECTOR)
    check(errors == 0, f"erros {errors:#x}")
    check(data == SECTOR_PATTERN, "conteúdo do setor lido")
    errors = await write_block(dut, SECTOR + 1, WRITTEN_PATTERN)
    check(errors == 0, f"erros {errors:#x}")
    check(card.sectors[SECTOR + 1] == WRITTEN_PATTERN, "cartão gravou")
    status = await bus.read(dut, STATUS)
    check(
        (status >> TOKEN_SHIFT) & TOKEN_MASK == TOKEN_ACCEPTED, "estado de CRC"
    )
    errors, data = await read_block(dut, SECTOR + 1)
    check(errors == 0 and data == WRITTEN_PATTERN, "leitura de volta")
    check(card.errors == [], f"erros do cartão {card.errors}")


@cocotb.test()
async def test_one_bit_sector_io(dut: SdNativeDut) -> None:
    """Com uma linha, o setor lido e o gravado chegam inteiros."""
    card = await setup(dut)
    await initialize(dut, card)
    card.state.wide = False
    await bus.write(dut, CONTROL, 0)
    errors, data = await read_block(dut, SECTOR)
    check(errors == 0, f"erros {errors:#x}")
    check(data == SECTOR_PATTERN, "conteúdo do setor lido com uma linha")
    errors = await write_block(dut, SECTOR + 2, WRITTEN_PATTERN)
    check(errors == 0, f"erros {errors:#x}")
    check(card.sectors[SECTOR + 2] == WRITTEN_PATTERN, "cartão gravou")
    check(int(dut.o_sd_dat_oe.value) == 0, "linhas soltas ao fim")
    check(card.errors == [], f"erros do cartão {card.errors}")


@cocotb.test()
async def test_sector_read_at_each_divider(dut: SdNativeDut) -> None:
    """A leitura de um setor funciona do divisor 0 ao 2."""
    card = await setup(dut)
    await initialize(dut, card)
    for divider in (0, 1, 2):
        await bus.write(dut, DIVIDER, divider)
        errors, data = await read_block(dut, SECTOR)
        check(errors == 0, f"divisor {divider}: erros {errors:#x}")
        check(data == SECTOR_PATTERN, f"divisor {divider}: conteúdo")
        errors = await write_block(dut, SECTOR + 3, WRITTEN_PATTERN)
        check(errors == 0, f"divisor {divider}: escrita {errors:#x}")
        check(card.sectors[SECTOR + 3] == WRITTEN_PATTERN)


@cocotb.test()
async def test_no_card_is_a_command_timeout(dut: SdNativeDut) -> None:
    """Sem cartão a resposta não chega e o comando acusa o prazo."""
    await setup(dut, attach=False)
    errors = await command(dut, CMD8, IF_COND)
    check(errors == E_CMD_TIMEOUT, f"erros {errors:#x}")
    errors = await command(dut, CMD0, 0, RSP_NONE << 6)
    check(errors == 0, "sem resposta esperada, sem erro")


@cocotb.test()
async def test_response_checks(dut: SdNativeDut) -> None:
    """CRC7, índice e formato da resposta são conferidos onde cabe."""
    card = await setup(dut)
    await initialize(dut, card)
    card.faults.bad_crc = True
    check(await command(dut, CMD13, RCA << 16) == E_CMD_CRC, "CRC7 R1")
    card.faults.wrong_index = True
    check(await command(dut, CMD13, RCA << 16) == E_CMD_INDEX, "índice")
    check(await command(dut, CMD13, RCA << 16) == 0, "sem falha")
    errors = await app_command(dut, CMD41, HCS, RSP_SHORT << 6)
    check(errors == E_CMD_CRC | E_CMD_INDEX, f"R3 como R1: {errors:#x}")
    errors = await app_command(dut, CMD41, HCS, RSP_SHORT_NO_CRC << 6)
    check(errors == 0, "R3 não confere CRC7 nem índice")
    card.state.state = 1
    card.faults.bad_crc = True
    errors = await command(dut, CMD2, 0, RSP_LONG << 6)
    check(errors == E_CMD_CRC, f"CRC7 do R2 {errors:#x}")


@cocotb.test()
async def test_busy_detection_on_dat0(dut: SdNativeDut) -> None:
    """DAT0 baixo vale CARD_BUSY e o R1b espera o fim do ocupado."""
    card = await setup(dut)
    await bus.write(dut, CONTROL, CLK_ENABLE)
    await bus.cycles(dut, 100 * 8)
    await bus.write(dut, CONTROL, 0)
    await command(dut, CMD0, 0, RSP_NONE << 6)
    await command(dut, CMD8, IF_COND)
    for _ in range(4):
        await app_command(dut, CMD41, HCS | OCR_VOLTAGE, RSP_SHORT_NO_CRC << 6)
    await command(dut, CMD2, 0, RSP_LONG << 6)
    await command(dut, CMD3, 0)
    await bus.write(dut, ARG, RCA << 16)
    await bus.write(dut, CMD, CMD7 | (RSP_SHORT << 6) | WAIT_BUSY)
    saw_busy = False
    for _ in range(POLL_LIMIT):
        status = await bus.read(dut, STATUS)
        saw_busy = saw_busy or status & CARD_BUSY != 0
        if status & CMD_DONE:
            break
        await bus.cycles(dut, 2)
    check(saw_busy, "CARD_BUSY nunca subiu")
    check(await bus.read(dut, STATUS) & CARD_BUSY == 0, "ocupado acabou")
    check(card.state.state == STATE_TRAN)
    await bus.write(dut, STATUS, CMD_DONE)
    card.faults.stuck_busy = True
    await bus.write(dut, TIMEOUT, SHORT_TIMEOUT)
    errors = await command(dut, CMD7, RCA << 16, (RSP_SHORT << 6) | WAIT_BUSY)
    check(errors == E_CMD_TIMEOUT, f"ocupado preso: {errors:#x}")


@cocotb.test()
async def test_data_errors(dut: SdNativeDut) -> None:
    """CRC16 errado, bloco ausente, estado de CRC e ocupado preso."""
    card = await setup(dut)
    await initialize(dut, card)
    card.faults.bad_data_crc = True
    errors, _ = await read_block(dut, SECTOR)
    check(errors == E_DATA_CRC, f"CRC16 errado: {errors:#x}")
    await bus.write(dut, TIMEOUT, SHORT_TIMEOUT)
    card.faults.no_data = True
    errors, _ = await read_block(dut, SECTOR)
    check(errors == E_DATA_TIMEOUT, f"bloco ausente: {errors:#x}")
    card.faults.token = 0b101
    errors = await write_block(dut, SECTOR + 4, WRITTEN_PATTERN)
    check(errors == E_WRITE_CRC, f"estado de CRC 101: {errors:#x}")
    card.faults.token = 0b110
    errors = await write_block(dut, SECTOR + 4, WRITTEN_PATTERN)
    check(errors == E_WRITE_ERROR, f"estado de CRC 110: {errors:#x}")
    card.faults.stuck_busy = False
    check(await write_block(dut, SECTOR + 4, WRITTEN_PATTERN) == 0)


@cocotb.test()
async def test_interrupts_dropped_and_abort(dut: SdNativeDut) -> None:
    """Cada causa de interrupção, o comando recusado e o aborto."""
    card = await setup(dut)
    await bus.write(dut, CONTROL, CMD_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 0)
    await bus.write(dut, ARG, IF_COND)
    await bus.write(dut, CMD, CMD8 | (RSP_SHORT << 6))
    await bus.write(dut, CMD, CMD8 | (RSP_SHORT << 6))
    status = await wait_status(dut, CMD_DONE, CMD_DONE)
    check(status & CMD_BUSY == 0)
    check(int(dut.o_irq.value) == 1, "fim de comando")
    await bus.write(dut, STATUS, CMD_DONE)
    check(int(dut.o_irq.value) == 0, "W1C do fim de comando")
    check(await bus.read(dut, ERROR) & E_DROPPED != 0, "comando recusado")
    await bus.write(dut, CONTROL, ERROR_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 1, "erro")
    await bus.write(dut, ERROR, E_ALL)
    check(int(dut.o_irq.value) == 0, "erro limpo")
    await bus.write(dut, CONTROL, DATA_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 0)
    card.faults.silent = True
    await bus.write(dut, ARG, IF_COND)
    await bus.write(dut, CMD, CMD8 | (RSP_SHORT << 6))
    await bus.cycles(dut, 40)
    check(await bus.read(dut, STATUS) & CMD_BUSY != 0, "comando em curso")
    await bus.write(dut, CONTROL, ABORT)
    await bus.cycles(dut, 4)
    status = await bus.read(dut, STATUS)
    check(status & (CMD_BUSY | CMD_DONE) == 0, f"aborto {status:#x}")
    check(int(dut.o_sd_cmd_oe.value) == 0, "CMD solta")
    check(await bus.read(dut, CONTROL) == 0, "ABORT não é guardado")

"""SD no modo SPI: registradores, SCLK, filas, interrupções e cartão.

A configuração do teste usa ``CLOCK_HZ=3200000``, que dá o divisor de
reset 3 (SCLK de 400 kHz com o clock de 3,2 MHz). O software do teste
faz a sequência de inicialização e as leituras e escritas de setor que o
exemplo em C da documentação faz, contra o modelo de cartão.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus, polling
from tests.python.utils.check import check
from tests.python.utils.dut import SdSpiDut
from tests.python.utils.sd_card import (
    CMD_ACMD41,
    CMD_APP,
    CMD_GO_IDLE,
    CMD_OCR,
    CMD_READ,
    CMD_SEND_IF,
    CMD_WRITE,
    SECTOR_BYTES,
    SpiCard,
    command_frame,
    crc16,
)
from tests.python.utils.spi_regs import (
    BUSY,
    CS_ASSERT,
    DONE,
    DONE_IRQ_ENABLE,
    ERROR_IRQ_ENABLE,
    RX_FULL,
    RX_IRQ_ENABLE,
    RX_OVERRUN,
    RX_VALID,
    TX_DROPPED,
    TX_EMPTY,
    TX_EMPTY_IRQ_ENABLE,
    TX_READY,
)

TX_DATA, RX_DATA, STATUS, CONTROL, DIVIDER = range(5)

RESET_DIVIDER = 3
FIFO_DEPTH = 4
POLL_LIMIT = 4000
IDLE_BYTES = 10
IDLE_FILL = 0xFF
HCS = 0x40000000
IF_COND = 0x1AA
SECTOR = 7
SECTOR_PATTERN = bytes((index * 7 + 3) & 0xFF for index in range(SECTOR_BYTES))
WRITTEN_PATTERN = bytes((index ^ 0x5A) & 0xFF for index in range(SECTOR_BYTES))
TOKEN_START = 0xFE
DATA_ACCEPTED = 0x05
DATA_RESPONSE_MASK = 0x1F
CONTROL_ALL = 0x1F
DIVIDER_PATTERN = 0xBEEF
EDGES = 3
EDGE_LIMIT = 400


async def setup(dut: SdSpiDut) -> SpiCard:
    """Reinicie o periférico e ligue o cartão.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.

    Returns
    -------
    SpiCard
        Cartão ligado aos pinos, com o setor de leitura gravado.
    """
    dut.i_sd_miso.value = 1
    await bus.reset(dut)
    card = SpiCard(dut, {SECTOR: SECTOR_PATTERN})
    card.start()
    return card


async def wait_status(dut: SdSpiDut, mask: int, value: int) -> int:
    """Leia STATUS até os bits de ``mask`` valerem ``value``.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.
    mask : int
        Bits observados.
    value : int
        Valor esperado dos bits observados.

    Returns
    -------
    int
        Último valor de STATUS lido.

    Raises
    ------
    AssertionError
        Se a condição não ocorrer dentro do limite.
    """
    return await polling.wait_status(dut, STATUS, mask, value, POLL_LIMIT)


async def xfer(dut: SdSpiDut, value: int) -> int:
    """Troque um byte, como a função spi_xfer do exemplo em C.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.
    value : int
        Byte transmitido.

    Returns
    -------
    int
        Byte recebido no mesmo intervalo.
    """
    await bus.write(dut, TX_DATA, value)
    await wait_status(dut, RX_VALID, RX_VALID)
    return await bus.read(dut, RX_DATA) & 0xFF


async def send_command(
    dut: SdSpiDut, frame: bytes, extra: int = 0
) -> list[int]:
    """Envie um comando e leia a resposta R1 mais ``extra`` bytes.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.
    frame : bytes
        Quadro de seis bytes do comando.
    extra : int
        Bytes que seguem o R1 (quatro no R7 e no R3).

    Returns
    -------
    list[int]
        R1 seguido dos bytes extras.

    Raises
    ------
    AssertionError
        Se o cartão não responder em oito bytes.
    """
    for value in frame:
        await xfer(dut, value)
    for _ in range(8):
        r1 = await xfer(dut, IDLE_FILL)
        if r1 != IDLE_FILL:
            return [r1] + [await xfer(dut, IDLE_FILL) for _ in range(extra)]
    message = "sem resposta do cartão"
    raise AssertionError(message)


async def initialize(dut: SdSpiDut) -> None:
    """Execute a sequência de inicialização do cartão no modo SPI.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.
    """
    for _ in range(IDLE_BYTES):
        await xfer(dut, IDLE_FILL)
    await bus.write(dut, CONTROL, CS_ASSERT)
    r1 = await send_command(dut, command_frame(CMD_GO_IDLE, 0))
    check(r1 == [0x01], f"CMD0 devolveu {r1}")
    r7 = await send_command(dut, command_frame(CMD_SEND_IF, IF_COND), 4)
    check(r7 == [0x01, 0, 0, 1, 0xAA], f"CMD8 devolveu {r7}")
    for _ in range(10):
        await send_command(dut, command_frame(CMD_APP, 0))
        r1 = await send_command(dut, command_frame(CMD_ACMD41, HCS))
        if r1 == [0x00]:
            break
    check(r1 == [0x00], f"ACMD41 devolveu {r1}")
    ocr = await send_command(dut, command_frame(CMD_OCR, 0), 4)
    check(ocr == [0x00, 0xC0, 0xFF, 0x80, 0x00], f"CMD58 devolveu {ocr}")


async def read_sector(dut: SdSpiDut, sector: int) -> bytes:
    """Leia um setor com o CMD17, como o exemplo em C.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.
    sector : int
        Número do setor.

    Returns
    -------
    bytes
        Os 512 bytes do setor, depois de conferir o token e o CRC.
    """
    r1 = await send_command(dut, command_frame(CMD_READ, sector))
    check(r1 == [0x00], f"CMD17 devolveu {r1}")
    token = IDLE_FILL
    for _ in range(100):
        token = await xfer(dut, IDLE_FILL)
        if token != IDLE_FILL:
            break
    check(token == TOKEN_START, f"token {token:#x}")
    data = bytes([await xfer(dut, IDLE_FILL) for _ in range(SECTOR_BYTES)])
    crc = (await xfer(dut, IDLE_FILL) << 8) | await xfer(dut, IDLE_FILL)
    check(crc == crc16(data), "CRC16 do setor lido")
    return data


async def write_sector(dut: SdSpiDut, sector: int, data: bytes) -> None:
    """Escreva um setor com o CMD24, como o exemplo em C.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.
    sector : int
        Número do setor.
    data : bytes
        Os 512 bytes a gravar.
    """
    r1 = await send_command(dut, command_frame(CMD_WRITE, sector))
    check(r1 == [0x00], f"CMD24 devolveu {r1}")
    await xfer(dut, IDLE_FILL)
    await xfer(dut, TOKEN_START)
    for value in data:
        await xfer(dut, value)
    crc = crc16(data)
    await xfer(dut, crc >> 8)
    await xfer(dut, crc & 0xFF)
    response = await xfer(dut, IDLE_FILL)
    check(
        response & DATA_RESPONSE_MASK == DATA_ACCEPTED,
        f"resposta de dados {response:#x}",
    )
    for _ in range(100):
        if await xfer(dut, IDLE_FILL) == IDLE_FILL:
            return
    message = "o cartão ficou ocupado"
    raise AssertionError(message)


async def loopback(dut: SdSpiDut) -> None:
    """Ligue MISO a MOSI, para a recepção devolver o que se transmite.

    Parameters
    ----------
    dut : SdSpiDut
        Controlador exercitado pelo teste.
    """
    while True:
        await dut.o_sd_mosi.value_change
        dut.i_sd_miso.value = dut.o_sd_mosi.value


@cocotb.test()
async def test_reset_state_and_register_map(dut: SdSpiDut) -> None:
    """Os registradores assumem os valores definidos para o reset."""
    await setup(dut)
    check(await bus.read(dut, STATUS) == TX_READY | TX_EMPTY)
    check(await bus.read(dut, CONTROL) == 0)
    check(await bus.read(dut, DIVIDER) == RESET_DIVIDER)
    check(await bus.read(dut, RX_DATA) == 0)
    check(int(dut.o_sd_cs_n.value) == 1, "cartão não selecionado")
    check(int(dut.o_sd_sclk.value) == 0, "SCLK em repouso em nível baixo")
    check(int(dut.o_sd_mosi.value) == 1, "MOSI em repouso em nível alto")
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_control_and_divider_registers(dut: SdSpiDut) -> None:
    """CONTROL e DIVIDER guardam o que se escreve e CS segue o bit 0."""
    await setup(dut)
    await bus.write(dut, CONTROL, CONTROL_ALL)
    check(await bus.read(dut, CONTROL) == CONTROL_ALL)
    check(int(dut.o_sd_cs_n.value) == 0, "CS ativo em nível baixo")
    await bus.write(dut, CONTROL, CONTROL_ALL ^ CS_ASSERT)
    check(int(dut.o_sd_cs_n.value) == 1)
    await bus.write(dut, DIVIDER, DIVIDER_PATTERN)
    check(await bus.read(dut, DIVIDER) == DIVIDER_PATTERN)


@cocotb.test()
async def test_sclk_period_follows_divider(dut: SdSpiDut) -> None:
    """O período de SCLK vale 2 * (divisor + 1) ciclos do clock."""
    await setup(dut)
    await bus.write(dut, CONTROL, CS_ASSERT)
    for divider in (1, 5):
        await bus.write(dut, DIVIDER, divider)
        await bus.write(dut, TX_DATA, 0xA5)
        stamps: list[int] = []
        cycle = 0
        previous = 0
        while len(stamps) < EDGES and cycle < EDGE_LIMIT:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            level = int(dut.o_sd_sclk.value)
            if level == 1 and previous == 0:
                stamps.append(cycle)
            previous, cycle = level, cycle + 1
        check(len(stamps) == EDGES, "SCLK não oscilou")
        gaps = {stamps[1] - stamps[0], stamps[2] - stamps[1]}
        check(gaps == {2 * (divider + 1)}, f"períodos {gaps}")
        await wait_status(dut, BUSY, 0)
        await bus.read(dut, RX_DATA)


@cocotb.test()
async def test_card_init_sequence_and_sector_read(dut: SdSpiDut) -> None:
    """Inicialize o cartão e leia um setor."""
    card = await setup(dut)
    await initialize(dut)
    check(card.commands[:3] == [0, 8, 55], f"comandos {card.commands}")
    data = await read_sector(dut, SECTOR)
    check(data == SECTOR_PATTERN, "conteúdo do setor lido")
    await bus.write(dut, CONTROL, 0)
    check(card.errors == [], f"erros do cartão {card.errors}")


@cocotb.test()
async def test_sector_write_then_read_back(dut: SdSpiDut) -> None:
    """Um setor escrito com o CMD24 volta igual pelo CMD17."""
    card = await setup(dut)
    await initialize(dut)
    await write_sector(dut, SECTOR + 1, WRITTEN_PATTERN)
    check(card.sectors[SECTOR + 1] == WRITTEN_PATTERN, "cartão gravou")
    check(await read_sector(dut, SECTOR + 1) == WRITTEN_PATTERN)
    check(card.errors == [], f"erros do cartão {card.errors}")


@cocotb.test()
async def test_cmd0_without_start_clocks_is_flagged(dut: SdSpiDut) -> None:
    """O modelo acusa o CMD0 sem os 74 clocks com CS alto."""
    card = await setup(dut)
    await bus.write(dut, CONTROL, CS_ASSERT)
    await send_command(dut, command_frame(CMD_GO_IDLE, 0))
    check(len(card.errors) == 1, f"erros {card.errors}")


@cocotb.test()
async def test_fifos_levels_overrun_and_dropped(dut: SdSpiDut) -> None:
    """As filas contam bytes, descartam o excesso e marcam os erros."""
    dut.i_sd_miso.value = 1
    await bus.reset(dut)
    cocotb.start_soon(loopback(dut))
    for index in range(FIFO_DEPTH + 2):
        await bus.write(dut, TX_DATA, 0x10 + index)
    status = await bus.read(dut, STATUS)
    check(status & TX_DROPPED != 0, "escrita excedente marcada")
    await bus.write(dut, STATUS, TX_DROPPED)
    check(await bus.read(dut, STATUS) & TX_DROPPED == 0, "W1C limpa")
    status = await wait_status(dut, BUSY, 0)
    check(status & RX_FULL != 0, "fila de recepção cheia")
    check(status & RX_OVERRUN != 0, "recepção excedente marcada")
    check((status >> 8) & 0xFF == FIFO_DEPTH, "nível de recepção")
    await bus.write(dut, STATUS, RX_OVERRUN)
    check(await bus.read(dut, STATUS) & RX_OVERRUN == 0, "W1C limpa")
    received = [await bus.read(dut, RX_DATA) for _ in range(FIFO_DEPTH)]
    check(received == [0x10 + i for i in range(FIFO_DEPTH)], f"{received}")
    check(await bus.read(dut, STATUS) & RX_VALID == 0, "fila esvaziada")


@cocotb.test()
async def test_interrupt_causes(dut: SdSpiDut) -> None:
    """Cada causa de interrupção tem a sua habilitação."""
    await setup(dut)
    await bus.write(dut, CONTROL, TX_EMPTY_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 1, "fila de transmissão vazia")
    await bus.write(dut, CONTROL, DONE_IRQ_ENABLE | RX_IRQ_ENABLE)
    check(int(dut.o_irq.value) == 0)
    await bus.write(dut, TX_DATA, 0x42)
    await wait_status(dut, BUSY, 0)
    await bus.cycles(dut, 2)
    check(int(dut.o_irq.value) == 1, "fim de transferência ou byte")
    await bus.write(dut, STATUS, DONE)
    check(int(dut.o_irq.value) == 1, "byte recebido ainda pendente")
    await bus.read(dut, RX_DATA)
    check(int(dut.o_irq.value) == 0, "tudo atendido")
    await bus.write(dut, CONTROL, ERROR_IRQ_ENABLE)
    for _ in range(FIFO_DEPTH + 1):
        await bus.write(dut, TX_DATA, 0x01)
    await wait_status(dut, BUSY, 0)
    check(int(dut.o_irq.value) == 1, "erro")
    await bus.write(dut, STATUS, RX_OVERRUN | TX_DROPPED)
    check(int(dut.o_irq.value) == 0, "erro limpo")

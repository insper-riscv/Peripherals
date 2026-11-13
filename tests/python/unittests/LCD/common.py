"""Acessos e valores comuns aos testes do controlador do LCD."""

from tests.python.unittests.LCD.hd44780 import Hd44780
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdDut

COMMAND, DATA, STATUS, CONTROL, DELAY, DELAY_LONG = range(6)

BUSY = 1 << 0
FIFO_FULL = 1 << 1
FIFO_EMPTY = 1 << 2
INIT_BUSY = 1 << 3
DROPPED = 1 << 4
TIMEOUT = 1 << 5
LEVEL_SHIFT = 8
LEVEL_MASK = 0xFF

IRQ_ENABLE = 1 << 0
POLL_ENABLE = 1 << 1
LCD_ON = 1 << 2
BACKLIGHT = 1 << 3

CLOCK_NS = 100
FUNCTION_SET = 0x38
DISPLAY_ON = 0x0C
CLEAR = 0x01
ENTRY_MODE = 0x06
SET_LINE_TWO = 0xC0
SET_LINE_ONE = 0x80
IDLE_LIMIT = 60_000
POWER_UP_CYCLES = 151_000


async def start(dut: LcdDut, *, power_up_ns: int = 0) -> Hd44780:
    """Aplica o reset e liga o modelo do chip.

    Parameters
    ----------
    dut : LcdDut
        Controlador sob teste.
    power_up_ns : int
        Energização que o modelo exige antes de aceitar escritas.

    Returns
    -------
    Hd44780
        O chip ligado aos pinos.
    """
    await bus.reset(dut, hold=4, period_ns=CLOCK_NS)
    return Hd44780(dut, power_up_ns=power_up_ns)


async def put(dut: LcdDut, command: int | None, value: int) -> None:
    """Escreve um byte em COMMAND ou em DATA, esperando espaço na fila.

    Parameters
    ----------
    dut : LcdDut
        Controlador sob teste.
    command : int | None
        Qualquer valor não nulo escolhe COMMAND, ``None`` escolhe DATA.
    value : int
        Byte escrito.
    """
    while await bus.read(dut, STATUS) & FIFO_FULL:
        pass
    await bus.write(dut, DATA if command is None else COMMAND, value)


async def text(dut: LcdDut, message: str) -> None:
    """Escreve uma cadeia de caracteres em DATA.

    Parameters
    ----------
    dut : LcdDut
        Controlador sob teste.
    message : str
        Texto, um byte por caractere.
    """
    for char in message:
        await put(dut, None, ord(char))


async def wait_idle(dut: LcdDut, limit: int = IDLE_LIMIT) -> int:
    """Espera o bit BUSY baixar, lendo STATUS.

    Parameters
    ----------
    dut : LcdDut
        Controlador sob teste.
    limit : int
        Quantidade máxima de leituras.

    Returns
    -------
    int
        O último valor de STATUS.
    """
    for _ in range(limit):
        status = await bus.read(dut, STATUS)
        if not status & BUSY:
            return status
    check(False, "o controlador não ficou ocioso")
    return 0


async def manual_init(dut: LcdDut) -> None:
    """Envia a inicialização por software depois da energização.

    Parameters
    ----------
    dut : LcdDut
        Controlador sob teste.
    """
    for command in (FUNCTION_SET, DISPLAY_ON, CLEAR, ENTRY_MODE):
        await put(dut, COMMAND, command)


def flag(value: int, mask: int) -> bool:
    """Informa se um bit de um registrador está aceso.

    Parameters
    ----------
    value : int
        Valor lido do registrador.
    mask : int
        Máscara do bit.

    Returns
    -------
    bool
        Verdadeiro quando algum bit da máscara está aceso.
    """
    return bool(value & mask)

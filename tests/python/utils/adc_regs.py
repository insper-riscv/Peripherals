"""Registradores e esperas comuns aos ADCs de 8 canais."""

from tests.python.utils import bus
from tests.python.utils.dut import BusDut, IrqDut

CH_BASE = 0
CONTROL = 8
STATUS = 9
DIVIDER = 10
ENABLE = 1 << 0
IRQ_ENABLE = 1 << 1
START = 1 << 2
BUSY = 1 << 0
SWEEP_DONE = 1 << 1
VALID = 1 << 2
FRAMES_PER_SWEEP = 9
VOLTS = (0x000, 0x7FF, 0xFFF, 0x123, 0x456, 0x789, 0xABC, 0xDEF)
LIMIT = 8000


async def wait_idle(dut: BusDut) -> None:
    """Espere BUSY cair.

    Parameters
    ----------
    dut : BusDut
        Controlador exercitado pelo teste.

    Raises
    ------
    AssertionError
        Se BUSY não cair dentro do limite.
    """
    for _ in range(LIMIT):
        if (await bus.read(dut, STATUS)) & BUSY == 0:
            return
    message = "a varredura não terminou"
    raise AssertionError(message)


async def wait_channel(dut: BusDut, channel: int, value: int) -> int:
    """Leia o canal até ele valer ``value``.

    Parameters
    ----------
    dut : BusDut
        Controlador exercitado pelo teste.
    channel : int
        Canal de 0 a 7.
    value : int
        Resultado esperado.

    Returns
    -------
    int
        Último resultado lido.
    """
    got = 0
    for _ in range(LIMIT):
        got = await bus.read(dut, CH_BASE + channel)
        if got == value:
            break
    return got


async def wait_irq(dut: IrqDut) -> bool:
    """Espere a interrupção do controlador subir.

    Parameters
    ----------
    dut : IrqDut
        Controlador exercitado pelo teste, com ``o_irq``.

    Returns
    -------
    bool
        Verdadeiro se a interrupção subiu dentro do limite.
    """
    for _ in range(LIMIT):
        if int(dut.o_irq.value):
            return True
        await bus.cycles(dut, 1)
    return False

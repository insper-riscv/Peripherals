"""Leitura repetida de um registrador até uma condição valer."""

from tests.python.utils import bus
from tests.python.utils.dut import BusDut

POLL_LIMIT = 4000


async def wait_status(
    dut: BusDut,
    address: int,
    mask: int,
    value: int,
    limit: int = POLL_LIMIT,
) -> int:
    """Leia ``address`` até os bits de ``mask`` valerem ``value``.

    Parameters
    ----------
    dut : BusDut
        Periférico exercitado pelo teste.
    address : int
        Endereço do registrador de estado.
    mask : int
        Bits observados.
    value : int
        Valor esperado dos bits observados.
    limit : int
        Quantidade máxima de leituras.

    Returns
    -------
    int
        Último valor lido.

    Raises
    ------
    AssertionError
        Se a condição não ocorrer dentro do limite.
    """
    for _ in range(limit):
        status = await bus.read(dut, address)
        if status & mask == value:
            return status
    message = f"estado não chegou a {value:#x} sob a máscara {mask:#x}"
    raise AssertionError(message)

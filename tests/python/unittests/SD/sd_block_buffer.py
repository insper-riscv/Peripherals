"""Buffer de bloco do SD: escrita, leitura síncrona e valor antigo."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.check import check
from tests.python.utils.dut import SdBufferDut

WORDS = 128
PATTERN = 0x9E3779B1
MASK = 0xFFFFFFFF
OLD = 0x11111111
NEW = 0x22222222
OTHER = 0xDEADBEEF


async def access(
    dut: SdBufferDut, write: int, address: int, data: int, read: int
) -> int:
    """Faça um ciclo de escrita e leitura e devolva a palavra lida.

    Parameters
    ----------
    dut : SdBufferDut
        Buffer exercitado pelo teste.
    write : int
        Habilitação de escrita.
    address : int
        Endereço de escrita.
    data : int
        Palavra escrita.
    read : int
        Endereço de leitura.

    Returns
    -------
    int
        Palavra que a porta de leitura apresenta depois da borda.
    """
    drive = {
        "i_write_enable": write,
        "i_write_address": address,
        "i_write_data": data,
        "i_read_address": read,
    }
    for name, value in drive.items():
        getattr(dut, name).value = value
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return int(dut.o_read_data.value)


async def start(dut: SdBufferDut) -> None:
    """Zere as entradas e ligue o clock, com a primeira borda adiante.

    Parameters
    ----------
    dut : SdBufferDut
        Buffer exercitado pelo teste.
    """
    dut.i_write_enable.value = 0
    dut.i_write_address.value = 0
    dut.i_write_data.value = 0
    dut.i_read_address.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start(start_high=False))
    await Timer(1, unit="ns")


@cocotb.test()
async def test_write_then_read_every_word(dut: SdBufferDut) -> None:
    """Cada palavra gravada volta pela leitura uma borda depois."""
    await start(dut)
    for word in range(WORDS):
        await access(dut, 1, word, (PATTERN * (word + 1)) & MASK, 0)
    for word in range(WORDS):
        got = await access(dut, 0, 0, 0, word)
        expected = (PATTERN * (word + 1)) & MASK
        check(got == expected, f"palavra {word}: {got:#x}")


@cocotb.test()
async def test_read_during_write_returns_old_value(dut: SdBufferDut) -> None:
    """Ler e escrever o mesmo endereço no ciclo devolve o antigo."""
    await start(dut)
    await access(dut, 1, 5, OLD, 0)
    got = await access(dut, 1, 5, NEW, 5)
    check(got == OLD, f"valor antigo esperado, veio {got:#x}")
    got = await access(dut, 0, 0, 0, 5)
    check(got == NEW, f"valor novo esperado, veio {got:#x}")
    got = await access(dut, 0, 5, OTHER, 5)
    check(got == NEW, "sem habilitação nada é gravado")

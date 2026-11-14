"""CRC7 e CRC16 seriais do cartão SD contra a divisão polinomial.

O módulo vale para as duas entidades, e a largura de ``o_crc`` escolhe o
modelo. O VHDL é um registrador de deslocamento; o modelo do teste
divide um inteiro. Os dois precisam concordar com os valores conhecidos
da especificação (CMD0, CMD8, CMD17, CMD55 e ACMD41 no CRC7; 512 bytes
0xFF, 512 bytes zero e "123456789" no CRC16) e com mensagens aleatórias,
e o CRC de uma mensagem seguida do próprio CRC é zero.
"""

from collections.abc import Callable, Sequence

import cocotb

from tests.python.utils import bus, rng
from tests.python.utils.check import check
from tests.python.utils.dut import SdCrcDut
from tests.python.utils.sd_native_card import (
    KNOWN_CRC7,
    KNOWN_CRC16,
    bytes_to_bits,
    crc7,
    crc16,
    to_bits,
)

CRC7_WIDTH = 7
CRC16_WIDTH = 16
RANDOM_MESSAGES = {CRC7_WIDTH: 40, CRC16_WIDTH: 12}
MAX_BITS = {CRC7_WIDTH: 200, CRC16_WIDTH: 600}
RNG_SEED = 0x5D7
HOLD_MESSAGE = bytes((0x51, 0, 0, 0, 0))
ModelSpec = tuple[
    int, Callable[[Sequence[int]], int], Sequence[tuple[bytes, int]]
]


def model_of(dut: SdCrcDut) -> ModelSpec:
    """Escolha o modelo pela largura de ``o_crc``.

    Parameters
    ----------
    dut : SdCrcDut
        Registrador exercitado pelo teste.

    Returns
    -------
    ModelSpec
        Largura, função de referência e vetores conhecidos.
    """
    width = len(dut.o_crc)
    if width == CRC7_WIDTH:
        return width, crc7, KNOWN_CRC7
    return width, crc16, KNOWN_CRC16


async def setup(dut: SdCrcDut) -> None:
    """Reinicie o registrador de CRC e solte as entradas.

    Parameters
    ----------
    dut : SdCrcDut
        Registrador exercitado pelo teste.
    """
    dut.i_clear.value = 0
    dut.i_enable.value = 0
    dut.i_bit.value = 0
    await bus.hold_reset(dut, hold=2)


async def feed(dut: SdCrcDut, bits: Sequence[int]) -> int:
    """Alimente bits e devolva o CRC resultante.

    Parameters
    ----------
    dut : SdCrcDut
        Registrador exercitado pelo teste.
    bits : Sequence[int]
        Bits da mensagem, o mais significativo primeiro.

    Returns
    -------
    int
        Valor de ``o_crc`` depois do último bit.
    """
    dut.i_clear.value = 1
    await bus.cycles(dut, 1)
    dut.i_clear.value = 0
    dut.i_enable.value = 1
    for bit in bits:
        dut.i_bit.value = bit
        await bus.cycles(dut, 1)
    dut.i_enable.value = 0
    return int(dut.o_crc.value)


@cocotb.test()
async def test_known_vectors(dut: SdCrcDut) -> None:
    """Os CRC conhecidos da especificação saem corretos."""
    await setup(dut)
    _, model, vectors = model_of(dut)
    for message, expected in vectors:
        check(model(bytes_to_bits(message)) == expected, "modelo do teste")
        got = await feed(dut, bytes_to_bits(message))
        check(got == expected, f"CRC {got:#x}, esperado {expected:#x}")


@cocotb.test()
async def test_random_messages_and_residue(dut: SdCrcDut) -> None:
    """Mensagens aleatórias batem e a mensagem com CRC dá resto zero."""
    await setup(dut)
    width, model, _ = model_of(dut)
    source = rng.seeded(RNG_SEED)
    for _ in range(RANDOM_MESSAGES[width]):
        length = source.randrange(1, MAX_BITS[width])
        bits = [source.randrange(2) for _ in range(length)]
        expected = model(bits)
        got = await feed(dut, bits)
        check(got == expected, f"CRC {got:#x}, esperado {expected:#x}")
        residue = await feed(dut, [*bits, *to_bits(expected, width)])
        check(residue == 0, f"resto {residue:#x}")


@cocotb.test()
async def test_hold_clear_and_reset(dut: SdCrcDut) -> None:
    """Sem habilitação o valor se mantém; limpar e resetar zeram."""
    await setup(dut)
    value = await feed(dut, bytes_to_bits(HOLD_MESSAGE))
    check(value != 0)
    await bus.cycles(dut, 3)
    check(int(dut.o_crc.value) == value, "o valor se manteve")
    dut.i_clear.value = 1
    dut.i_enable.value = 1
    dut.i_bit.value = 1
    await bus.cycles(dut, 1)
    check(int(dut.o_crc.value) == 0, "limpar vence a habilitação")
    dut.i_clear.value = 0
    await bus.cycles(dut, 2)
    check(int(dut.o_crc.value) != 0)
    dut.i_enable.value = 0
    dut.i_rst.value = 1
    await bus.cycles(dut, 1)
    check(int(dut.o_crc.value) == 0, "o reset zera")

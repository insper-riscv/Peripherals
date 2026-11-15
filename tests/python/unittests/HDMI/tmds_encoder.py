"""Codificador TMDS de um canal contra o modelo de referência do DVI.

O teste confere os quatro símbolos de controle, o reset, o símbolo de
cada um dos 256 bytes com a disparidade acumulada, o caminho inverso
(o byte decodificado é o original) e a disparidade acumulada limitada,
com apagamentos no meio de um fluxo aleatório.
"""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import TmdsEncoderDut
from tests.python.utils.rng import seeded
from tests.python.utils.tmds_reference import (
    CONTROL_TOKENS,
    TOKEN_BITS,
    EncoderModel,
    decode,
    ones,
)

SEED = 345
STREAM_LENGTH = 4000
BLANK_ONE_IN = 37
DISPARITY_LIMIT = 10


async def setup(dut: TmdsEncoderDut) -> None:
    """Reinicie o codificador com a entrada de apagamento parada.

    Parameters
    ----------
    dut : TmdsEncoderDut
        Codificador exercitado pelo teste.
    """
    bus.set_inputs(dut, i_de=0, i_c0=0, i_c1=0, i_d=0)
    await bus.hold_reset(dut)


async def step(
    dut: TmdsEncoderDut, de: int, byte: int, c1: int = 0, c0: int = 0
) -> int:
    """Aplique uma entrada e leia o símbolo registrado dela.

    Parameters
    ----------
    dut : TmdsEncoderDut
        Codificador exercitado pelo teste.
    de : int
        Habilitação de dados.
    byte : int
        Byte de pixel.
    c1 : int
        Bit de controle C1.
    c0 : int
        Bit de controle C0.

    Returns
    -------
    int
        O símbolo que a entrada produziu, uma borda depois.
    """
    bus.set_inputs(dut, i_de=de, i_d=byte, i_c1=c1, i_c0=c0)
    await bus.cycles(dut, 1)
    return int(dut.o_q.value)


@cocotb.test()
async def test_reset_token(dut: TmdsEncoderDut) -> None:
    """O reset deixa o símbolo de controle 00 na saída."""
    await setup(dut)
    check(int(dut.o_q.value) == CONTROL_TOKENS[0], "símbolo do reset")


@cocotb.test()
async def test_control_tokens(dut: TmdsEncoderDut) -> None:
    """Cada par C1 C0 do apagamento tem o seu símbolo de controle."""
    await setup(dut)
    for pair, token in CONTROL_TOKENS.items():
        got = await step(dut, 0, 0xFF, pair >> 1, pair & 1)
        check(got == token, f"par {pair:02b}: {got:010b}")


@cocotb.test()
async def test_every_byte_matches_the_reference(dut: TmdsEncoderDut) -> None:
    """Os 256 bytes dão o símbolo do modelo e voltam ao byte."""
    await setup(dut)
    model = EncoderModel()
    for byte in range(256):
        got = await step(dut, 1, byte)
        check(got == model.data(byte), f"byte {byte:#04x}: {got:010b}")
        check(decode(got) == byte, f"byte {byte:#04x} não decodifica")


@cocotb.test()
async def test_random_stream_with_blanking(dut: TmdsEncoderDut) -> None:
    """Um fluxo aleatório com apagamentos segue o modelo."""
    await setup(dut)
    rng = seeded(SEED)
    model = EncoderModel()
    balance = 0
    for _ in range(STREAM_LENGTH):
        if rng.randrange(BLANK_ONE_IN) == 0:
            pair = rng.randrange(4)
            got = await step(dut, 0, rng.randrange(256), pair >> 1, pair & 1)
            check(got == model.control(pair >> 1, pair & 1), "controle")
            balance = 0
            continue
        byte = rng.randrange(256)
        got = await step(dut, 1, byte)
        check(got == model.data(byte), f"byte {byte:#04x}: {got:010b}")
        balance += 2 * ones(got) - TOKEN_BITS
        check(abs(balance) <= DISPARITY_LIMIT, f"disparidade {balance}")

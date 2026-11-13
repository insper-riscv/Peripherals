"""Bancada do sequenciador: escritor falso e leituras."""

from dataclasses import dataclass, field
from typing import Protocol

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils.check import check

CLOCK_NS = 10
WRITE_CYCLES = 6
TABLE = [(0x98, 0x03), (0x01, 0x00), (0x15, 0x20), (0xAF, 0x16)]
SATURATION = 255


class SeqDut(Protocol):
    """Sinais do sequenciador de inicialização."""

    i_clk: LogicObject
    i_rst: LogicObject
    i_start: LogicObject
    o_wr_start: LogicObject
    o_wr_reg: LogicArrayObject
    o_wr_value: LogicArrayObject
    i_wr_done: LogicObject
    i_wr_nack: LogicObject
    o_busy: LogicObject
    o_done: LogicObject
    o_nack_seen: LogicObject
    o_sent: LogicArrayObject
    o_nacks: LogicArrayObject


@dataclass
class FakeWriter:
    """Escritor I2C falso que responde a cada pedido.

    Attributes
    ----------
    dut : SeqDut
        Sequenciador ao qual o escritor se liga.
    nack_on : set[int]
        Pedidos (por posição, a partir de zero) com NACK.
    requests : list[tuple[int, int]]
        Pares registrador-valor pedidos, na ordem.
    """

    dut: SeqDut
    nack_on: set[int] = field(default_factory=set[int])
    requests: list[tuple[int, int]] = field(
        default_factory=list[tuple[int, int]]
    )

    async def run(self) -> None:
        """Atende os pedidos até o fim da simulação."""
        dut = self.dut
        dut.i_wr_done.value = 0
        dut.i_wr_nack.value = 0
        while True:
            await RisingEdge(dut.i_clk)
            if int(dut.o_wr_start.value):
                index = len(self.requests)
                self.requests.append(
                    (int(dut.o_wr_reg.value), int(dut.o_wr_value.value))
                )
                for _ in range(WRITE_CYCLES):
                    await RisingEdge(dut.i_clk)
                await Timer(1, unit="ns")
                dut.i_wr_nack.value = int(index in self.nack_on)
                dut.i_wr_done.value = 1
                await RisingEdge(dut.i_clk)
                await Timer(1, unit="ns")
                dut.i_wr_done.value = 0
                dut.i_wr_nack.value = 0


async def start(dut: SeqDut, nack_on: set[int] | None = None) -> FakeWriter:
    """Inicia o clock, o escritor falso e solta o reset.

    Parameters
    ----------
    dut : SeqDut
        Sequenciador sob teste.
    nack_on : set[int] | None
        Pedidos (por posição) que o escritor falso rejeita.

    Returns
    -------
    FakeWriter
        O escritor falso em execução.
    """
    writer = FakeWriter(dut, nack_on or set())
    cocotb.start_soon(Clock(dut.i_clk, CLOCK_NS, unit="ns").start())
    dut.i_rst.value = 1
    dut.i_start.value = 0
    for _ in range(3):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst.value = 0
    cocotb.start_soon(writer.run())
    return writer


async def wait_idle(dut: SeqDut, cycles: int = 200) -> None:
    """Espera o sequenciador ficar parado.

    Parameters
    ----------
    dut : SeqDut
        Sequenciador sob teste.
    cycles : int
        Limite de ciclos de espera.
    """
    for _ in range(cycles):
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
        if not int(dut.o_busy.value):
            return
    message = "o sequenciador não parou"
    raise AssertionError(message)


async def pulse_start(dut: SeqDut) -> None:
    """Dá um pulso de um ciclo em i_start.

    Parameters
    ----------
    dut : SeqDut
        Sequenciador sob teste.
    """
    dut.i_start.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_start.value = 0


def check_counts(dut: SeqDut, sent: int, nacks: int) -> None:
    """Confere os contadores de entradas concluídas e de NACK.

    Parameters
    ----------
    dut : SeqDut
        Sequenciador sob teste.
    sent : int
        Entradas concluídas esperadas.
    nacks : int
        Escritas sem confirmação esperadas.
    """
    check(int(dut.o_sent.value) == sent, f"o_sent {int(dut.o_sent.value)}")
    check(int(dut.o_nacks.value) == nacks, f"o_nacks {int(dut.o_nacks.value)}")
    check(int(dut.o_nack_seen.value) == int(nacks > 0), "o_nack_seen")

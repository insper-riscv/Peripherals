"""Pulsos de borda de SD_CLK para os testes do controlador SD."""

from collections.abc import Awaitable, Callable, Sequence

from cocotb.handle import LogicObject
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.dut import SdStrobeDut


class Strobes:
    """Gera pulsos alternados de subida e de descida, um por ciclo."""

    def __init__(self, dut: SdStrobeDut) -> None:
        """Crie o gerador com a próxima borda sendo de subida.

        Parameters
        ----------
        dut : SdStrobeDut
            Bloco que recebe os pulsos.
        """
        self.dut = dut
        self.rise_next = True

    def drive(self) -> bool:
        """Apresente os pulsos do ciclo que começa.

        Returns
        -------
        bool
            Verdadeiro se o ciclo é o de uma borda de subida.
        """
        rising = self.rise_next
        self.dut.i_rise.value = int(rising)
        self.dut.i_fall.value = int(not rising)
        self.rise_next = not rising
        return rising

    async def edge(self) -> None:
        """Espere a borda do clock e deixe as saídas assentarem."""
        await RisingEdge(self.dut.i_clk)
        await Timer(1, unit="ns")


async def reset_block(dut: SdStrobeDut) -> None:
    """Zere os pulsos e reinicie o bloco, com o clock em marcha.

    Parameters
    ----------
    dut : SdStrobeDut
        Bloco exercitado pelo teste.
    """
    dut.i_rise.value = 0
    dut.i_fall.value = 0
    await bus.hold_reset(dut, hold=2)


def pack(signals: Sequence[LogicObject]) -> int:
    """Junte sinais de um bit numa máscara, o primeiro no bit 0.

    Parameters
    ----------
    signals : Sequence[LogicObject]
        Sinais de um bit.

    Returns
    -------
    int
        A máscara com o valor atual de cada sinal.
    """
    return sum(
        int(signal.value) << index for index, signal in enumerate(signals)
    )


async def run_until_done(
    cycle: Callable[[], Awaitable[bool]], limit: int
) -> None:
    """Avance ciclos até a operação terminar.

    Parameters
    ----------
    cycle : Callable[[], Awaitable[bool]]
        Avança um ciclo e diz se a operação terminou nele.
    limit : int
        Máximo de ciclos.

    Raises
    ------
    AssertionError
        Se a operação não terminar dentro do limite.
    """
    for _ in range(limit):
        if await cycle():
            return
    message = "a operação não terminou"
    raise AssertionError(message)


def flags(dut: SdStrobeDut, *names: str) -> int:
    """Junte sinais de saída de um bit do bloco numa máscara.

    Parameters
    ----------
    dut : SdStrobeDut
        Bloco exercitado pelo teste.
    *names : str
        Nomes dos sinais, o primeiro no bit 0.

    Returns
    -------
    int
        A máscara com o valor atual de cada sinal.
    """
    return pack([getattr(dut, name) for name in names])

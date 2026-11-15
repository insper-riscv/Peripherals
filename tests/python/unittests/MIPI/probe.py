"""Início comum dos testes que coletam eventos a cada ciclo."""

from typing import Protocol

import cocotb

from tests.python.unittests.dut import Dut
from tests.python.utils import bus
from tests.python.utils.dut import ResettableDut

SETTLE_CYCLES = 2


class Collector(Protocol):
    """Coletor de eventos que amostra o projeto a cada ciclo."""

    async def run(self, dut: Dut) -> None:
        """Amostre as saídas do projeto sem parar.

        Parameters
        ----------
        dut : Dut
            Projeto sob teste.
        """


async def launch(dut: ResettableDut, collector: Collector) -> None:
    """Solte o reset, inicie o coletor e deixe o projeto assentar.

    Parameters
    ----------
    dut : ResettableDut
        Projeto sob teste, com as entradas já em repouso.
    collector : Collector
        Coletor de eventos.
    """
    await bus.hold_reset(dut)
    cocotb.start_soon(collector.run(dut))
    await bus.cycles(dut, SETTLE_CYCLES)

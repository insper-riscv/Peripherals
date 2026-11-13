"""Barramentos e linhas do testbench do cabo Y (teclado e mouse).

O testbench tem dois barramentos independentes, com os prefixos ``kb``
(teclado, canal 0) e ``ms`` (mouse, canal 1). ``BusPort`` apresenta um
deles com os nomes que o módulo ``bus`` espera, e ``Ps2Port`` junta as
linhas do conector do mesmo periférico.
"""

from tests.python.utils import bus
from tests.python.utils.dut import IrqDut, Ps2CableTbDut
from tests.python.utils.ps2 import Ps2Lines


class BusPort(IrqDut):
    """Barramento do testbench, com os nomes de um periférico."""

    def __init__(self, dut: Ps2CableTbDut, prefix: str) -> None:
        """Agrupe os sinais de um barramento.

        Parameters
        ----------
        dut : Ps2CableTbDut
            Testbench exercitado.
        prefix : str
            Prefixo do periférico, ``kb`` ou ``ms``.
        """
        self.i_clk = dut.i_clk
        self.i_rst = dut.i_rst
        self.i_write = getattr(dut, f"i_{prefix}_write")
        self.i_read = getattr(dut, f"i_{prefix}_read")
        self.i_address = getattr(dut, f"i_{prefix}_address")
        self.i_data_in = getattr(dut, f"i_{prefix}_data_in")
        self.o_data_out = getattr(dut, f"o_{prefix}_data_out")
        self.o_irq = getattr(dut, f"o_{prefix}_irq")


class Ps2Port(BusPort):
    """Barramento de um periférico e as linhas do conector dele."""

    def __init__(self, dut: Ps2CableTbDut, prefix: str) -> None:
        """Agrupe os sinais do barramento e das linhas.

        Parameters
        ----------
        dut : Ps2CableTbDut
            Testbench exercitado.
        prefix : str
            Prefixo do periférico, ``kb`` ou ``ms``.
        """
        super().__init__(dut, prefix)
        self.lines = Ps2Lines(
            clk_low=getattr(dut, f"i_{prefix}_dev_clk_low"),
            dat_low=getattr(dut, f"i_{prefix}_dev_dat_low"),
            clk=getattr(dut, f"o_{prefix}_clk"),
            dat=getattr(dut, f"o_{prefix}_dat"),
        )


async def setup_port(dut: Ps2CableTbDut, prefix: str) -> Ps2Port:
    """Solte as linhas e zere as entradas de um barramento.

    Parameters
    ----------
    dut : Ps2CableTbDut
        Testbench exercitado.
    prefix : str
        Prefixo do periférico, ``kb`` ou ``ms``.

    Returns
    -------
    Ps2Port
        Barramento e linhas do periférico.
    """
    port = Ps2Port(dut, prefix)
    inputs = (
        port.lines.clk_low,
        port.lines.dat_low,
        port.i_write,
        port.i_read,
        port.i_address,
        port.i_data_in,
    )
    for signal in inputs:
        signal.value = 0
    return port


async def setup_cable(dut: Ps2CableTbDut) -> tuple[Ps2Port, Ps2Port]:
    """Reinicie o cabo e devolva os barramentos do teclado e do mouse.

    Parameters
    ----------
    dut : Ps2CableTbDut
        Testbench exercitado.

    Returns
    -------
    tuple[Ps2Port, Ps2Port]
        Barramento do teclado e barramento do mouse.
    """
    keyboard = await setup_port(dut, "kb")
    mouse = await setup_port(dut, "ms")
    await bus.reset(keyboard)
    return keyboard, mouse

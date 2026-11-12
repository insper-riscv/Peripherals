"""Clocks, reset e acessos ao barramento do periférico de vídeo."""

from collections.abc import Iterable

import cocotb
from cocotb.clock import Clock
from cocotb.task import Task
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.dut import Dut
from tests.python.unittests.video.registers import MASK32
from tests.python.unittests.video.signals import VideoDut
from tests.python.utils.bus import cycles

PIXEL_NS = 40
SYSTEM_NS = 13
RESET_EDGES = 30
FULL_MASK = 0xF


def drive(dut: Dut, **values: int) -> None:
    """Escreve vários sinais de entrada de uma vez.

    Parameters
    ----------
    dut : Dut
        Projeto sob teste.
    **values : int
        Valor de cada sinal, indexado pelo nome da porta.
    """
    for name, value in values.items():
        getattr(dut, name).value = value


async def start(
    dut: VideoDut, system_ns: int = SYSTEM_NS, pixel_ns: int = PIXEL_NS
) -> list[Task[None]]:
    """Inicia os dois clocks, aplica o reset e o solta.

    O reset dura vários ciclos de pixel, como o periférico exige.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    system_ns : int
        Período do clock do sistema em nanossegundos.
    pixel_ns : int
        Período do clock de pixel em nanossegundos.

    Returns
    -------
    list[Task[None]]
        As tarefas dos clocks, para cancelá-las ao trocar o período.
    """
    tasks = [
        cocotb.start_soon(Clock(dut.i_clk, system_ns, unit="ns").start()),
        cocotb.start_soon(Clock(dut.i_pixel_clk, pixel_ns, unit="ns").start()),
    ]
    drive(
        dut,
        i_rst=1,
        i_write=0,
        i_address=0,
        i_data_in=0,
        i_byteena=FULL_MASK,
    )
    await cycles(dut, RESET_EDGES)
    drive(dut, i_rst=0)
    await cycles(dut, 1)
    return tasks


async def write_burst(
    dut: VideoDut, accesses: Iterable[tuple[int, int, int]]
) -> None:
    """Escreve uma sequência de acessos, um por ciclo do sistema.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    accesses : Iterable[tuple[int, int, int]]
        Tuplas de endereço de palavra, dado e máscara de bytes.
    """
    dut.i_write.value = 1
    for address, data, mask in accesses:
        drive(dut, i_address=address, i_data_in=data & MASK32, i_byteena=mask)
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_write.value = 0
    # A escrita sai registrada: dois ciclos a levam até a memória.
    await cycles(dut, 2)


async def write(
    dut: VideoDut, address: int, data: int, mask: int = FULL_MASK
) -> None:
    """Escreve uma palavra com máscara de bytes.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    address : int
        Endereço de palavra.
    data : int
        Dado de 32 bits.
    mask : int
        Habilitação de bytes, um bit por byte.
    """
    await write_burst(dut, [(address, data, mask)])


async def read(dut: VideoDut, address: int) -> int:
    """Lê uma palavra; a leitura é combinacional no endereço.

    Parameters
    ----------
    dut : VideoDut
        Periférico sob teste.
    address : int
        Endereço de palavra.

    Returns
    -------
    int
        O dado lido.
    """
    dut.i_address.value = address
    await Timer(1, unit="ns")
    return int(dut.o_data_out.value)

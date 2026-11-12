"""Memória de duas portas: faixas de escrita, latência e clocks."""

import cocotb
from cocotb.clock import Clock
from cocotb.task import Task
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.video.signals import DpramDut
from tests.python.utils.check import check
from tests.python.utils.rng import seeded

SEED = 0xD9A
ACCESSES = 400
RATIOS = ((13, 40), (40, 13), (27, 27))


def widths(dut: DpramDut) -> tuple[int, int, int]:
    """Lê as faixas, a largura de cada uma e o endereço das portas.

    Parameters
    ----------
    dut : DpramDut
        Memória sob teste.

    Returns
    -------
    tuple[int, int, int]
        Número de faixas, largura da faixa e largura do endereço.
    """
    lanes = len(dut.i_we)
    return lanes, len(dut.i_wdata) // lanes, len(dut.i_waddr)


async def write(dut: DpramDut, address: int, data: int, mask: int) -> None:
    """Escreve uma palavra na porta de escrita.

    Parameters
    ----------
    dut : DpramDut
        Memória sob teste.
    address : int
        Endereço de escrita.
    data : int
        Dado de escrita.
    mask : int
        Habilitação das faixas.
    """
    dut.i_waddr.value = address
    dut.i_wdata.value = data
    dut.i_we.value = mask
    await RisingEdge(dut.i_wclk)
    await Timer(1, unit="ns")
    dut.i_we.value = 0


async def read(dut: DpramDut, address: int) -> int:
    """Lê uma palavra pela porta de leitura, que registra o dado.

    Parameters
    ----------
    dut : DpramDut
        Memória sob teste.
    address : int
        Endereço de leitura.

    Returns
    -------
    int
        O dado visível depois da borda do clock de leitura.
    """
    dut.i_raddr.value = address
    await RisingEdge(dut.i_rclk)
    await Timer(1, unit="ns")
    return int(dut.o_rdata.value)


def start(dut: DpramDut, write_ns: int, read_ns: int) -> list[Task[None]]:
    """Inicia os dois clocks e zera as entradas.

    Parameters
    ----------
    dut : DpramDut
        Memória sob teste.
    write_ns : int
        Período do clock de escrita.
    read_ns : int
        Período do clock de leitura.

    Returns
    -------
    list[Task[None]]
        As tarefas dos clocks.
    """
    tasks = [
        cocotb.start_soon(Clock(dut.i_wclk, write_ns, unit="ns").start()),
        cocotb.start_soon(Clock(dut.i_rclk, read_ns, unit="ns").start()),
    ]
    dut.i_we.value = 0
    dut.i_waddr.value = 0
    dut.i_wdata.value = 0
    dut.i_raddr.value = 0
    return tasks


def merge(old: int, data: int, mask: int, lane_width: int) -> int:
    """Aplica uma escrita por faixas a uma palavra.

    Parameters
    ----------
    old : int
        Palavra anterior.
    data : int
        Dado de escrita.
    mask : int
        Habilitação das faixas.
    lane_width : int
        Largura de cada faixa.

    Returns
    -------
    int
        A palavra resultante.
    """
    lane_mask = (1 << lane_width) - 1
    word = old
    for lane in range(mask.bit_length()):
        if (mask >> lane) & 1:
            shift = lane * lane_width
            word = (word & ~(lane_mask << shift)) | (
                data & (lane_mask << shift)
            )
    return word


async def random_accesses(
    dut: DpramDut, seed: int, model: dict[int, int]
) -> None:
    """Escreve e lê endereços aleatórios contra um modelo.

    Parameters
    ----------
    dut : DpramDut
        Memória sob teste.
    seed : int
        Semente do estímulo.
    model : dict[int, int]
        Conteúdo esperado, que a memória guarda entre as chamadas.
    """
    lanes, lane_width, _ = widths(dut)
    depth = 2 ** len(dut.i_waddr)
    rng = seeded(seed)
    for _ in range(ACCESSES):
        address = rng.randrange(0, min(depth, 64))
        data = rng.getrandbits(lanes * lane_width)
        mask = rng.randrange(0, 1 << lanes)
        await write(dut, address, data, mask)
        model[address] = merge(model.get(address, 0), data, mask, lane_width)
        probe = rng.choice(list(model))
        # Dois ciclos de leitura cobrem qualquer razão entre os clocks.
        await read(dut, probe)
        got = await read(dut, probe)
        check(got == model[probe], f"{probe}: {got:#x} != {model[probe]:#x}")


@cocotb.test()
async def test_lanes_and_clock_ratios(dut: DpramDut) -> None:
    """Cada faixa grava sozinha, em qualquer razão entre os clocks."""
    model: dict[int, int] = {}
    for write_ns, read_ns in RATIOS:
        tasks = start(dut, write_ns, read_ns)
        await Timer(5 * max(write_ns, read_ns), unit="ns")
        await random_accesses(dut, SEED + write_ns, model)
        for task in tasks:
            task.cancel()


@cocotb.test()
async def test_read_is_registered(dut: DpramDut) -> None:
    """O dado lido só muda na borda do clock de leitura."""
    start(dut, 13, 40)
    await Timer(100, unit="ns")
    lanes, lane_width, _ = widths(dut)
    full = (1 << (lanes * lane_width)) - 1
    await write(dut, 1, full, (1 << lanes) - 1)
    await write(dut, 2, 0, (1 << lanes) - 1)
    check(await read(dut, 1) == full, "o dado chega na borda")
    dut.i_raddr.value = 2
    await Timer(1, unit="ns")
    check(int(dut.o_rdata.value) == full, "a saída muda sem borda de clock")
    await RisingEdge(dut.i_rclk)
    await Timer(1, unit="ns")
    check(int(dut.o_rdata.value) == 0, "a saída segue o novo endereço")

"""Mestre do barramento do chip: etapas, pinos e amostragem do dado."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.USB.signals import MasterDut
from tests.python.utils import bus
from tests.python.utils.check import check_equal

SETUP = 3
PULSE = 4
RECOVERY = 2
WORD = 0xC0DE
CHIP_WORD = 0x1357


async def begin(dut: MasterDut) -> None:
    """Inicia o clock, aplica o reset e configura as durações.

    Parameters
    ----------
    dut : MasterDut
        Mestre sob teste.
    """
    idle = {
        "i_start": 0,
        "i_is_read": 0,
        "i_port": 0,
        "i_wdata": 0,
        "i_chip_data": 0,
    }
    for name, value in idle.items():
        getattr(dut, name).value = value
    for name, cycles in zip(
        ("i_setup", "i_pulse", "i_recovery"),
        (SETUP, PULSE, RECOVERY),
        strict=True,
    ):
        getattr(dut, name).value = cycles
    await bus.hold_reset(dut)


async def tick(dut: MasterDut) -> tuple[int, int, int, int, int, int]:
    """Avança um ciclo e devolve os pinos.

    Parameters
    ----------
    dut : MasterDut
        Mestre sob teste.

    Returns
    -------
    tuple[int, int, int, int, int, int]
        Seleção, leitura, escrita, ocupado, habilitação do dado e dado.
    """
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    return (
        int(dut.o_cs_n.value),
        int(dut.o_rd_n.value),
        int(dut.o_wr_n.value),
        int(dut.o_busy.value),
        int(dut.o_chip_data_oe.value),
        int(dut.o_chip_data.value),
    )


async def request(dut: MasterDut, is_read: int, port: int, data: int) -> None:
    """Pede um acesso por um ciclo.

    Parameters
    ----------
    dut : MasterDut
        Mestre sob teste.
    is_read : int
        1 para leitura, 0 para escrita.
    port : int
        Endereço do chip.
    data : int
        Dado de escrita.
    """
    bus.set_inputs(dut, i_is_read=is_read, i_port=port, i_wdata=data)
    await bus.pulse(dut, "i_start")


@cocotb.test()
async def write_access(dut: MasterDut) -> None:
    """Uma escrita tem preparação, pulso, retenção e recuperação."""
    await begin(dut)
    await request(dut, 0, 2, WORD)
    first = (
        int(dut.o_cs_n.value),
        int(dut.o_rd_n.value),
        int(dut.o_wr_n.value),
        int(dut.o_busy.value),
        int(dut.o_chip_data_oe.value),
        int(dut.o_chip_data.value),
    )
    seen = [first]
    seen += [await tick(dut) for _ in range(SETUP + PULSE + 1 + RECOVERY)]
    check_equal(int(dut.o_chip_addr.value), 2)
    # (cs_n, wr_n) esperados em cada ciclo, depois do pedido.
    want = [(0, 1)] * SETUP + [(0, 0)] * PULSE + [(0, 1)] + [(1, 1)] * RECOVERY
    for index, (cs_n, rd_n, wr_n, busy, oe, data) in enumerate(seen[:-1]):
        check_equal(cs_n, want[index][0])
        check_equal(wr_n, want[index][1])
        check_equal(rd_n, 1)
        check_equal(busy, 1)
        check_equal(oe, 1 if index <= SETUP + PULSE else 0)
        if oe:
            check_equal(data, WORD)
    check_equal(seen[-1][3], 0)
    check_equal(seen[-1][0], 1)


@cocotb.test()
async def read_access(dut: MasterDut) -> None:
    """Uma leitura amostra o dado no fim do pulso e o mantém."""
    await begin(dut)
    dut.i_chip_data.value = CHIP_WORD
    await request(dut, 1, 1, 0)
    strobes = 0
    for _ in range(SETUP + PULSE + 1 + RECOVERY + 2):
        _, rd_n, wr_n, _, oe, _ = await tick(dut)
        check_equal(oe, 0)
        check_equal(wr_n, 1)
        strobes += 1 - rd_n
    check_equal(strobes, PULSE)
    check_equal(int(dut.o_rdata.value), CHIP_WORD)
    dut.i_chip_data.value = 0
    await tick(dut)
    check_equal(int(dut.o_rdata.value), CHIP_WORD)


@cocotb.test()
async def start_ignored_while_busy(dut: MasterDut) -> None:
    """Um pedido com o mestre ocupado não muda o acesso em curso."""
    await begin(dut)
    await request(dut, 0, 3, WORD)
    await tick(dut)
    await request(dut, 0, 1, 0x1111)
    await tick(dut)
    check_equal(int(dut.o_chip_addr.value), 3)
    check_equal(int(dut.o_chip_data.value), WORD)

"""Software de teste: o que o programa faz com a ponte."""

from dataclasses import dataclass

from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.USB import registers as reg
from tests.python.unittests.USB.model import ChipModel, Sample
from tests.python.unittests.USB.signals import UsbDut
from tests.python.utils import bus
from tests.python.utils.check import check

POLL_LIMIT = 2000


@dataclass(frozen=True)
class Transaction:
    """Um acesso ao chip observado nos pinos."""

    setup: int
    pulse: int
    hold: int
    is_read: bool
    addr: int
    data: int
    gap: int


async def start(dut: UsbDut) -> ChipModel:
    """Zera a ponte, deixa o chip ocioso e inicia o modelo.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.

    Returns
    -------
    ChipModel
        O modelo do chip, já observando os pinos.
    """
    dut.i_otg_data.value = 0
    dut.i_otg_int.value = 0
    dut.i_otg_dreq.value = 0
    await bus.reset(dut)
    model = ChipModel(dut)
    model.start()
    return model


async def wait_idle(dut: UsbDut) -> None:
    """Espera o bit de ocupado do estado cair.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.
    """
    for _ in range(POLL_LIMIT):
        status = await bus.read(dut, reg.STATUS)
        if not status & reg.STATUS_BUSY:
            return
    check(False, "a ponte ficou ocupada para sempre")


async def chip_write(dut: UsbDut, port: int, value: int) -> None:
    """Escreve 16 bits numa porta do chip e espera o fim do acesso.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.
    port : int
        Endereço de palavra da porta (0 a 3).
    value : int
        Dado de 16 bits.
    """
    await bus.write(dut, port, value)
    await wait_idle(dut)


async def chip_read(dut: UsbDut, port: int) -> int:
    """Lê 16 bits de uma porta: dispara, espera e lê o resultado.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.
    port : int
        Endereço de palavra da porta (0 a 3).

    Returns
    -------
    int
        O dado lido do chip.
    """
    await bus.read(dut, port)
    await wait_idle(dut)
    return await bus.read(dut, reg.RDATA)


async def read_register(dut: UsbDut, controller: int, command: int) -> int:
    """Lê um registrador do chip: comando e depois dado.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.
    controller : int
        0 para o host, 1 para o dispositivo.
    command : int
        Código do registrador.

    Returns
    -------
    int
        O valor do registrador.
    """
    base = reg.DC_DATA if controller else reg.HC_DATA
    await chip_write(dut, base + 1, command)
    return await chip_read(dut, base)


async def write_register(
    dut: UsbDut, controller: int, command: int, value: int
) -> None:
    """Escreve um registrador do chip: comando e depois dado.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.
    controller : int
        0 para o host, 1 para o dispositivo.
    command : int
        Código do registrador.
    value : int
        Valor a escrever.
    """
    base = reg.DC_DATA if controller else reg.HC_DATA
    await chip_write(dut, base + 1, command)
    await chip_write(dut, base, value)


async def settle(dut: UsbDut, count: int) -> None:
    """Espera alguns ciclos e deixa os sinais assentarem.

    Parameters
    ----------
    dut : UsbDut
        Ponte sob teste.
    count : int
        Número de bordas de clock.
    """
    for _ in range(count):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")


def transactions(log: list[Sample]) -> list[Transaction]:
    """Extrai os acessos do histórico dos pinos.

    Parameters
    ----------
    log : list[Sample]
        Amostra dos pinos a cada ciclo de clock.

    Returns
    -------
    list[Transaction]
        Os acessos, com a duração de cada etapa em ciclos.
    """
    found: list[Transaction] = []
    index = 0
    last_end = -1
    while index < len(log):
        if log[index].cs_n:
            index += 1
            continue
        first = index
        while log[index].rd_n and log[index].wr_n:
            index += 1
        strobe = index
        while not (log[index].rd_n and log[index].wr_n):
            index += 1
        end = index
        while not log[index].cs_n:
            index += 1
        sample = log[strobe]
        found.append(
            Transaction(
                setup=strobe - first,
                pulse=end - strobe,
                hold=index - end,
                is_read=sample.rd_n == 0,
                addr=sample.addr,
                data=sample.data,
                gap=first - last_end if last_end >= 0 else 0,
            )
        )
        last_end = index
    return found

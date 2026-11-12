"""Dispositivo PS/2 simulado e canal de teste do ps2_host.

O dispositivo segura as linhas em nível baixo (open-drain) com os
sinais ``i_dev_clk_low`` e ``i_dev_dat_low`` do testbench, e lê o nível
resolvido das linhas em ``o_clk`` e ``o_dat``.
"""

from collections.abc import Callable
from dataclasses import dataclass, field

import cocotb
from cocotb.clock import Clock
from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import RisingEdge, Timer

from tests.python.utils import bus
from tests.python.utils.dut import Ps2HostTbDut

QUARTER = 20
POLL_LIMIT = 4000
DATA_BITS = 8
FRAME_BITS = 11
ACK_FALLING_EDGE = 10


@dataclass
class Ps2Lines:
    """Linhas do conector, do lado do dispositivo.

    Attributes
    ----------
    clk_low : LogicObject
        O dispositivo segura o clock em baixo.
    dat_low : LogicObject
        O dispositivo segura os dados em baixo.
    clk : LogicObject
        Nível resolvido do clock.
    dat : LogicObject
        Nível resolvido dos dados.
    """

    clk_low: LogicObject
    dat_low: LogicObject
    clk: LogicObject
    dat: LogicObject


@dataclass
class Ps2Host:
    """Portas do ps2_host e o que o monitor observou.

    Attributes
    ----------
    tx_data : LogicArrayObject
        Byte a enviar pelo hospedeiro.
    tx_valid : LogicObject
        Pedido de envio.
    tx_ready : LogicObject
        O transmissor aceita um novo byte.
    rx_data : LogicArrayObject
        Último byte recebido.
    rx_valid : LogicObject
        Pulso de byte recebido.
    rx_error : LogicObject
        Pulso de erro.
    received : list[int]
        Bytes entregues com o pulso de ``o_rx_valid``.
    errors : int
        Quantidade de pulsos de ``o_rx_error``.
    """

    tx_data: LogicArrayObject
    tx_valid: LogicObject
    tx_ready: LogicObject
    rx_data: LogicArrayObject
    rx_valid: LogicObject
    rx_error: LogicObject
    received: list[int] = field(default_factory=list[int])
    errors: int = 0


@dataclass
class Ps2Channel:
    """Um canal do testbench.

    Attributes
    ----------
    lines : Ps2Lines
        Linhas do conector.
    host : Ps2Host
        Portas do hospedeiro.
    """

    lines: Ps2Lines
    host: Ps2Host


def make_channel(dut: Ps2HostTbDut, index: int) -> Ps2Channel:
    """Agrupe os sinais de um canal do testbench.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.
    index : int
        Canal, 0 ou 1.

    Returns
    -------
    Ps2Channel
        Sinais do canal.
    """
    return Ps2Channel(
        lines=Ps2Lines(
            clk_low=getattr(dut, f"i_dev_clk_low{index}"),
            dat_low=getattr(dut, f"i_dev_dat_low{index}"),
            clk=getattr(dut, f"o_clk{index}"),
            dat=getattr(dut, f"o_dat{index}"),
        ),
        host=Ps2Host(
            tx_data=getattr(dut, f"i_tx_data{index}"),
            tx_valid=getattr(dut, f"i_tx_valid{index}"),
            tx_ready=getattr(dut, f"o_tx_ready{index}"),
            rx_data=getattr(dut, f"o_rx_data{index}"),
            rx_valid=getattr(dut, f"o_rx_valid{index}"),
            rx_error=getattr(dut, f"o_rx_error{index}"),
        ),
    )


async def monitor(dut: Ps2HostTbDut, channel: Ps2Channel) -> None:
    """Registre os pulsos de recepção e de erro de um canal.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.
    channel : Ps2Channel
        Canal observado.
    """
    while True:
        await RisingEdge(dut.i_clk)
        if int(channel.host.rx_valid.value):
            channel.host.received.append(int(channel.host.rx_data.value))
        if int(channel.host.rx_error.value):
            channel.host.errors += 1


async def setup(dut: Ps2HostTbDut) -> tuple[Ps2Channel, Ps2Channel]:
    """Reinicie os dois canais, solte as linhas e inicie os monitores.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.

    Returns
    -------
    tuple[Ps2Channel, Ps2Channel]
        Canal 0 e canal 1.
    """
    channels = (make_channel(dut, 0), make_channel(dut, 1))
    for channel in channels:
        channel.lines.clk_low.value = 0
        channel.lines.dat_low.value = 0
        channel.host.tx_data.value = 0
        channel.host.tx_valid.value = 0
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst_n.value = 0
    for _ in range(4):
        await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rst_n.value = 1
    await bus.cycles(dut, 2)
    for channel in channels:
        cocotb.start_soon(monitor(dut, channel))
    return channels


def frame_bits(
    value: int,
    *,
    parity_ok: bool = True,
    stop_ok: bool = True,
    start_ok: bool = True,
) -> list[int]:
    """Monte os 11 bits de um quadro do dispositivo.

    Parameters
    ----------
    value : int
        Byte de dados.
    parity_ok : bool
        Gera paridade ímpar correta.
    stop_ok : bool
        Gera bit de parada em 1.
    start_ok : bool
        Gera bit de início em 0.

    Returns
    -------
    list[int]
        Bits na ordem de transmissao.
    """
    data = [(value >> bit) & 1 for bit in range(DATA_BITS)]
    parity = 1 - (sum(data) % 2)
    return [
        0 if start_ok else 1,
        *data,
        parity if parity_ok else 1 - parity,
        1 if stop_ok else 0,
    ]


async def pulse_clock(dut: Ps2HostTbDut, channel: Ps2Channel) -> None:
    """Gere um pulso de clock do dispositivo, em baixo por meio período.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.
    channel : Ps2Channel
        Canal do dispositivo.
    """
    channel.lines.clk_low.value = 1
    await bus.cycles(dut, 2 * QUARTER)
    channel.lines.clk_low.value = 0


async def device_send(
    dut: Ps2HostTbDut,
    channel: Ps2Channel,
    bits: list[int],
) -> None:
    """Envie bits ao hospedeiro, um por ciclo de clock do dispositivo.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.
    channel : Ps2Channel
        Canal do dispositivo.
    bits : list[int]
        Bits na ordem de transmissao.
    """
    for bit in bits:
        channel.lines.dat_low.value = int(bit == 0)
        await bus.cycles(dut, QUARTER)
        await pulse_clock(dut, channel)
        await bus.cycles(dut, QUARTER)
    channel.lines.dat_low.value = 0
    await bus.cycles(dut, QUARTER)


async def wait_until(dut: Ps2HostTbDut, condition: Callable[[], bool]) -> None:
    """Espere uma condição, ciclo a ciclo, até o limite de espera.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.
    condition : Callable[[], bool]
        Condição esperada.

    Raises
    ------
    TimeoutError
        Se a condição não valer dentro do limite.
    """
    for _ in range(POLL_LIMIT):
        if condition():
            return
        await bus.cycles(dut, 1)
    raise TimeoutError("condição não atingida")


async def device_receive(
    dut: Ps2HostTbDut, channel: Ps2Channel, *, ack: bool = True
) -> tuple[int, bool]:
    """Receba um byte do hospedeiro e responda com o reconhecimento.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.
    channel : Ps2Channel
        Canal do dispositivo.
    ack : bool
        Responde com o bit de reconhecimento.

    Returns
    -------
    tuple[int, bool]
        Byte recebido e se a paridade ímpar e a parada estavam certas.
    """
    await wait_until(dut, lambda: int(channel.lines.clk.value) == 0)
    await wait_until(
        dut,
        lambda: (
            int(channel.lines.clk.value) == 1
            and int(channel.lines.dat.value) == 0
        ),
    )
    await bus.cycles(dut, QUARTER)
    bits: list[int] = []
    for _ in range(DATA_BITS + 1):
        await pulse_clock(dut, channel)
        await bus.cycles(dut, QUARTER)
        bits.append(int(channel.lines.dat.value))
    await pulse_clock(dut, channel)
    await bus.cycles(dut, QUARTER)
    stop = int(channel.lines.dat.value)
    channel.lines.dat_low.value = int(ack)
    await pulse_clock(dut, channel)
    await bus.cycles(dut, QUARTER)
    channel.lines.dat_low.value = 0
    value = sum(bit << index for index, bit in enumerate(bits[:DATA_BITS]))
    odd = (sum(bits) % 2) == 1
    return value, odd and stop == 1


async def host_send(
    dut: Ps2HostTbDut, channel: Ps2Channel, value: int
) -> None:
    """Entregue um byte ao transmissor do hospedeiro.

    Parameters
    ----------
    dut : Ps2HostTbDut
        Testbench exercitado.
    channel : Ps2Channel
        Canal do hospedeiro.
    value : int
        Byte a enviar.
    """
    await wait_until(dut, lambda: int(channel.host.tx_ready.value) == 1)
    channel.host.tx_data.value = value
    channel.host.tx_valid.value = 1
    await bus.cycles(dut, 1)
    channel.host.tx_valid.value = 0

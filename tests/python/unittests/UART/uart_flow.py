"""UART serial com controle de fluxo por hardware (RTS e CTS).

A configuração do teste usa ``BAUD_FREQ=1`` e ``BAUD_LIMIT=0`` (cada bit
serial dura 16 ciclos), filas de quatro bytes e ``HAS_FLOW_CONTROL``. As
duas linhas são de nível baixo ativo. O limiar de RTS do reset é a
metade da fila de recepção, dois bytes. Um modelo do outro lado do
cabo envia bytes só enquanto o RTS da UART está ativo.
"""

import cocotb
from cocotb.triggers import FallingEdge, RisingEdge, with_timeout

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import UartFlowDut
from tests.python.utils.uart_frame import (
    BIT_CYCLES,
    Format,
    receive_frame,
    reset_idle,
    send_frame,
    wait_tx_idle,
)

TX_DATA, RX_DATA, STATUS, CONTROL = range(4)
RX_VALID = 1 << 0
RX_OVERRUN = 1 << 2
TX_EMPTY = 1 << 5
TX_IDLE = 1 << 6
CTS_ACTIVE = 1 << 25
RTS_ACTIVE = 1 << 26
FLOW_ENABLE = 1 << 7
THRESHOLD_SHIFT = 8
FIFO_DEPTH = 4
RESET_THRESHOLD = 2
ACTIVE = 0
INACTIVE = 1
FRAME_CYCLES = BIT_CYCLES * 10
POLL_LIMIT = BIT_CYCLES * 12
PEER_BYTES = 20
READ_PERIOD_CYCLES = 600
NO_START_FRAMES = 6
LOOP_BYTES = 8
BYTE_PLAIN = 0x6B
BYTE_FIRST = 0xC4
BYTE_SECOND = 0xC5


def flow(threshold: int) -> int:
    """Monte o valor de CONTROL com o fluxo ligado.

    Parameters
    ----------
    threshold : int
        Limiar de RTS, em bytes.

    Returns
    -------
    int
        Valor de CONTROL.
    """
    return FLOW_ENABLE | (threshold << THRESHOLD_SHIFT)


def rx_level(status: int) -> int:
    """Extraia a quantidade de bytes da fila de recepção.

    Parameters
    ----------
    status : int
        Valor do registrador de estado.

    Returns
    -------
    int
        Bytes recebidos e ainda não lidos.
    """
    return (status >> 8) & 0xFF


def tx_level(status: int) -> int:
    """Extraia a quantidade de bytes da fila de transmissão.

    Parameters
    ----------
    status : int
        Valor do registrador de estado.

    Returns
    -------
    int
        Bytes esperando o transmissor.
    """
    return (status >> 16) & 0xFF


async def setup(dut: UartFlowDut) -> None:
    """Deixe as linhas ociosas e ativas e reinicie o periférico.

    Parameters
    ----------
    dut : UartFlowDut
        UART exercitada pelo teste.
    """
    dut.i_uart_cts.value = ACTIVE
    await reset_idle(dut)


async def count_starts(dut: UartFlowDut, starts: list[int]) -> None:
    """Conte os bits de início que aparecem na saída serial.

    Parameters
    ----------
    dut : UartFlowDut
        UART exercitada pelo teste.
    starts : list[int]
        Lista que recebe um item por bit de início.
    """
    while True:
        await FallingEdge(dut.o_uart_tx)
        starts.append(1)


async def terminal(dut: UartFlowDut, values: list[int], *, obey: bool) -> None:
    """Modele o outro lado do cabo, que envia bytes em sequência.

    Parameters
    ----------
    dut : UartFlowDut
        UART exercitada pelo teste.
    values : list[int]
        Bytes enviados, na ordem.
    obey : bool
        Espera o RTS ativo antes de cada quadro.
    """
    for value in values:
        while obey and int(dut.o_uart_rts.value) != ACTIVE:
            await RisingEdge(dut.i_clk)
        await send_frame(dut, value, Format())


async def self_wire(dut: UartFlowDut) -> None:
    """Ligue TX a RX e RTS a CTS, com um ciclo de atraso.

    Parameters
    ----------
    dut : UartFlowDut
        UART exercitada pelo teste.
    """
    while True:
        await RisingEdge(dut.i_clk)
        dut.i_uart_rx.value = dut.o_uart_tx.value
        dut.i_uart_cts.value = dut.o_uart_rts.value


@cocotb.test()
async def test_reset_state_and_flow_registers(dut: UartFlowDut) -> None:
    """No reset o fluxo está desligado e o limiar é metade da fila."""
    await setup(dut)
    check(await bus.read(dut, CONTROL) == RESET_THRESHOLD << THRESHOLD_SHIFT)
    check(int(dut.o_uart_rts.value) == ACTIVE)
    check(await bus.read(dut, STATUS) & RTS_ACTIVE != 0)

    await bus.write(dut, CONTROL, flow(3))
    check(await bus.read(dut, CONTROL) == flow(3))
    await bus.write(dut, CONTROL, 0xFF00 | FLOW_ENABLE | 1)
    check(await bus.read(dut, CONTROL) == 0xFF00 | FLOW_ENABLE | 1)


@cocotb.test()
async def test_cts_status_follows_the_pin(dut: UartFlowDut) -> None:
    """CTS_ACTIVE reflete o pino, de nível baixo ativo."""
    await setup(dut)
    await bus.cycles(dut, 3)
    check(await bus.read(dut, STATUS) & CTS_ACTIVE != 0)
    dut.i_uart_cts.value = INACTIVE
    await bus.cycles(dut, 3)
    check(await bus.read(dut, STATUS) & CTS_ACTIVE == 0)
    dut.i_uart_cts.value = ACTIVE
    await bus.cycles(dut, 3)
    check(await bus.read(dut, STATUS) & CTS_ACTIVE != 0)


@cocotb.test()
async def test_flow_disabled_ignores_cts_and_keeps_rts_active(
    dut: UartFlowDut,
) -> None:
    """Sem FLOW_ENABLE a UART ignora CTS e mantém RTS ativo."""
    await setup(dut)
    dut.i_uart_cts.value = INACTIVE
    receiver = cocotb.start_soon(receive_frame(dut, Format()))
    await bus.write(dut, TX_DATA, BYTE_PLAIN)
    check(await receiver == BYTE_PLAIN)

    for value in range(FIFO_DEPTH):
        await send_frame(dut, value, Format())
    check(int(dut.o_uart_rts.value) == ACTIVE)


@cocotb.test()
async def test_cts_inactive_holds_the_queue(dut: UartFlowDut) -> None:
    """Com CTS inativo nenhum quadro começa; ativo, a fila sai."""
    await setup(dut)
    await bus.write(dut, CONTROL, flow(RESET_THRESHOLD))
    dut.i_uart_cts.value = INACTIVE
    await bus.cycles(dut, 3)

    starts: list[int] = []
    cocotb.start_soon(count_starts(dut, starts))
    for value in (0x31, 0x32, 0x33):
        await bus.write(dut, TX_DATA, value)
    await bus.cycles(dut, FRAME_CYCLES * NO_START_FRAMES)
    status = await bus.read(dut, STATUS)
    check(not starts, "nenhum bit de início com CTS inativo")
    check(tx_level(status) == len((0x31, 0x32, 0x33)))
    check(status & TX_EMPTY == 0)

    receiver = cocotb.start_soon(_receive_many(dut, 3))
    dut.i_uart_cts.value = ACTIVE
    check(await with_timeout(receiver, 50, "us") == [0x31, 0x32, 0x33])
    await wait_tx_idle(dut)


async def _receive_many(dut: UartFlowDut, count: int) -> list[int]:
    """Decodifique uma sequência de quadros 8N1 da saída serial.

    Parameters
    ----------
    dut : UartFlowDut
        UART exercitada pelo teste.
    count : int
        Quantidade de quadros esperada.

    Returns
    -------
    list[int]
        Bytes na ordem observada.
    """
    return [await receive_frame(dut, Format()) for _ in range(count)]


@cocotb.test()
async def test_frame_in_flight_finishes_when_cts_falls(
    dut: UartFlowDut,
) -> None:
    """O quadro que já começou termina; o seguinte espera o CTS."""
    await setup(dut)
    await bus.write(dut, CONTROL, flow(RESET_THRESHOLD))

    first = cocotb.start_soon(receive_frame(dut, Format()))
    await bus.write(dut, TX_DATA, BYTE_FIRST)
    await bus.write(dut, TX_DATA, BYTE_SECOND)
    await with_timeout(FallingEdge(dut.o_uart_tx), 5, "us")
    dut.i_uart_cts.value = INACTIVE
    check(
        await first == BYTE_FIRST, "o quadro em curso termina com o byte certo"
    )

    starts: list[int] = []
    cocotb.start_soon(count_starts(dut, starts))
    await bus.cycles(dut, FRAME_CYCLES * NO_START_FRAMES)
    check(not starts, "o segundo quadro espera o CTS")
    check(tx_level(await bus.read(dut, STATUS)) == 1)

    second = cocotb.start_soon(receive_frame(dut, Format()))
    dut.i_uart_cts.value = ACTIVE
    check(await second == BYTE_SECOND)


@cocotb.test()
async def test_rts_follows_the_receive_level(dut: UartFlowDut) -> None:
    """RTS fica inativo no limiar de bytes e volta abaixo dele."""
    await setup(dut)
    await bus.write(dut, CONTROL, flow(RESET_THRESHOLD))
    check(int(dut.o_uart_rts.value) == ACTIVE)

    await send_frame(dut, BYTE_FIRST, Format())
    check(int(dut.o_uart_rts.value) == ACTIVE, "um byte, abaixo do limiar")
    await send_frame(dut, BYTE_SECOND, Format())
    check(int(dut.o_uart_rts.value) == INACTIVE, "dois bytes, no limiar")
    check(await bus.read(dut, STATUS) & RTS_ACTIVE == 0)

    check(await bus.read(dut, RX_DATA) == BYTE_FIRST)
    await bus.cycles(dut, 2)
    check(int(dut.o_uart_rts.value) == ACTIVE, "um byte de novo")
    check(await bus.read(dut, RX_DATA) == BYTE_SECOND)


@cocotb.test()
async def test_rts_threshold_register_is_obeyed(dut: UartFlowDut) -> None:
    """O limiar é por registrador: 1 cai com um byte, 0 fica inativo."""
    await setup(dut)
    await bus.write(dut, CONTROL, flow(1))
    check(int(dut.o_uart_rts.value) == ACTIVE)
    await send_frame(dut, BYTE_PLAIN, Format())
    check(int(dut.o_uart_rts.value) == INACTIVE)
    check(await bus.read(dut, RX_DATA) == BYTE_PLAIN)
    await bus.cycles(dut, 2)
    check(int(dut.o_uart_rts.value) == ACTIVE)

    await bus.write(dut, CONTROL, flow(0))
    await bus.cycles(dut, 2)
    check(int(dut.o_uart_rts.value) == INACTIVE, "limiar zero: sempre inativo")

    await bus.write(dut, CONTROL, flow(FIFO_DEPTH))
    for value in range(FIFO_DEPTH - 1):
        await send_frame(dut, value, Format())
    check(int(dut.o_uart_rts.value) == ACTIVE)
    await send_frame(dut, 0x99, Format())
    check(int(dut.o_uart_rts.value) == INACTIVE)

    await bus.write(dut, CONTROL, 0)
    await bus.cycles(dut, 2)
    check(int(dut.o_uart_rts.value) == ACTIVE, "fluxo desligado: RTS ativo")


@cocotb.test()
async def test_terminal_that_obeys_rts_loses_no_byte(
    dut: UartFlowDut,
) -> None:
    """Com RTS respeitado, um leitor lento recebe tudo, sem overrun."""
    await setup(dut)
    await bus.write(dut, CONTROL, flow(RESET_THRESHOLD))
    sent = [0x40 + index for index in range(PEER_BYTES)]
    peer = cocotb.start_soon(terminal(dut, sent, obey=True))

    got: list[int] = []
    deepest = 0
    while len(got) < PEER_BYTES:
        await bus.cycles(dut, READ_PERIOD_CYCLES)
        status = await bus.read(dut, STATUS)
        check(status & RX_OVERRUN == 0, "overrun com RTS respeitado")
        deepest = max(deepest, rx_level(status))
        if status & RX_VALID:
            got.append(await bus.read(dut, RX_DATA))
    await peer
    check(got == sent)
    check(deepest > 0, "o leitor lento acumulou bytes")
    check(deepest < FIFO_DEPTH, "a fila nunca encheu")


@cocotb.test()
async def test_terminal_that_ignores_rts_overruns_without_flow(
    dut: UartFlowDut,
) -> None:
    """Controle: sem o fluxo, o mesmo leitor lento perde bytes."""
    await setup(dut)
    sent = [0x40 + index for index in range(PEER_BYTES)]
    await terminal(dut, sent, obey=False)
    check(await bus.read(dut, STATUS) & RX_OVERRUN != 0)


@cocotb.test()
async def test_self_loopback_regulates_itself(dut: UartFlowDut) -> None:
    """Com TX em RX e RTS em CTS a UART se regula e não perde byte."""
    await setup(dut)
    cocotb.start_soon(self_wire(dut))
    await bus.write(dut, CONTROL, flow(RESET_THRESHOLD))

    sent = [0x70 + index for index in range(LOOP_BYTES)]
    pending = list(sent)
    for _ in range(POLL_LIMIT):
        if not pending:
            break
        if await bus.read(dut, STATUS) & 2:
            await bus.write(dut, TX_DATA, pending.pop(0))
    await bus.cycles(dut, FRAME_CYCLES * NO_START_FRAMES)
    status = await bus.read(dut, STATUS)
    check(status & RX_OVERRUN == 0)
    check(RESET_THRESHOLD <= rx_level(status) < FIFO_DEPTH, f"{status:#x}")

    got: list[int] = []
    for _ in range(POLL_LIMIT * LOOP_BYTES * 4):
        status = await bus.read(dut, STATUS)
        check(status & RX_OVERRUN == 0)
        if status & RX_VALID:
            got.append(await bus.read(dut, RX_DATA))
        if pending and status & 2:
            await bus.write(dut, TX_DATA, pending.pop(0))
        if len(got) == LOOP_BYTES:
            break
    check(got == sent, f"{got}")

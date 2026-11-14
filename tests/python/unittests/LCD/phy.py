"""lcd_phy: escrita, leitura do ocupado, atraso e tempo limite."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdPhyDut

SETUP = 2
PULSE = 3
HOLD = 2
TIMEOUT_CYCLES = 20
DELAY = 4
MAX_CYCLES = 200
BYTE_A = 0x5A
READS = 3


async def setup(dut: LcdPhyDut) -> None:
    """Aplica o reset e solta as entradas.

    Parameters
    ----------
    dut : LcdPhyDut
        Camada física sob teste.
    """
    bus.set_inputs(
        dut,
        i_start=0,
        i_rs=0,
        i_data=0,
        i_poll=0,
        i_delay=0,
        i_busy_flag=0,
    )
    await bus.hold_reset(dut)
    await bus.cycles(dut, 1)


async def request(
    dut: LcdPhyDut, word: tuple[int, int], poll: int, delay: int
) -> None:
    """Apresenta um pedido e dá o pulso de início por um ciclo.

    Parameters
    ----------
    dut : LcdPhyDut
        Camada física sob teste.
    word : tuple[int, int]
        RS e byte do pedido.
    poll : int
        Espera pelo flag de ocupado.
    delay : int
        Atraso fixo em ciclos.
    """
    rs, data = word
    bus.set_inputs(dut, i_rs=rs, i_data=data, i_poll=poll, i_delay=delay)
    await bus.pulse(dut, "i_start")


async def run(
    dut: LcdPhyDut,
    word: tuple[int, int],
    poll: int,
    delay: int,
    busy: list[int],
) -> list[tuple[int, int, int, int, int]]:
    """Executa uma operação e registra os pinos a cada ciclo.

    Parameters
    ----------
    dut : LcdPhyDut
        Camada física sob teste.
    word : tuple[int, int]
        RS e byte do pedido.
    poll : int
        Espera pelo flag de ocupado.
    delay : int
        Atraso fixo em ciclos.
    busy : list[int]
        Valores do flag de ocupado, um por leitura (o último se repete).

    Returns
    -------
    list[tuple[int, int, int, int, int]]
        Por ciclo, RS, RW, EN, dado e habilitação, até o repouso.
    """
    await request(dut, word, poll, delay)
    trace: list[tuple[int, int, int, int, int]] = []
    reads = 0
    for _ in range(MAX_CYCLES):
        if int(dut.o_ready.value):
            return trace
        en = int(dut.o_lcd_en.value)
        rw = int(dut.o_lcd_rw.value)
        if en and rw:
            dut.i_busy_flag.value = busy[min(reads, len(busy) - 1)]
        if not en and trace and trace[-1][2] and trace[-1][1]:
            reads += 1
        trace.append(
            (
                int(dut.o_lcd_rs.value),
                rw,
                en,
                int(dut.o_lcd_data.value),
                int(dut.o_lcd_data_oe.value),
            )
        )
        await bus.cycles(dut, 1)
    check(False, "a camada física não voltou ao repouso")
    return trace


@cocotb.test()
async def fixed_delay_write(dut: LcdPhyDut) -> None:
    """Dure setup, pulso, hold e atraso numa escrita sem leitura."""
    await setup(dut)
    trace = await run(dut, (1, BYTE_A), 0, DELAY, [0])
    check(len(trace) == SETUP + PULSE + HOLD + DELAY, f"{len(trace)} ciclos")
    enables = [row[2] for row in trace]
    check(enables == [0] * SETUP + [1] * PULSE + [0] * (HOLD + DELAY), "EN")
    end_of_hold = SETUP + PULSE + HOLD
    for row in trace[:end_of_hold]:
        check(row[:2] == (1, 0) and row[3] == BYTE_A and row[4] == 1, f"{row}")
    check(
        all(row[4] == 0 for row in trace[end_of_hold:]),
        "driver solto",
    )
    check(int(dut.o_timeout.value) == 0, "sem tempo limite")


@cocotb.test()
async def zero_delay_write(dut: LcdPhyDut) -> None:
    """Com atraso zero a camada volta ao repouso logo depois do hold."""
    await setup(dut)
    trace = await run(dut, (0, 0x01), 0, 0, [0])
    check(len(trace) == SETUP + PULSE + HOLD, f"{len(trace)} ciclos")


@cocotb.test()
async def busy_polling(dut: LcdPhyDut) -> None:
    """Leia o ocupado até baixar, com RW alto e o driver solto."""
    await setup(dut)
    trace = await run(dut, (1, 0x33), 1, DELAY, [1, 1, 0])
    read_rows = [row for row in trace if row[1] == 1]
    check(read_rows != [], "houve leitura")
    check(
        all(row[0] == 0 and row[4] == 0 for row in read_rows),
        "RS baixo, solto",
    )
    pulses = sum(
        1
        for i, row in enumerate(trace)
        if row[2] and row[1] and not trace[i - 1][2]
    )
    check(pulses == READS, f"{pulses} leituras")
    check(int(dut.o_lcd_rw.value) == 0, "RW volta a zero")
    check(int(dut.o_timeout.value) == 0, "sem tempo limite")


@cocotb.test()
async def busy_timeout(dut: LcdPhyDut) -> None:
    """Desista com o ocupado preso e acenda o tempo limite."""
    await setup(dut)
    seen = False
    await request(dut, (1, 0x11), 1, 0)
    for _ in range(MAX_CYCLES):
        if int(dut.o_lcd_en.value) and int(dut.o_lcd_rw.value):
            dut.i_busy_flag.value = 1
        seen = seen or bool(int(dut.o_timeout.value))
        if int(dut.o_ready.value):
            break
        await bus.cycles(dut, 1)
    await bus.cycles(dut, 1)
    check(int(dut.o_ready.value) == 1, "voltou ao repouso")
    check(seen or int(dut.o_timeout.value) == 1, "pulso de tempo limite")

"""LCD 16x2 com a inicialização em hardware ligada."""

import cocotb

from tests.python.unittests.LCD import common as c
from tests.python.unittests.LCD.hd44780 import POWER_UP_NS
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdDut

INIT_WRITES = [
    (0, 0x30),
    (0, 0x30),
    (0, 0x30),
    (0, 0x38),
    (0, 0x0C),
    (0, 0x01),
    (0, 0x06),
]
INIT_LIMIT = 600_000
EARLY_CYCLES = 100


@cocotb.test()
async def initializes_then_drains_the_queue(dut: LcdDut) -> None:
    """Rode a sequência com uma escrita antecipada na fila."""
    chip = await c.start(dut, power_up_ns=POWER_UP_NS)
    await bus.write(dut, c.CONTROL, c.IRQ_ENABLE | c.POLL_ENABLE | c.LCD_ON)
    await c.put(dut, None, ord("A"))
    await bus.cycles(dut, EARLY_CYCLES)
    status = await bus.read(dut, c.STATUS)
    check(c.flag(status, c.INIT_BUSY), "inicialização em andamento")
    check(
        not c.flag(status, c.FIFO_EMPTY), "a escrita antecipada espera na fila"
    )
    check(int(dut.o_irq.value) == 0, "sem interrupção durante a inicialização")
    done = False
    for _ in range(INIT_LIMIT):
        await bus.cycles(dut, 1)
        if int(dut.o_irq.value):
            done = True
            break
    check(done, "a inicialização terminou")
    status = await c.wait_idle(dut)
    check(not c.flag(status, c.INIT_BUSY), "INIT_BUSY baixo")
    check(chip.violations == [], f"violações {chip.violations}")
    check(
        chip.writes == [*INIT_WRITES, (1, ord("A"))], f"escritas {chip.writes}"
    )
    state = chip.state
    check(
        state.two_lines and state.display_on and state.increment,
        "estado do chip",
    )
    check(chip.line(0).startswith("A"), f"linha 1 {chip.line(0)!r}")

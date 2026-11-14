"""LCD 16x2 com o pino RW fixo em zero: só atraso por registrador."""

import cocotb

from tests.python.unittests.LCD import common as c
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdDut

CHARS = "fixed rw"
WATCH_CYCLES = 3000


@cocotb.test()
async def writes_with_delay_only(dut: LcdDut) -> None:
    """Escreva com RW baixo e POLL_ENABLE preso em zero."""
    chip = await c.start(dut)
    check(
        await bus.read(dut, c.CONTROL) == c.LCD_ON, "poll desligado no reset"
    )
    await bus.write(dut, c.CONTROL, c.POLL_ENABLE | c.LCD_ON)
    check(await bus.read(dut, c.CONTROL) == c.LCD_ON, "poll não liga sem RW")
    await c.manual_init(dut)
    await c.text(dut, CHARS)
    for _ in range(WATCH_CYCLES):
        await bus.cycles(dut, 1)
        check(int(dut.o_lcd_rw.value) == 0, "RW fixo em zero")
    await c.wait_idle(dut)
    check(chip.violations == [], f"violações {chip.violations}")
    check(chip.busy_polls == 0, "nenhuma leitura do ocupado")
    check(chip.line(0).rstrip() == CHARS, f"linha 1 {chip.line(0)!r}")

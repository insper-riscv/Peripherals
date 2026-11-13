"""LCD 16x2 com um flag de ocupado que nunca baixa."""

import cocotb

from tests.python.unittests.LCD import common as c
from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdDut

STUCK_BUSY = 0x80
TIMEOUT_CYCLES = 2000
MARGIN_CYCLES = 600


@cocotb.test()
async def gives_up_waiting_for_busy(dut: LcdDut) -> None:
    """Desista da espera, acenda TIMEOUT e siga adiante."""
    await bus.reset(dut, hold=4, period_ns=c.CLOCK_NS)
    dut.i_lcd_data.value = STUCK_BUSY
    await c.put(dut, None, ord("a"))
    await c.put(dut, None, ord("b"))
    await bus.cycles(dut, 2 * (TIMEOUT_CYCLES + MARGIN_CYCLES))
    status = await bus.read(dut, c.STATUS)
    check(c.flag(status, c.TIMEOUT), "TIMEOUT aceso")
    check(not c.flag(status, c.BUSY), "o controlador seguiu adiante")
    check(c.flag(status, c.FIFO_EMPTY), "as duas escritas foram consumidas")
    await bus.write(dut, c.STATUS, c.TIMEOUT)
    check(
        not c.flag(await bus.read(dut, c.STATUS), c.TIMEOUT), "TIMEOUT limpo"
    )

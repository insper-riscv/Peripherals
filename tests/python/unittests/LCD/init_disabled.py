"""lcd_init desligado: fica pronto e não envia nada."""

import cocotb

from tests.python.utils import bus
from tests.python.utils.check import check
from tests.python.utils.dut import LcdInitDut

WATCH_CYCLES = 200


@cocotb.test()
async def stays_idle(dut: LcdInitDut) -> None:
    """Sem enabled, o_busy fica em zero e o_start nunca sobe."""
    dut.i_phy_ready.value = 1
    await bus.hold_reset(dut)
    for _ in range(WATCH_CYCLES):
        await bus.cycles(dut, 1)
        check(
            int(dut.o_busy.value) == 0 and int(dut.o_start.value) == 0,
            "ocioso",
        )

"""Ponte USB com as interrupções do chip ativas em nível baixo."""

import cocotb

from tests.python.unittests.USB import usb_bridge
from tests.python.unittests.USB.signals import UsbDut


@cocotb.test()
async def interrupts_active_low(dut: UsbDut) -> None:
    """O programa vê as interrupções ativas em '1' com pinos em '0'."""
    usb_bridge.ACTIVE_HIGH_INT = False
    await usb_bridge.check_interrupts(dut)

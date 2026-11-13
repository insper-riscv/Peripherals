"""Registradores da ponte: decodificação, erro e temporização."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.USB import registers as reg
from tests.python.unittests.USB.signals import RegsDut
from tests.python.utils import bus
from tests.python.utils.check import check_equal


async def begin(dut: RegsDut) -> None:
    """Inicia o clock e aplica o reset com as entradas ociosas.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    """
    for name in ("i_busy", "i_rdata", "i_int", "i_dreq"):
        getattr(dut, name).value = 0
    await bus.reset(dut)


@cocotb.test()
async def port_requests(dut: RegsDut) -> None:
    """Escrita e leitura das quatro portas geram o pedido ao mestre."""
    await begin(dut)
    for port in range(4):
        dut.i_address.value = port
        dut.i_data_in.value = 0xFFFF_1000 + port
        dut.i_write.value = 1
        await Timer(1, unit="ns")
        check_equal(int(dut.o_start.value), 1)
        check_equal(int(dut.o_is_read.value), 0)
        check_equal(int(dut.o_port.value), port)
        check_equal(int(dut.o_wdata.value), 0x1000 + port)
        dut.i_write.value = 0
        dut.i_read.value = 1
        await Timer(1, unit="ns")
        check_equal(int(dut.o_start.value), 1)
        check_equal(int(dut.o_is_read.value), 1)
        check_equal(int(dut.o_data_out.value), 0)
        dut.i_read.value = 0
    dut.i_address.value = reg.CTRL
    dut.i_write.value = 1
    await Timer(1, unit="ns")
    check_equal(int(dut.o_start.value), 0)
    dut.i_write.value = 0


@cocotb.test()
async def busy_drops_and_flags(dut: RegsDut) -> None:
    """Com o mestre ocupado o pedido não sai e o erro fica ligado."""
    await begin(dut)
    dut.i_busy.value = 1
    dut.i_address.value = reg.HC_DATA
    dut.i_write.value = 1
    await Timer(1, unit="ns")
    check_equal(int(dut.o_start.value), 0)
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_write.value = 0
    status = await bus.read(dut, reg.STATUS)
    check_equal(status, reg.STATUS_BUSY | reg.STATUS_ERROR)
    dut.i_busy.value = 0
    await bus.write(dut, reg.STATUS, reg.STATUS_ERROR)
    check_equal(await bus.read(dut, reg.STATUS), 0)


@cocotb.test()
async def control_mask_timing(dut: RegsDut) -> None:
    """Guarda o controle, a máscara e a temporização escritos."""
    await begin(dut)
    check_equal(int(dut.o_chip_reset.value), 1)
    check_equal(int(dut.o_setup.value), reg.DEFAULT_SETUP)
    check_equal(int(dut.o_pulse.value), reg.DEFAULT_PULSE)
    check_equal(int(dut.o_recovery.value), reg.DEFAULT_RECOVERY)
    await bus.write(dut, reg.TIMING, 0x030201)
    check_equal(int(dut.o_setup.value), 1)
    check_equal(int(dut.o_pulse.value), 2)
    check_equal(int(dut.o_recovery.value), 3)
    await bus.write(dut, reg.CTRL, reg.CTRL_DACK)
    check_equal(int(dut.o_chip_reset.value), 0)
    check_equal(int(dut.o_dack.value), 1)
    dut.i_int.value = 0b10
    dut.i_rdata.value = 0xBEEF
    check_equal(int(dut.o_irq.value), 0)
    await bus.write(dut, reg.IRQ_MASK, 0b10)
    check_equal(int(dut.o_irq.value), 1)
    check_equal(await bus.read(dut, reg.RDATA), 0xBEEF)
    check_equal(await bus.read(dut, reg.STATUS), reg.STATUS_INT1)

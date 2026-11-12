"""PS2_MOUSE_OPERATION_DECODER: o mapa de registradores do mouse."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.PS2.mouse.registers import (
    BUTTONS,
    CONTROL,
    DX,
    DY,
    STATUS,
)
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MouseOperationDecoderDut

ADDRESSES = 8
RD_SEL = {STATUS: 0, DX: 1, DY: 2, BUTTONS: 3, CONTROL: 4}
RESERVED_SEL = 0b111


async def drive(
    dut: MouseOperationDecoderDut, address: int, write: int, read: int
) -> None:
    """Conduza as entradas de barramento do decodificador e espere.

    Parameters
    ----------
    dut : MouseOperationDecoderDut
        Projeto sob teste.
    address : int
        Endereço do registrador.
    write : int
        Valor do pulso de escrita.
    read : int
        Valor do pulso de leitura.
    """
    dut.i_address.value = address
    dut.i_write.value = write
    dut.i_read.value = read
    await Timer(1, unit="ns")


@cocotb.test()
async def test_read_selector(dut: MouseOperationDecoderDut) -> None:
    """Cada endereço seleciona o seu registrador; o resto, zero."""
    for address in range(ADDRESSES):
        await drive(dut, address, 0, 0)
        want = RD_SEL.get(address, RESERVED_SEL)
        check_equal(int(dut.o_rd_sel.value), want)


@cocotb.test()
async def test_read_pulses(dut: MouseOperationDecoderDut) -> None:
    """Uma leitura pulsa a limpeza do seu registrador e só dele."""
    for address in range(ADDRESSES):
        await drive(dut, address, 0, 1)
        check(int(dut.o_status_read.value) == (address == STATUS))
        check(int(dut.o_dx_read.value) == (address == DX))
        check(int(dut.o_dy_read.value) == (address == DY))
        check(int(dut.o_control_write.value) == 0)


@cocotb.test()
async def test_write_pulse(dut: MouseOperationDecoderDut) -> None:
    """Só uma escrita em CONTROL pulsa a escrita de controle."""
    for address in range(ADDRESSES):
        await drive(dut, address, 1, 0)
        check(int(dut.o_control_write.value) == (address == CONTROL))
        check(int(dut.o_status_read.value) == 0)
        check(int(dut.o_dx_read.value) == 0)
        check(int(dut.o_dy_read.value) == 0)


@cocotb.test()
async def test_idle(dut: MouseOperationDecoderDut) -> None:
    """Sem pulso de entrada, nenhum pulso sai."""
    for address in range(ADDRESSES):
        await drive(dut, address, 0, 0)
        check(int(dut.o_status_read.value) == 0)
        check(int(dut.o_dx_read.value) == 0)
        check(int(dut.o_dy_read.value) == 0)
        check(int(dut.o_control_write.value) == 0)

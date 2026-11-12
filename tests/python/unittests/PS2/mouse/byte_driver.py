"""Estímulo de bytes na interface do decodificador do mouse PS/2."""

from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.PS2.mouse.registers import (
    CMD_ENABLE,
    CMD_RESET,
    RSP_ACK,
    RSP_ID,
    RSP_SELF_TEST,
)
from tests.python.utils import bus
from tests.python.utils.dut import ByteHostDut

MAX_WAIT = 400


async def send_byte(dut: ByteHostDut, value: int) -> None:
    """Entregue um byte recebido ao mouse, como pulso de um ciclo.

    Parameters
    ----------
    dut : ByteHostDut
        Projeto sob teste.
    value : int
        Byte que o dispositivo enviou.
    """
    dut.i_rx_data.value = value
    dut.i_rx_valid.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rx_valid.value = 0


async def send_rx_error(dut: ByteHostDut) -> None:
    """Entregue um erro de quadro ou de paridade de um ciclo.

    Parameters
    ----------
    dut : ByteHostDut
        Projeto sob teste.
    """
    dut.i_rx_error.value = 1
    await RisingEdge(dut.i_clk)
    await Timer(1, unit="ns")
    dut.i_rx_error.value = 0


async def expect_tx(dut: ByteHostDut, value: int) -> None:
    """Espere o mouse enviar um byte e confira.

    O transmissor fica pronto só durante a espera, então o byte sai
    no primeiro ciclo em que é pedido, e o pedido dura um ciclo.

    Parameters
    ----------
    dut : ByteHostDut
        Projeto sob teste.
    value : int
        Byte que o mouse deve enviar.

    Raises
    ------
    AssertionError
        Se o byte não vier a tempo ou não for o esperado.
    """
    dut.i_tx_ready.value = 1
    await Timer(1, unit="ns")
    for _ in range(MAX_WAIT):
        if int(dut.o_tx_valid.value) == 1:
            got = int(dut.o_tx_data.value)
            if got != value:
                raise AssertionError(f"enviou {got:#x}, queria {value:#x}")
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            if int(dut.o_tx_valid.value) != 0:
                raise AssertionError("tx_valid durou mais de um ciclo")
            dut.i_tx_ready.value = 0
            return
        await RisingEdge(dut.i_clk)
        await Timer(1, unit="ns")
    raise AssertionError(f"byte {value:#x} nunca foi enviado")


async def initialize(dut: ByteHostDut) -> None:
    """Execute a troca completa de respostas da inicialização.

    Parameters
    ----------
    dut : ByteHostDut
        Projeto sob teste.
    """
    await expect_tx(dut, CMD_RESET)
    for response in (RSP_ACK, RSP_SELF_TEST, RSP_ID):
        await send_byte(dut, response)
    await expect_tx(dut, CMD_ENABLE)
    await send_byte(dut, RSP_ACK)


async def send_packet(
    dut: ByteHostDut, dx: int, dy: int, buttons: int = 0, overflow: int = 0
) -> None:
    """Envie um pacote de movimento de 3 bytes.

    Parameters
    ----------
    dut : ByteHostDut
        Projeto sob teste.
    dx : int
        Deslocamento X com sinal, de -256 a 255.
    dy : int
        Deslocamento Y com sinal, de -256 a 255.
    buttons : int
        Bit 0 esquerdo, bit 1 direito, bit 2 meio.
    overflow : int
        Bit 0 estouro em X, bit 1 estouro em Y.
    """
    first = 0x08 | buttons
    first |= ((dx >> 8) & 1) << 4
    first |= ((dy >> 8) & 1) << 5
    first |= (overflow & 3) << 6
    for value in (first, dx & 0xFF, dy & 0xFF):
        await send_byte(dut, value)


async def reset_idle(dut: ByteHostDut) -> None:
    """Reinicie com a interface de bytes parada e o host ocupado.

    Parameters
    ----------
    dut : ByteHostDut
        Projeto sob teste.
    """
    dut.i_rx_data.value = 0
    dut.i_rx_valid.value = 0
    dut.i_rx_error.value = 0
    dut.i_tx_ready.value = 0
    await bus.hold_reset(dut)

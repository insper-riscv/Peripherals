"""Mouse PS/2 com o ps2_host real: inicialização e registradores."""

import cocotb

from tests.python.unittests.PS2.mouse.registers import (
    BUTTONS,
    CMD_ENABLE,
    CMD_RESET,
    CONTROL,
    DX,
    DY,
    ERROR,
    IRQ_ENABLE,
    NEW,
    OVERFLOW,
    REINIT,
    RSP_ACK,
    RSP_ID,
    RSP_SELF_TEST,
    STATUS,
    STREAMING,
)
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import Ps2CableTbDut
from tests.python.utils.ps2 import (
    Ps2Lines,
    device_receive,
    device_send,
    frame_bits,
)
from tests.python.utils.ps2_cable import Ps2Port, setup_port

SETTLE = 8
# Silêncio aceito no meio de um pacote, igual ao generic do testbench.
PACKET_TIMEOUT = 1500
FIRST_BYTE_BASE = 0x08
BAD_FIRST_BYTE = 0x00
SHORT_PACKET = (0x09, 0x11)


def signed16(value: int) -> int:
    """Interprete uma leitura de 32 bits como número com sinal.

    Parameters
    ----------
    value : int
        Palavra lida do barramento.

    Returns
    -------
    int
        Valor com sinal.
    """
    return value - (1 << 32) if value & (1 << 31) else value


async def reply(port: Ps2Port, values: tuple[int, ...]) -> None:
    """Envie bytes do mouse simulado ao hospedeiro, um quadro cada.

    Parameters
    ----------
    port : Ps2Port
        Barramento e linhas do mouse.
    values : tuple[int, ...]
        Bytes enviados.
    """
    for value in values:
        await device_send(port, port.lines, frame_bits(value))


async def expect_command(
    dut: Ps2CableTbDut,
    lines: Ps2Lines,
    want: int,
    *,
    inhibited: bool = False,
) -> None:
    """Receba um comando do hospedeiro e confira byte e quadro.

    Parameters
    ----------
    dut : Ps2CableTbDut
        Testbench exercitado.
    lines : Ps2Lines
        Linhas do mouse simulado.
    want : int
        Byte esperado.
    inhibited : bool
        Espera ver o clock inibido antes do bit de início.
    """
    value, framed_ok = await device_receive(dut, lines, inhibited=inhibited)
    check_equal(value, want)
    check(framed_ok, "paridade ímpar e parada corretas")


async def initialize(dut: Ps2CableTbDut, port: Ps2Port) -> None:
    """Execute a inicialização completa do mouse simulado.

    Parameters
    ----------
    dut : Ps2CableTbDut
        Testbench exercitado.
    port : Ps2Port
        Barramento e linhas do mouse.
    """
    await expect_command(dut, port.lines, CMD_RESET)
    await reply(port, (RSP_ACK, RSP_SELF_TEST, RSP_ID))
    await expect_command(dut, port.lines, CMD_ENABLE)
    await reply(port, (RSP_ACK,))
    await bus.cycles(port, SETTLE)


async def open_mouse(dut: Ps2CableTbDut) -> Ps2Port:
    """Solte as linhas e reinicie o mouse.

    Parameters
    ----------
    dut : Ps2CableTbDut
        Testbench exercitado.

    Returns
    -------
    Ps2Port
        Barramento e linhas do mouse.
    """
    mouse = await setup_port(dut, "ms")
    await bus.reset(mouse)
    return mouse


async def start(dut: Ps2CableTbDut) -> Ps2Port:
    """Reinicie o cabo e leve o mouse ao modo streaming.

    Parameters
    ----------
    dut : Ps2CableTbDut
        Testbench exercitado.

    Returns
    -------
    Ps2Port
        Barramento e linhas do mouse.
    """
    mouse = await open_mouse(dut)
    await initialize(dut, mouse)
    return mouse


async def send_packet(
    port: Ps2Port, dx: int, dy: int, buttons: int = 0, overflow: int = 0
) -> None:
    """Envie um pacote de movimento de três bytes.

    Parameters
    ----------
    port : Ps2Port
        Barramento e linhas do mouse.
    dx : int
        Deslocamento X com sinal, de -256 a 255.
    dy : int
        Deslocamento Y com sinal, de -256 a 255.
    buttons : int
        Bit 0 esquerdo, bit 1 direito, bit 2 meio.
    overflow : int
        Bit 0 estouro em X, bit 1 estouro em Y.
    """
    first = FIRST_BYTE_BASE | buttons
    first |= ((dx >> 8) & 1) << 4
    first |= ((dy >> 8) & 1) << 5
    first |= (overflow & 3) << 6
    await reply(port, (first, dx & 0xFF, dy & 0xFF))
    await bus.cycles(port, SETTLE)


@cocotb.test()
async def test_init_sequence(dut: Ps2CableTbDut) -> None:
    """O mouse reinicia, troca as respostas e entra em streaming."""
    mouse = await open_mouse(dut)
    check(await bus.read(mouse, STATUS) & STREAMING == 0)
    await expect_command(dut, mouse.lines, CMD_RESET)
    await reply(mouse, (RSP_ACK, RSP_SELF_TEST, RSP_ID))
    await expect_command(dut, mouse.lines, CMD_ENABLE)
    check(await bus.read(mouse, STATUS) & STREAMING == 0)
    await reply(mouse, (RSP_ACK,))
    await bus.cycles(mouse, SETTLE)
    check(await bus.read(mouse, STATUS) & STREAMING != 0)


@cocotb.test()
async def test_bad_response_restarts(dut: Ps2CableTbDut) -> None:
    """Uma resposta errada ao reset o envia de novo, com erro."""
    mouse = await open_mouse(dut)
    await expect_command(dut, mouse.lines, CMD_RESET)
    await reply(mouse, (0xFE,))
    await bus.cycles(mouse, SETTLE)
    check(await bus.read(mouse, STATUS) & ERROR != 0)
    await initialize(dut, mouse)
    check(await bus.read(mouse, STATUS) & STREAMING != 0)


@cocotb.test()
async def test_init_timeout(dut: Ps2CableTbDut) -> None:
    """O silêncio durante a inicialização envia o reset de novo."""
    mouse = await open_mouse(dut)
    await expect_command(dut, mouse.lines, CMD_RESET)
    await expect_command(dut, mouse.lines, CMD_RESET, inhibited=True)
    check(await bus.read(mouse, STATUS) & ERROR != 0)


@cocotb.test()
async def test_packet_registers(dut: Ps2CableTbDut) -> None:
    """Um pacote aparece em DX, DY, BUTTONS e STATUS."""
    mouse = await start(dut)
    await send_packet(mouse, 5, -3, buttons=0b101)
    status = await bus.read(mouse, STATUS)
    check(status & NEW != 0)
    check(status & (OVERFLOW | ERROR) == 0, hex(status))
    check_equal(await bus.read(mouse, BUTTONS), 0b101)
    check_equal(signed16(await bus.read(mouse, DX)), 5)
    check_equal(signed16(await bus.read(mouse, DY)), -3)


@cocotb.test()
async def test_read_clears_accumulators(dut: Ps2CableTbDut) -> None:
    """Ler DX e DY os zera, e os botões mantêm o nível."""
    mouse = await start(dut)
    await send_packet(mouse, 7, 9, buttons=1)
    check_equal(await bus.read(mouse, DX), 7)
    check(await bus.read(mouse, DX) == 0)
    check_equal(await bus.read(mouse, DY), 9)
    check(await bus.read(mouse, DY) == 0)
    check(await bus.read(mouse, BUTTONS) == 1)


@cocotb.test()
async def test_accumulation_and_sign(dut: Ps2CableTbDut) -> None:
    """Os pacotes se somam, com o nono bit como sinal."""
    mouse = await start(dut)
    for dx, dy in ((100, -200), (-256, 255), (255, -256), (-1, 1)):
        await send_packet(mouse, dx, dy)
    check(signed16(await bus.read(mouse, DX)) == 100 - 256 + 255 - 1)
    check(signed16(await bus.read(mouse, DY)) == -200 + 255 - 256 + 1)


@cocotb.test()
async def test_axis_overflow_bits(dut: Ps2CableTbDut) -> None:
    """Os bits de estouro do pacote limitam o eixo e marcam OVERFLOW."""
    mouse = await start(dut)
    await send_packet(mouse, 10, 20, overflow=0b01)
    check(await bus.read(mouse, STATUS) & OVERFLOW != 0)
    check_equal(signed16(await bus.read(mouse, DX)), 255)
    check_equal(signed16(await bus.read(mouse, DY)), 20)
    await send_packet(mouse, -10, -20, overflow=0b10)
    check_equal(signed16(await bus.read(mouse, DX)), -10)
    check_equal(signed16(await bus.read(mouse, DY)), -256)


@cocotb.test()
async def test_resynchronization(dut: Ps2CableTbDut) -> None:
    """Um primeiro byte com o bit 3 zerado é descartado e marca erro."""
    mouse = await start(dut)
    await reply(mouse, (BAD_FIRST_BYTE, 0x41))
    await bus.cycles(mouse, SETTLE)
    status = await bus.read(mouse, STATUS)
    check(status & ERROR != 0)
    check(status & NEW == 0)
    await send_packet(mouse, 4, 6)
    check_equal(await bus.read(mouse, DX), 4)
    check_equal(await bus.read(mouse, DY), 6)
    check(await bus.read(mouse, STATUS) & ERROR == 0)


@cocotb.test()
async def test_frame_error_discards_packet(dut: Ps2CableTbDut) -> None:
    """Um erro de paridade no meio de um pacote descarta esse pacote."""
    mouse = await start(dut)
    await reply(mouse, (0x09,))
    await device_send(mouse, mouse.lines, frame_bits(0x11, parity_ok=False))
    await bus.cycles(mouse, SETTLE)
    await send_packet(mouse, 3, 2)
    check(await bus.read(mouse, STATUS) & ERROR != 0)
    check_equal(await bus.read(mouse, DX), 3)
    check_equal(await bus.read(mouse, DY), 2)


@cocotb.test()
async def test_packet_timeout(dut: Ps2CableTbDut) -> None:
    """Um pacote parado entre bytes é descartado após o limite."""
    mouse = await start(dut)
    await reply(mouse, SHORT_PACKET)
    await bus.cycles(mouse, PACKET_TIMEOUT + SETTLE)
    check(await bus.read(mouse, STATUS) & ERROR != 0)
    await send_packet(mouse, 2, 1)
    check_equal(await bus.read(mouse, DX), 2)
    check(await bus.read(mouse, DY) == 1)


@cocotb.test()
async def test_status_flags_clear_on_read(dut: Ps2CableTbDut) -> None:
    """NEW, OVERFLOW e ERROR são limpos pela leitura de STATUS."""
    mouse = await start(dut)
    await send_packet(mouse, 1, 1, overflow=1)
    await reply(mouse, (BAD_FIRST_BYTE,))
    await bus.cycles(mouse, SETTLE)
    check(await bus.read(mouse, STATUS) & 0b111 == NEW | OVERFLOW | ERROR)
    check(await bus.read(mouse, STATUS) & 0b111 == 0)


@cocotb.test()
async def test_interrupt(dut: Ps2CableTbDut) -> None:
    """A interrupção segue o bit de pacote novo quando habilitada."""
    mouse = await start(dut)
    await send_packet(mouse, 1, 1)
    check(int(mouse.o_irq.value) == 0)
    await bus.write(mouse, CONTROL, IRQ_ENABLE)
    check(int(mouse.o_irq.value) == 1)
    check(await bus.read(mouse, CONTROL) == IRQ_ENABLE)
    await bus.read(mouse, STATUS)
    check(int(mouse.o_irq.value) == 0)
    await send_packet(mouse, 1, 1)
    check(int(mouse.o_irq.value) == 1)
    await bus.write(mouse, CONTROL, 0)
    check(int(mouse.o_irq.value) == 0)


@cocotb.test()
async def test_reinitialize(dut: Ps2CableTbDut) -> None:
    """Escrever o bit de reinício refaz a inicialização."""
    mouse = await start(dut)
    await bus.write(mouse, CONTROL, REINIT)
    check(await bus.read(mouse, CONTROL) == 0)
    await initialize(dut, mouse)
    check(await bus.read(mouse, STATUS) & STREAMING != 0)


@cocotb.test()
async def test_reserved_addresses(dut: Ps2CableTbDut) -> None:
    """Endereços fora do mapa leem zero e ignoram a escrita."""
    mouse = await start(dut)
    for address in (5, 6, 7):
        await bus.write(mouse, address, 0xFFFF_FFFF)
        check(await bus.read(mouse, address) == 0)
    check(await bus.read(mouse, CONTROL) == 0)

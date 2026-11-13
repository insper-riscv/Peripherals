"""Mouse PS/2: inicialização, pacotes, registradores e interrupção."""

import cocotb

from tests.python.unittests.PS2.mouse.byte_driver import (
    expect_tx,
    initialize,
    reset_idle,
    send_byte,
    send_packet,
    send_rx_error,
)
from tests.python.unittests.PS2.mouse.registers import (
    ACC_MAX,
    ACC_MIN,
    BUTTONS,
    CMD_RESET,
    CONTROL,
    DX,
    DY,
    ERROR,
    INIT_TIMEOUT,
    IRQ_ENABLE,
    NEW,
    OVERFLOW,
    PACKET_TIMEOUT,
    REINIT,
    STATUS,
    STREAMING,
)
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MouseDut

SETTLE = 4


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


async def start(dut: MouseDut) -> None:
    """Reinicie o projeto e leve o mouse ao modo streaming.

    Parameters
    ----------
    dut : MouseDut
        Projeto sob teste.
    """
    dut.i_rx_data.value = 0
    await reset_idle(dut)
    await initialize(dut)
    await bus.cycles(dut, SETTLE)


async def packet(dut: MouseDut, dx: int, dy: int, **kwargs: int) -> None:
    """Envie um pacote e espere os registradores o mostrarem.

    Parameters
    ----------
    dut : MouseDut
        Projeto sob teste.
    dx : int
        Deslocamento X com sinal.
    dy : int
        Deslocamento Y com sinal.
    **kwargs : int
        Botões e bits de estouro do pacote.
    """
    await send_packet(dut, dx, dy, **kwargs)
    await bus.cycles(dut, SETTLE)


@cocotb.test()
async def test_init_sequence(dut: MouseDut) -> None:
    """O mouse reinicia, troca as respostas e entra em streaming."""
    await reset_idle(dut)
    check(await bus.read(dut, STATUS) & STREAMING == 0)
    await expect_tx(dut, CMD_RESET)
    for value in (0xFA, 0xAA, 0x00):
        await send_byte(dut, value)
    await expect_tx(dut, 0xF4)
    check(await bus.read(dut, STATUS) & STREAMING == 0)
    await send_byte(dut, 0xFA)
    await bus.cycles(dut, 2)
    check(await bus.read(dut, STATUS) & STREAMING != 0)


@cocotb.test()
async def test_no_send_without_ready(dut: MouseDut) -> None:
    """Nenhum byte é pedido enquanto o hospedeiro não está pronto."""
    await reset_idle(dut)
    for _ in range(10):
        check(int(dut.o_tx_valid.value) == 0)
        await bus.cycles(dut, 1)
    await expect_tx(dut, CMD_RESET)


@cocotb.test()
async def test_bad_response_restarts(dut: MouseDut) -> None:
    """Uma resposta errada ao reset o envia de novo, com erro."""
    await reset_idle(dut)
    await expect_tx(dut, CMD_RESET)
    await send_byte(dut, 0xFE)
    await bus.cycles(dut, 2)
    check(await bus.read(dut, STATUS) & ERROR != 0)
    await expect_tx(dut, CMD_RESET)
    await initialize_after_reset(dut)


async def initialize_after_reset(dut: MouseDut) -> None:
    """Termine a troca de respostas depois de o reset já enviado.

    Parameters
    ----------
    dut : MouseDut
        Projeto sob teste.
    """
    for value in (0xFA, 0xAA, 0x00):
        await send_byte(dut, value)
    await expect_tx(dut, 0xF4)
    await send_byte(dut, 0xFA)
    await bus.cycles(dut, 2)
    check(await bus.read(dut, STATUS) & STREAMING != 0)


@cocotb.test()
async def test_init_timeout(dut: MouseDut) -> None:
    """O silêncio durante a inicialização envia o reset de novo."""
    await reset_idle(dut)
    await expect_tx(dut, CMD_RESET)
    await bus.cycles(dut, INIT_TIMEOUT + 10)
    await expect_tx(dut, CMD_RESET)
    check(await bus.read(dut, STATUS) & ERROR != 0)


@cocotb.test()
async def test_packet_registers(dut: MouseDut) -> None:
    """Um pacote aparece em DX, DY, BUTTONS e STATUS."""
    await start(dut)
    await packet(dut, 5, -3, buttons=0b101)
    status = await bus.read(dut, STATUS)
    check(status & NEW != 0)
    check(status & (OVERFLOW | ERROR) == 0, hex(status))
    check_equal(await bus.read(dut, BUTTONS), 0b101)
    check_equal(signed16(await bus.read(dut, DX)), 5)
    check_equal(signed16(await bus.read(dut, DY)), -3)


@cocotb.test()
async def test_read_clears_accumulators(dut: MouseDut) -> None:
    """Ler DX e DY os zera, e os botões mantêm o nível."""
    await start(dut)
    await packet(dut, 7, 9, buttons=1)
    check_equal(await bus.read(dut, DX), 7)
    check(await bus.read(dut, DX) == 0)
    check_equal(await bus.read(dut, DY), 9)
    check(await bus.read(dut, DY) == 0)
    check(await bus.read(dut, BUTTONS) == 1)


@cocotb.test()
async def test_accumulation_and_sign(dut: MouseDut) -> None:
    """Os pacotes se somam, com o nono bit como sinal."""
    await start(dut)
    for dx, dy in ((100, -200), (-256, 255), (255, -256), (-1, 1)):
        await packet(dut, dx, dy)
    check(signed16(await bus.read(dut, DX)) == 100 - 256 + 255 - 1)
    check(signed16(await bus.read(dut, DY)) == -200 + 255 - 256 + 1)


@cocotb.test()
async def test_saturation(dut: MouseDut) -> None:
    """Os acumuladores param nos limites de 16 bits e marcam estouro."""
    await start(dut)
    for _ in range(ACC_MAX // 255 + 2):
        await packet(dut, 255, -256)
    check(await bus.read(dut, STATUS) & OVERFLOW != 0)
    check(signed16(await bus.read(dut, DX)) == ACC_MAX)
    check(signed16(await bus.read(dut, DY)) == ACC_MIN)
    await packet(dut, 1, 1)
    check(signed16(await bus.read(dut, DX)) == 1)
    check(await bus.read(dut, STATUS) & OVERFLOW == 0)


@cocotb.test()
async def test_axis_overflow_bits(dut: MouseDut) -> None:
    """Os bits de estouro do pacote cortam o eixo e marcam estouro."""
    await start(dut)
    await packet(dut, 10, 20, overflow=0b01)
    check(await bus.read(dut, STATUS) & OVERFLOW != 0)
    check_equal(signed16(await bus.read(dut, DX)), 255)
    check_equal(signed16(await bus.read(dut, DY)), 20)
    await packet(dut, -10, -20, overflow=0b10)
    check_equal(signed16(await bus.read(dut, DX)), -10)
    check_equal(signed16(await bus.read(dut, DY)), -256)


@cocotb.test()
async def test_resynchronization(dut: MouseDut) -> None:
    """Um primeiro byte com o bit 3 zerado é descartado e marca erro."""
    await start(dut)
    await send_byte(dut, 0x00)
    await send_byte(dut, 0x41)
    await bus.cycles(dut, SETTLE)
    status = await bus.read(dut, STATUS)
    check(status & ERROR != 0)
    check(status & NEW == 0)
    await packet(dut, 4, 6)
    check_equal(await bus.read(dut, DX), 4)
    check_equal(await bus.read(dut, DY), 6)
    check(await bus.read(dut, STATUS) & ERROR == 0)


@cocotb.test()
async def test_frame_error_discards_packet(dut: MouseDut) -> None:
    """Um erro de quadro no meio de um pacote descarta esse pacote."""
    await start(dut)
    await send_byte(dut, 0x09)
    await send_rx_error(dut)
    await bus.cycles(dut, SETTLE)
    await packet(dut, 3, 2)
    check(await bus.read(dut, STATUS) & ERROR != 0)
    check_equal(await bus.read(dut, DX), 3)
    check_equal(await bus.read(dut, DY), 2)


@cocotb.test()
async def test_packet_timeout(dut: MouseDut) -> None:
    """Um pacote parado entre bytes é descartado após o limite."""
    await start(dut)
    await send_byte(dut, 0x09)
    await send_byte(dut, 0x11)
    await bus.cycles(dut, PACKET_TIMEOUT + 10)
    check(await bus.read(dut, STATUS) & ERROR != 0)
    await packet(dut, 2, 1)
    check_equal(await bus.read(dut, DX), 2)
    check(await bus.read(dut, DY) == 1)


@cocotb.test()
async def test_status_flags_clear_on_read(dut: MouseDut) -> None:
    """NEW, OVERFLOW e ERROR são limpos pela leitura de STATUS."""
    await start(dut)
    await packet(dut, 1, 1, overflow=1)
    await send_byte(dut, 0x00)
    await bus.cycles(dut, SETTLE)
    check(await bus.read(dut, STATUS) & 0b111 == NEW | OVERFLOW | ERROR)
    check(await bus.read(dut, STATUS) & 0b111 == 0)


@cocotb.test()
async def test_interrupt(dut: MouseDut) -> None:
    """A interrupção segue o bit de pacote novo quando habilitada."""
    await start(dut)
    await packet(dut, 1, 1)
    check(int(dut.o_irq.value) == 0)
    await bus.write(dut, CONTROL, IRQ_ENABLE)
    check(int(dut.o_irq.value) == 1)
    check(await bus.read(dut, CONTROL) == IRQ_ENABLE)
    await bus.read(dut, STATUS)
    check(int(dut.o_irq.value) == 0)
    await packet(dut, 1, 1)
    check(int(dut.o_irq.value) == 1)
    await bus.write(dut, CONTROL, 0)
    check(int(dut.o_irq.value) == 0)


@cocotb.test()
async def test_reinitialize(dut: MouseDut) -> None:
    """Escrever o bit de reinício refaz a inicialização."""
    await start(dut)
    await bus.write(dut, CONTROL, REINIT)
    check(await bus.read(dut, CONTROL) == 0)
    await expect_tx(dut, CMD_RESET)
    check(await bus.read(dut, STATUS) & STREAMING == 0)
    await initialize_after_reset(dut)


@cocotb.test()
async def test_reserved_addresses(dut: MouseDut) -> None:
    """Endereços fora do mapa leem zero e ignoram a escrita."""
    await start(dut)
    for address in (5, 6, 7):
        await bus.write(dut, address, 0xFFFF_FFFF)
        check(await bus.read(dut, address) == 0)
    check(await bus.read(dut, CONTROL) == 0)

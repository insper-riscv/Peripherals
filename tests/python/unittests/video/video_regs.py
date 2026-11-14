"""Registradores do vídeo: decodificação, contador e escritas."""

import cocotb
from cocotb.triggers import Timer

from tests.python.unittests.video.bus import drive
from tests.python.unittests.video.registers import (
    CTRL,
    FORMAT,
    FRAME_COUNT,
    GEOMETRY,
    INDEXED_FLAG,
    MASK32,
    PALETTE,
    STATUS,
    STATUS_VBLANK,
    STATUS_VSYNC,
    storage_bits,
)
from tests.python.unittests.video.signals import RegsDut
from tests.python.utils.bus import cycles, hold_reset
from tests.python.utils.check import check

FULL = 0xF


def eq(actual: int, expected: int, message: str) -> None:
    """Falha o teste se dois valores diferem.

    Parameters
    ----------
    actual : int
        Valor observado.
    expected : int
        Valor esperado.
    message : str
        Texto da falha.
    """
    check(actual == expected, f"{message}: {actual:#x} != {expected:#x}")


async def start(dut: RegsDut) -> None:
    """Inicia o clock, aplica o reset e solta.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    """
    drive(
        dut,
        i_write=0,
        i_address=0,
        i_data_in=0,
        i_byteena=FULL,
        i_vsync=0,
        i_vblank=0,
    )
    await hold_reset(dut)


async def write(
    dut: RegsDut, address: int, data: int, mask: int = FULL
) -> None:
    """Pulso de escrita de um ciclo.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    address : int
        Endereço de palavra.
    data : int
        Dado de escrita.
    mask : int
        Habilitação de bytes.
    """
    drive(dut, i_address=address, i_data_in=data, i_byteena=mask, i_write=1)
    await cycles(dut, 1)
    dut.i_write.value = 0


async def read(dut: RegsDut, address: int) -> int:
    """Leitura combinacional do endereço.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.
    address : int
        Endereço de palavra.

    Returns
    -------
    int
        O dado lido.
    """
    dut.i_address.value = address
    await Timer(1, unit="ns")
    return int(dut.o_data_out.value)


def window(dut: RegsDut) -> int:
    """Endereço de palavra do início da janela do framebuffer.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.

    Returns
    -------
    int
        O início da janela.
    """
    return 1 << (len(dut.i_address) - 1)


async def fb_depth(dut: RegsDut) -> int:
    """Palavras do framebuffer, deduzidas da geometria e do formato.

    Parameters
    ----------
    dut : RegsDut
        Registradores sob teste.

    Returns
    -------
    int
        O número de palavras.
    """
    geometry = await read(dut, GEOMETRY)
    bits = (await read(dut, FORMAT)) & 0xFF
    return (geometry & 0xFFFF) * (geometry >> 16) * bits // 32


@cocotb.test()
async def test_reset_and_info(dut: RegsDut) -> None:
    """Valores de reset e registradores de geometria e formato."""
    await start(dut)
    eq(int(dut.o_enable.value), 0, "exibição")
    eq(int(dut.o_fb_we.value), 0, "faixas")
    eq(int(dut.o_pal_we.value), 0, "paleta")
    for address in (CTRL, STATUS, FRAME_COUNT):
        eq(await read(dut, address), 0, f"registrador {address}")
    geometry = await read(dut, GEOMETRY)
    fmt = await read(dut, FORMAT)
    check(geometry >> 16 > 0 and geometry & 0xFFFF > 0, "geometria")
    bits = int(dut.channel_bits.value)
    check((fmt & 0xFF) in (8, 16, 32) and (fmt >> 8) & 0xFF > 0, "formato")
    eq((fmt >> 16) & 0xFF, bits, "bits por canal")
    indexed = bool(fmt & INDEXED_FLAG)
    eq(fmt & 0xFF, storage_bits(indexed, bits), "pixel")
    for address in (5, 100, 255, 300, 511, 512, 1023):
        eq(await read(dut, address), 0, f"lacuna {address}")


@cocotb.test()
async def test_control_and_status(dut: RegsDut) -> None:
    """O controle respeita a máscara; o estado reflete as entradas."""
    await start(dut)
    await write(dut, CTRL, MASK32, 0b1110)
    eq(int(dut.o_enable.value), 0, "sem o byte 0")
    await write(dut, CTRL, 1)
    eq(int(dut.o_enable.value), 1, "liga")
    eq(await read(dut, CTRL), 1, "leitura do controle")
    await write(dut, CTRL, 0xFFFFFFFE)
    eq(int(dut.o_enable.value), 0, "desliga")
    for vsync in (0, 1):
        for vblank in (0, 1):
            dut.i_vsync.value = vsync
            dut.i_vblank.value = vblank
            expected = STATUS_VSYNC * vsync + STATUS_VBLANK * vblank
            eq(await read(dut, STATUS), expected, "estado")
    for address in (STATUS, FRAME_COUNT, GEOMETRY, FORMAT):
        before = await read(dut, address)
        await write(dut, address, MASK32)
        eq(await read(dut, address), before, "registrador só de leitura")


@cocotb.test()
async def test_frame_counter(dut: RegsDut) -> None:
    """O contador conta bordas de subida do apagamento, não o nível."""
    await start(dut)
    for expected in range(1, 5):
        dut.i_vblank.value = 1
        await cycles(dut, 4)
        eq(await read(dut, FRAME_COUNT), expected, "contador")
        dut.i_vsync.value = expected & 1
        dut.i_vblank.value = 0
        await cycles(dut, 3)
        eq(await read(dut, FRAME_COUNT), expected, "nível não conta")
    await start(dut)
    eq(await read(dut, FRAME_COUNT), 0, "reset zera o contador")


@cocotb.test()
async def test_framebuffer_write(dut: RegsDut) -> None:
    """A escrita sai registrada, copia a máscara e respeita a faixa."""
    await start(dut)
    base = window(dut)
    cases = [(0, 0xCAFEBABE, 0b0101), (7, 0x12345678, FULL), (3, 5, 0b1000)]
    for index, data, mask in cases:
        await write(dut, base + index, data, mask)
        eq(int(dut.o_fb_we.value), mask, "faixas um ciclo depois")
        eq(int(dut.o_fb_addr.value), index, "endereço")
        eq(int(dut.o_wdata.value), data, "dado")
        await cycles(dut, 1)
        eq(int(dut.o_fb_we.value), 0, "a escrita dura um ciclo")
    last = base - 1
    for index in (await fb_depth(dut), last):
        await write(dut, base + index, MASK32)
        eq(int(dut.o_fb_we.value), 0, f"fora da faixa {index}")
    await write(dut, CTRL, MASK32)
    eq(int(dut.o_fb_we.value), 0, "registrador não grava o framebuffer")


@cocotb.test()
async def test_palette_write(dut: RegsDut) -> None:
    """A paleta só grava no formato indexado e com as faixas da cor."""
    await start(dut)
    has_palette = bool((await read(dut, FORMAT)) & INDEXED_FLAG)
    need = (1 << ((3 * int(dut.channel_bits.value) + 7) // 8)) - 1
    cases = (
        (0, FULL, 1),
        (255, need, 1),
        (9, need >> 1, 0),
        (10, 0b1000 | need >> 1, 0),
    )
    for index, mask, hit in cases:
        await write(dut, PALETTE + index, 0xABCDEF, mask)
        expected = hit if has_palette else 0
        eq(int(dut.o_pal_we.value), expected, f"paleta {index}")
        if expected:
            eq(int(dut.o_pal_addr.value), index, "índice")
            eq(int(dut.o_wdata.value) & 0xFFFFFF, 0xABCDEF, "cor")
    await write(dut, PALETTE - 1, MASK32)
    eq(int(dut.o_pal_we.value), 0, "fora da paleta")

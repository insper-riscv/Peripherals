"""Captura: quadro, recorte, passo de linhas, filtro e abortos."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.MIPI.probe import launch
from tests.python.unittests.MIPI.registers import DT_EMBEDDED, DT_RAW8
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MipiCaptureDut

LINE_BYTES = 8
LINES = 3


class Probe:
    """Coleta a memória escrita e os eventos a cada ciclo."""

    def __init__(self) -> None:
        """Zere a memória e os contadores."""
        self.memory: dict[int, int] = {}
        self.crc = 0
        self.drops = 0
        self.dones: list[tuple[int, int, int]] = []

    async def run(self, dut: MipiCaptureDut) -> None:
        """Amostre as saídas depois de cada borda de subida.

        Parameters
        ----------
        dut : MipiCaptureDut
            Projeto sob teste.
        """
        while True:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            self.crc += int(dut.o_ev_crc.value)
            self.drops += int(dut.o_ev_drop.value)
            enable = int(dut.o_we.value)
            word = int(dut.o_waddr.value)
            data = int(dut.o_wdata.value)
            for byte in range(4):
                if enable >> byte & 1:
                    self.memory[word * 4 + byte] = data >> (8 * byte) & 0xFF
            if int(dut.o_done.value):
                self.dones.append(
                    (
                        int(dut.o_ok.value),
                        int(dut.o_lines.value),
                        int(dut.o_last_wc.value),
                    )
                )

    def image(self) -> list[list[int | None]]:
        """Devolva a memória escrita como linhas de bytes.

        Returns
        -------
        list[list[int | None]]
            Cada linha com None onde nada foi escrito.
        """
        return [
            [self.memory.get(row * LINE_BYTES + x) for x in range(LINE_BYTES)]
            for row in range(LINES)
        ]


async def start(dut: MipiCaptureDut, y_step: int = 1) -> Probe:
    """Reinicie o projeto, configure o filtro e comece a coletar.

    Parameters
    ----------
    dut : MipiCaptureDut
        Projeto sob teste.
    y_step : int
        Passo de linhas.

    Returns
    -------
    Probe
        O coletor de eventos.
    """
    bus.set_inputs(dut, i_dt=DT_RAW8, i_y_step=y_step, i_crc_ok=1)
    bus.set_inputs(dut, i_start=0, i_hdr_valid=0, i_hdr_long=0, i_hdr_dt=0)
    bus.set_inputs(dut, i_hdr_wc=0, i_pix_valid=0, i_pix_data=0)
    bus.set_inputs(dut, i_pix_mask=0, i_pkt_end=0)
    probe = Probe()
    await launch(dut, probe)
    return probe


async def header(dut: MipiCaptureDut, long: int, dt: int, wc: int = 0) -> None:
    """Entregue um cabeçalho válido por um ciclo.

    Parameters
    ----------
    dut : MipiCaptureDut
        Projeto sob teste.
    long : int
        Pacote longo.
    dt : int
        Tipo de dado.
    wc : int
        Contagem de palavras.
    """
    bus.set_inputs(dut, i_hdr_valid=1, i_hdr_long=long, i_hdr_dt=dt)
    bus.set_inputs(dut, i_hdr_wc=wc)
    await bus.cycles(dut, 1)
    dut.i_hdr_valid.value = 0
    await bus.cycles(dut, 1)


async def line(
    dut: MipiCaptureDut,
    payload: bytes,
    dt: int = DT_RAW8,
    crc_ok: int = 1,
) -> None:
    """Entregue um pacote de linha inteiro, em grupos de duas lanes.

    Parameters
    ----------
    dut : MipiCaptureDut
        Projeto sob teste.
    payload : bytes
        Bytes da linha.
    dt : int
        Tipo de dado.
    crc_ok : int
        Resultado do CRC do pacote.
    """
    await header(dut, 1, dt, len(payload))
    for index in range(0, len(payload), 2):
        group = payload[index:][:2]
        dut.i_pix_valid.value = 1
        dut.i_pix_data.value = int.from_bytes(group.ljust(2, b"\0"), "little")
        dut.i_pix_mask.value = (1 << len(group)) - 1
        await bus.cycles(dut, 1)
        dut.i_pix_valid.value = 0
        await bus.cycles(dut, 1)
    dut.i_pkt_end.value = 1
    dut.i_crc_ok.value = crc_ok
    await bus.cycles(dut, 1)
    dut.i_pkt_end.value = 0
    dut.i_crc_ok.value = 1
    await bus.cycles(dut, 1)


async def request(dut: MipiCaptureDut) -> None:
    """Peça uma captura.

    Parameters
    ----------
    dut : MipiCaptureDut
        Projeto sob teste.
    """
    dut.i_start.value = 1
    await bus.cycles(dut, 1)
    dut.i_start.value = 0
    await bus.cycles(dut, 1)


def row(base: int, size: int = LINE_BYTES) -> bytes:
    """Gere os bytes de uma linha de teste.

    Parameters
    ----------
    base : int
        Valor do primeiro byte.
    size : int
        Quantidade de bytes.

    Returns
    -------
    bytes
        Os bytes, crescentes a partir de base.
    """
    return bytes((base + index) & 0xFF for index in range(size))


@cocotb.test()
async def test_full_frame(dut: MipiCaptureDut) -> None:
    """Um quadro de três linhas fica inteiro na memória e termina ok."""
    probe = await start(dut)
    await request(dut)
    check_equal(int(dut.o_busy.value), 1)
    await header(dut, 0, 0x00, 1)
    for index in range(LINES):
        await line(dut, row(16 * index))
    await header(dut, 0, 0x01, 1)
    check(probe.image() == [list(row(16 * i)) for i in range(LINES)])
    check(probe.dones == [(1, LINES, LINE_BYTES)], f"{probe.dones}")
    check_equal(int(dut.o_busy.value), 0)
    check_equal(probe.drops, 0)


@cocotb.test()
async def test_crop_and_extra_lines(dut: MipiCaptureDut) -> None:
    """Bytes além da linha e linhas além do quadro são descartados."""
    probe = await start(dut)
    await request(dut)
    await header(dut, 0, 0x00)
    for index in range(LINES + 2):
        await line(dut, row(16 * index, 12))
    await header(dut, 0, 0x01)
    check(probe.image() == [list(row(16 * i, 8)) for i in range(LINES)])
    check(probe.dones == [(1, LINES, 12)], f"{probe.dones}")
    check_equal(probe.drops, LINES + 2)


@cocotb.test()
async def test_line_step(dut: MipiCaptureDut) -> None:
    """Com passo 2, só as linhas de índice par entram na memória."""
    probe = await start(dut, y_step=2)
    await request(dut)
    await header(dut, 0, 0x00)
    for index in range(5):
        await line(dut, row(16 * index))
    await header(dut, 0, 0x01)
    want = [list(row(16 * i)) for i in (0, 2, 4)]
    check(probe.image() == want, f"{probe.image()}")
    check(probe.dones == [(1, 3, LINE_BYTES)], f"{probe.dones}")


@cocotb.test()
async def test_other_types_ignored(dut: MipiCaptureDut) -> None:
    """Linhas de outro tipo e pacotes curtos de linha são ignorados."""
    probe = await start(dut)
    await request(dut)
    await header(dut, 0, 0x00)
    await header(dut, 0, 0x02, 5)
    await line(dut, row(0x40), DT_EMBEDDED)
    await line(dut, row(0x10))
    await header(dut, 0, 0x03, 5)
    await header(dut, 0, 0x01)
    check(probe.image()[0] == list(row(0x10)), f"{probe.image()}")
    check_equal(probe.dones[0][1], 1)


@cocotb.test()
async def test_crc_error_event(dut: MipiCaptureDut) -> None:
    """Uma linha com CRC errado gera o evento e ainda é guardada."""
    probe = await start(dut)
    await request(dut)
    await header(dut, 0, 0x00)
    await line(dut, row(0x20), crc_ok=0)
    await header(dut, 0, 0x01)
    check_equal(probe.crc, 1)
    check(probe.image()[0] == list(row(0x20)))
    check_equal(probe.dones[0][0], 1)


@cocotb.test()
async def test_odd_length_line(dut: MipiCaptureDut) -> None:
    """Uma linha de bytes ímpares grava só os bytes que existem."""
    probe = await start(dut)
    await request(dut)
    await header(dut, 0, 0x00)
    await line(dut, row(0x30, 7))
    await header(dut, 0, 0x01)
    check(probe.image()[0] == [*row(0x30, 7), None], f"{probe.image()}")
    check_equal(probe.dones[0][2], 7)


@cocotb.test()
async def test_waits_for_frame_start(dut: MipiCaptureDut) -> None:
    """Sem pedido nada é guardado, e com pedido espera o início."""
    probe = await start(dut)
    await header(dut, 0, 0x00)
    await line(dut, row(1))
    await header(dut, 0, 0x01)
    check_equal(len(probe.memory), 0)
    check_equal(len(probe.dones), 0)
    await request(dut)
    await line(dut, row(2))
    await header(dut, 0, 0x01)
    check_equal(len(probe.memory), 0)
    check_equal(int(dut.o_busy.value), 1)
    await request(dut)
    check_equal(int(dut.o_busy.value), 1)


@cocotb.test()
async def test_aborts(dut: MipiCaptureDut) -> None:
    """Início no meio do quadro, ou quadro vazio, termina sem ok."""
    probe = await start(dut)
    await request(dut)
    await header(dut, 0, 0x00)
    await line(dut, row(0x50))
    await header(dut, 0, 0x00)
    check(probe.dones == [(0, 1, LINE_BYTES)], f"{probe.dones}")
    await request(dut)
    await header(dut, 0, 0x00)
    await header(dut, 0, 0x01)
    check(probe.dones[-1][0] == 0 and probe.dones[-1][1] == 0)
    check_equal(len(probe.dones), 2)

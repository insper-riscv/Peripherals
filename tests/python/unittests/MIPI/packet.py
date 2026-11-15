"""Camada de pacotes: grupos de lanes, ECC, CRC e tipos de pacote."""

import cocotb
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.MIPI import csi2
from tests.python.unittests.MIPI.probe import launch
from tests.python.utils import bus
from tests.python.utils.check import check, check_equal
from tests.python.utils.dut import MipiPacketDut

BYTE_PERIOD = 4
CRC_CHECK_VALUE = 0x6F91
SETTLE = 12


class Probe:
    """Coleta os eventos da camada de pacotes a cada ciclo."""

    def __init__(self) -> None:
        """Zere as listas de eventos."""
        self.headers: list[tuple[int, int, int]] = []
        self.bad = 0
        self.pixels: list[int] = []
        self.groups: list[int] = []
        self.ends: list[int] = []
        self.arm_low = 0

    async def run(self, dut: MipiPacketDut) -> None:
        """Amostre as saídas depois de cada borda de subida.

        Parameters
        ----------
        dut : MipiPacketDut
            Projeto sob teste.
        """
        lanes = len(dut.i_lane_valid)
        while True:
            await RisingEdge(dut.i_clk)
            await Timer(1, unit="ns")
            self.arm_low += 1 - int(dut.o_arm.value)
            self.bad += int(dut.o_hdr_bad.value)
            if int(dut.o_hdr_valid.value):
                self.headers.append(
                    (
                        int(dut.o_hdr_long.value),
                        int(dut.o_hdr_dt.value),
                        int(dut.o_hdr_wc.value),
                    )
                )
            if int(dut.o_pix_valid.value):
                mask = int(dut.o_pix_mask.value)
                data = int(dut.o_pix_data.value)
                self.groups.append(mask)
                self.pixels += [
                    data >> (8 * lane) & 0xFF
                    for lane in range(lanes)
                    if mask >> lane & 1
                ]
            if int(dut.o_pkt_end.value):
                self.ends.append(int(dut.o_crc_ok.value))


async def start(dut: MipiPacketDut) -> Probe:
    """Reinicie o projeto e comece a coletar eventos.

    Parameters
    ----------
    dut : MipiPacketDut
        Projeto sob teste.

    Returns
    -------
    Probe
        O coletor de eventos.
    """
    dut.i_lane_locked.value = 0
    dut.i_lane_valid.value = 0
    dut.i_lane_data.value = 0
    probe = Probe()
    await launch(dut, probe)
    return probe


async def send(
    dut: MipiPacketDut, packet: bytes, skew: tuple[int, ...] = ()
) -> None:
    """Envie um pacote como bytes de lane, com as lanes já alinhadas.

    Parameters
    ----------
    dut : MipiPacketDut
        Projeto sob teste.
    packet : bytes
        Bytes do pacote.
    skew : tuple[int, ...]
        Atraso em ciclos de cada lane.
    """
    lanes = len(dut.i_lane_valid)
    delays = skew or (0,) * lanes
    streams = csi2.distribute(packet, lanes)
    length = max(len(s) for s in streams) * BYTE_PERIOD + max(delays) + 2
    dut.i_lane_locked.value = (1 << lanes) - 1
    await bus.cycles(dut, 2)
    for cycle in range(length):
        valid = 0
        data = 0
        for lane, stream in enumerate(streams):
            rel = cycle - delays[lane]
            if rel >= 0 and rel % BYTE_PERIOD == 0:
                index = rel // BYTE_PERIOD
                if index < len(stream):
                    valid |= 1 << lane
                    data |= stream[index] << (8 * lane)
        dut.i_lane_valid.value = valid
        dut.i_lane_data.value = data
        await bus.cycles(dut, 1)
        if not int(dut.o_arm.value):
            # As lanes se destravam e param de entregar bytes.
            break
    dut.i_lane_valid.value = 0
    await bus.cycles(dut, SETTLE)
    dut.i_lane_locked.value = 0
    await bus.cycles(dut, 4)


@cocotb.test()
async def test_short_packets(dut: MipiPacketDut) -> None:
    """Início e fim de quadro saem como pacotes curtos."""
    probe = await start(dut)
    await send(dut, csi2.short_packet(0x00, 7))
    await send(dut, csi2.short_packet(0x01, 7))
    check(probe.headers == [(0, 0, 7), (0, 1, 7)], f"{probe.headers}")
    check(probe.ends == [1, 1], f"{probe.ends}")
    check_equal(len(probe.pixels), 0)
    check_equal(probe.bad, 0)


@cocotb.test()
async def test_long_packet_lengths(dut: MipiPacketDut) -> None:
    """Cargas úteis de qualquer tamanho saem inteiras, com CRC."""
    probe = await start(dut)
    for size in (0, 1, 2, 3, 4, 5, 7, 8, 9, 16, 33):
        payload = bytes((index * 37 + size) & 0xFF for index in range(size))
        probe.pixels.clear()
        probe.ends.clear()
        await send(dut, csi2.long_packet(0x2A, payload))
        check(list(payload) == probe.pixels, f"tamanho {size}: {probe.pixels}")
        check(probe.ends == [1], f"tamanho {size}: CRC {probe.ends}")
    check(probe.headers[-1] == (1, 0x2A, 33), f"{probe.headers[-1]}")


@cocotb.test()
async def test_crc_error(dut: MipiPacketDut) -> None:
    """Um CRC errado entrega a carga útil e marca o fim com CRC ruim."""
    probe = await start(dut)
    payload = bytes(range(10))
    await send(dut, csi2.long_packet(0x2A, payload, bad_crc=1))
    check(list(payload) == probe.pixels, f"{probe.pixels}")
    check(probe.ends == [0], f"{probe.ends}")
    await send(dut, csi2.long_packet(0x2A, payload))
    check(probe.ends == [0, 1], f"{probe.ends}")


@cocotb.test()
async def test_ecc_error_drops_packet(dut: MipiPacketDut) -> None:
    """Um ECC errado derruba o pacote e o seguinte é recebido."""
    probe = await start(dut)
    good = csi2.long_packet(0x2A, bytes(range(8)))
    broken = bytes([good[0], good[1], good[2], good[3] ^ 0x01]) + good[4:]
    await send(dut, broken)
    check_equal(probe.bad, 1)
    check_equal(len(probe.headers), 0)
    check_equal(len(probe.pixels), 0)
    await send(dut, good)
    check_equal(len(probe.headers), 1)
    check(probe.pixels == list(range(8)), f"{probe.pixels}")


@cocotb.test()
async def test_ecc_reference_vector(dut: MipiPacketDut) -> None:
    """O cabeçalho 21 00 00 12 de um vetor de referência é aceito."""
    check_equal(csi2.crc16(b"123456789"), CRC_CHECK_VALUE)
    check_equal(csi2.ecc(0x000021), 0x12)
    probe = await start(dut)
    await send(dut, bytes([0x21, 0x00, 0x00, 0x12, 0x00, 0x00]))
    check(probe.headers == [(1, 0x21, 0)], f"{probe.headers}")
    check_equal(probe.bad, 0)


@cocotb.test()
async def test_lane_skew(dut: MipiPacketDut) -> None:
    """Defasagens de até três ciclos entre as lanes são aceitas."""
    probe = await start(dut)
    lanes = len(dut.i_lane_valid)
    payload = bytes(range(1, 14))
    for offset in range(4):
        skew = tuple((lane * offset) % 4 for lane in range(lanes))
        probe.pixels.clear()
        probe.ends.clear()
        await send(dut, csi2.long_packet(0x2A, payload), skew)
        check(list(payload) == probe.pixels, f"defasagem {skew}")
        check(probe.ends == [1], f"defasagem {skew}")


@cocotb.test()
async def test_sync_window(dut: MipiPacketDut) -> None:
    """Se só uma lane trava, a busca recomeça depois de oito ciclos."""
    probe = await start(dut)
    lanes = len(dut.i_lane_valid)
    if lanes == 1:
        return
    dut.i_lane_locked.value = 1
    await bus.cycles(dut, 14)
    check_equal(probe.arm_low, 1)
    dut.i_lane_locked.value = 0
    await bus.cycles(dut, 4)
    await send(dut, csi2.short_packet(0x00, 1))
    check(probe.headers == [(0, 0, 1)], f"{probe.headers}")

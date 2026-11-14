"""Monitor comportamental da saída HDMI: temporização e pixels."""

from dataclasses import dataclass, field
from itertools import pairwise
from typing import NamedTuple, Protocol

from cocotb.handle import LogicArrayObject, LogicObject
from cocotb.triggers import FallingEdge, First
from cocotb.utils import get_sim_time

from tests.python.unittests.video.registers import Axis
from tests.python.utils.check import check

MIN_LINES = 2
MIN_FRAMES = 2


class OutputDut(Protocol):
    """Saídas de vídeo do periférico HDMI."""

    i_pixel_clk: LogicObject
    o_tx_d: LogicArrayObject
    o_tx_clk: LogicObject
    o_tx_de: LogicObject
    o_tx_hs: LogicObject
    o_tx_vs: LogicObject


@dataclass(frozen=True)
class Timing:
    """Temporização de um modo de vídeo.

    Attributes
    ----------
    h : Axis
        Direção horizontal, em pixels.
    v : Axis
        Direção vertical, em linhas.
    """

    h: Axis
    v: Axis

    @property
    def h_visible(self) -> int:
        """Pixels visíveis por linha."""
        return self.h.visible

    @property
    def v_visible(self) -> int:
        """Linhas visíveis por quadro."""
        return self.v.visible

    @property
    def h_front(self) -> int:
        """Pórtico frontal horizontal."""
        return self.h.front

    @property
    def h_back(self) -> int:
        """Pórtico traseiro horizontal."""
        return self.h.back

    @property
    def h_sync(self) -> int:
        """Largura do pulso horizontal."""
        return self.h.sync

    @property
    def v_sync(self) -> int:
        """Largura do pulso vertical em linhas."""
        return self.v.sync

    @property
    def h_positive(self) -> bool:
        """HS em nível alto durante o pulso."""
        return self.h.positive

    @property
    def v_positive(self) -> bool:
        """VS em nível alto durante o pulso."""
        return self.v.positive

    @property
    def h_total(self) -> int:
        """Pixels totais por linha."""
        return self.h.total

    @property
    def v_total(self) -> int:
        """Linhas totais por quadro."""
        return self.v.total

    @property
    def frame_clocks(self) -> int:
        """Ciclos de pixel de um quadro."""
        return self.h_total * self.v_total

    def hs_level(self, column: int) -> int:
        """Nível esperado de HS em uma coluna.

        Parameters
        ----------
        column : int
            Coluna da linha.

        Returns
        -------
        int
            O nível da saída.
        """
        return self.h.level(column)

    def vs_level(self, line: int) -> int:
        """Nível esperado de VS em uma linha.

        Parameters
        ----------
        line : int
            Linha do quadro.

        Returns
        -------
        int
            O nível da saída.
        """
        return self.v.level(line)

    def visible(self, column: int, line: int) -> bool:
        """Indica se uma posição está na área visível (DE alto).

        Parameters
        ----------
        column : int
            Coluna da linha.
        line : int
            Linha do quadro.

        Returns
        -------
        bool
            Verdadeiro dentro da área visível.
        """
        return column < self.h_visible and line < self.v_visible


class Sample(NamedTuple):
    """Uma amostra das saídas em uma borda do clock de pixel."""

    de: int
    hs: int
    vs: int
    data: int


class Event(NamedTuple):
    """Uma mudança de HS, VS ou DE, com o instante em picossegundos."""

    time_ps: float
    hs: int
    vs: int
    de: int


@dataclass
class EdgeLog:
    """Registro das mudanças de HS, VS e DE.

    Attributes
    ----------
    events : list[Event]
        Eventos na ordem em que ocorreram.
    """

    events: list[Event] = field(default_factory=list[Event])


async def log_edges(dut: OutputDut, log: EdgeLog) -> None:
    """Registra cada mudança de HS, VS ou DE até o fim da simulação.

    Parameters
    ----------
    dut : OutputDut
        Periférico sob teste.
    log : EdgeLog
        Registro que recebe os eventos.
    """
    while True:
        await First(
            dut.o_tx_hs.value_change,
            dut.o_tx_vs.value_change,
            dut.o_tx_de.value_change,
        )
        event = Event(
            get_sim_time("ps"),
            int(dut.o_tx_hs.value),
            int(dut.o_tx_vs.value),
            int(dut.o_tx_de.value),
        )
        if log.events and log.events[-1].time_ps == event.time_ps:
            log.events[-1] = event
        else:
            log.events.append(event)


async def sample_clocks(dut: OutputDut, count: int) -> list[Sample]:
    """Amostra as saídas na descida do clock de pixel.

    Parameters
    ----------
    dut : OutputDut
        Periférico sob teste.
    count : int
        Número de amostras.

    Returns
    -------
    list[Sample]
        As amostras, uma por ciclo de pixel.
    """
    samples: list[Sample] = []
    for _ in range(count):
        await FallingEdge(dut.i_pixel_clk)
        samples.append(
            Sample(
                int(dut.o_tx_de.value),
                int(dut.o_tx_hs.value),
                int(dut.o_tx_vs.value),
                int(dut.o_tx_d.value),
            )
        )
    return samples


def _intervals(
    events: list[Event], index: int, level: int
) -> list[tuple[float, float]]:
    """Intervalos em que um sinal vale um nível.

    Parameters
    ----------
    events : list[Event]
        Eventos registrados.
    index : int
        Campo do evento (1 HS, 2 VS, 3 DE).
    level : int
        Nível procurado.

    Returns
    -------
    list[tuple[float, float]]
        Pares de instante inicial e final, só os intervalos completos.
    """
    result: list[tuple[float, float]] = []
    begin: float | None = None
    previous = None
    for event in events:
        value = event[index]
        if value == previous:
            continue
        if value == level:
            begin = event.time_ps
        elif begin is not None:
            result.append((begin, event.time_ps))
            begin = None
        previous = value
    return result


def _clocks(delta_ps: float, period_ps: int) -> int:
    """Transformar uma duração em ciclos de pixel, inteiros.

    Parameters
    ----------
    delta_ps : float
        Duração em picossegundos.
    period_ps : int
        Período do clock de pixel em picossegundos.

    Returns
    -------
    int
        A duração em ciclos de pixel.
    """
    cycles = round(delta_ps / period_ps)
    check(abs(delta_ps - cycles * period_ps) < 1, "duração não inteira")
    return cycles


def _starts_gaps(spans: list[tuple[float, float]], period_ps: int) -> set[int]:
    """Distâncias, em ciclos, entre inícios de intervalos consecutivos.

    Parameters
    ----------
    spans : list[tuple[float, float]]
        Intervalos.
    period_ps : int
        Período do clock de pixel em picossegundos.

    Returns
    -------
    set[int]
        O conjunto das distâncias vistas.
    """
    return {_clocks(b[0] - a[0], period_ps) for a, b in pairwise(spans)}


def check_edges(log: EdgeLog, timing: Timing, period_ps: int) -> None:
    """Mede e confere largura de linha, de quadro, polaridades e DE.

    Parameters
    ----------
    log : EdgeLog
        Eventos registrados, de pelo menos dois quadros.
    timing : Timing
        Temporização esperada.
    period_ps : int
        Período do clock de pixel em picossegundos.
    """
    hs = _intervals(log.events, 1, int(timing.h_positive))
    vs = _intervals(log.events, 2, int(timing.v_positive))
    de = _intervals(log.events, 3, 1)
    check(len(hs) > MIN_LINES and len(vs) >= 1, "poucos pulsos para medir")
    check(
        _starts_gaps(hs, period_ps) == {timing.h_total},
        f"largura de linha medida {_starts_gaps(hs, period_ps)}",
    )
    check(
        {_clocks(e - b, period_ps) for b, e in hs} == {timing.h_sync},
        "largura do pulso de HS",
    )
    check(
        {_clocks(e - b, period_ps) for b, e in vs}
        == {timing.v_sync * timing.h_total},
        "largura do pulso de VS",
    )
    if len(vs) >= MIN_FRAMES:
        check(
            _starts_gaps(vs, period_ps) == {timing.frame_clocks},
            f"largura de quadro medida {_starts_gaps(vs, period_ps)}",
        )
    check(
        {_clocks(e - b, period_ps) for b, e in de} == {timing.h_visible},
        "largura de DE",
    )
    _check_alignment(hs, vs, de, timing, period_ps)


def _check_alignment(
    hs: list[tuple[float, float]],
    vs: list[tuple[float, float]],
    de: list[tuple[float, float]],
    timing: Timing,
    period_ps: int,
) -> None:
    """Confere pórticos, DE por quadro e o começo de VS na linha.

    Parameters
    ----------
    hs : list[tuple[float, float]]
        Pulsos de HS.
    vs : list[tuple[float, float]]
        Pulsos de VS.
    de : list[tuple[float, float]]
        Intervalos de DE alto.
    timing : Timing
        Temporização esperada.
    period_ps : int
        Período do clock de pixel em picossegundos.
    """
    lines = timing.v_visible
    for k in range(min(lines - 1, len(hs) - 1, len(de) - 1)):
        gap = _clocks(de[k + 1][0] - hs[k][1], period_ps)
        check(gap == timing.h_back, f"pórtico traseiro medido {gap}")
    for k in range(min(lines, len(hs), len(de))):
        gap = _clocks(hs[k][0] - de[k][1], period_ps)
        check(gap == timing.h_front, f"pórtico frontal medido {gap}")
    if len(vs) >= MIN_FRAMES:
        in_frame = [d for d in de if vs[0][0] <= d[0] < vs[1][0]]
        check(
            len(in_frame) == lines,
            f"linhas com DE por quadro: {len(in_frame)}",
        )
    skew = timing.h_total - timing.h_visible - timing.h_front
    for begin, _ in vs:
        in_line = _clocks(begin - hs[0][0], period_ps) % timing.h_total
        check(in_line == skew % timing.h_total, "VS muda no início da linha")

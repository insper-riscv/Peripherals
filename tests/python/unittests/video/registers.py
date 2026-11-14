"""Endereços dos registradores e modo de vídeo lido dos generics."""

from dataclasses import dataclass
from typing import Protocol

from cocotb.handle import LogicArrayObject, LogicObject

CTRL = 0
STATUS = 1
FRAME_COUNT = 2
GEOMETRY = 3
FORMAT = 4
PALETTE = 256
PALETTE_ENTRIES = 256
MASK32 = 0xFFFFFFFF

STATUS_VSYNC = 0b01
STATUS_VBLANK = 0b10

INDEXED_PIXEL_BITS = 8
DIRECT_NARROW_BITS = 16
DIRECT_WIDE_BITS = 32
COLOR_CHANNELS = 3
INDEXED_FLAG = 1 << 24


def storage_bits(indexed: bool, channel_bits: int) -> int:
    """Bits que cada pixel ocupa no framebuffer.

    Parameters
    ----------
    indexed : bool
        Formato indexado quando verdadeiro.
    channel_bits : int
        Bits de cada canal de cor.

    Returns
    -------
    int
        8 no indexado; no direto, 16 ou 32.
    """
    if indexed:
        return INDEXED_PIXEL_BITS
    if COLOR_CHANNELS * channel_bits <= DIRECT_NARROW_BITS:
        return DIRECT_NARROW_BITS
    return DIRECT_WIDE_BITS


class ModeDut(Protocol):
    """Generics de temporização que as entidades de vídeo expõem."""

    h_visible: LogicArrayObject
    h_front_porch: LogicArrayObject
    h_sync: LogicArrayObject
    h_back_porch: LogicArrayObject
    h_sync_positive: LogicObject
    v_visible: LogicArrayObject
    v_front_porch: LogicArrayObject
    v_sync: LogicArrayObject
    v_back_porch: LogicArrayObject
    v_sync_positive: LogicObject


@dataclass(frozen=True)
class Axis:
    """Temporização de uma direção (horizontal ou vertical).

    Attributes
    ----------
    visible : int
        Pixels (ou linhas) visíveis.
    front : int
        Pórtico frontal.
    sync : int
        Largura do pulso de sincronismo.
    back : int
        Pórtico traseiro.
    positive : bool
        Sincronismo em nível alto durante o pulso.
    """

    visible: int
    front: int
    sync: int
    back: int
    positive: bool

    @property
    def total(self) -> int:
        """Pixels (ou linhas) totais."""
        return self.visible + self.front + self.sync + self.back

    @property
    def begin(self) -> int:
        """Posição em que o pulso de sincronismo começa."""
        return self.visible + self.front

    def level(self, position: int) -> int:
        """Nível esperado da saída de sincronismo em uma posição.

        Parameters
        ----------
        position : int
            Coluna ou linha da tela.

        Returns
        -------
        int
            O nível da saída, conforme a polaridade.
        """
        pulse = self.begin <= position < self.begin + self.sync
        return int(pulse == self.positive)


@dataclass(frozen=True)
class Mode:
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
    def h_sync(self) -> int:
        """Largura do pulso horizontal em pixels."""
        return self.h.sync

    @property
    def v_sync(self) -> int:
        """Largura do pulso vertical em linhas."""
        return self.v.sync

    @property
    def v_back(self) -> int:
        """Pórtico traseiro vertical em linhas."""
        return self.v.back

    @property
    def h_positive(self) -> bool:
        """Sincronismo horizontal em nível alto durante o pulso."""
        return self.h.positive

    @property
    def v_positive(self) -> bool:
        """Sincronismo vertical em nível alto durante o pulso."""
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
    def vs_begin(self) -> int:
        """Linha em que o pulso vertical começa."""
        return self.v.begin

    def hs_level(self, column: int) -> int:
        """Nível esperado de HS em uma coluna.

        Parameters
        ----------
        column : int
            Coluna da tela.

        Returns
        -------
        int
            O nível da saída, conforme a polaridade.
        """
        return self.h.level(column)

    def vs_level(self, line: int) -> int:
        """Nível esperado de VS em uma linha.

        Parameters
        ----------
        line : int
            Linha da tela.

        Returns
        -------
        int
            O nível da saída, conforme a polaridade.
        """
        return self.v.level(line)

    def visible(self, column: int, line: int) -> bool:
        """Indica se uma posição da tela está na área visível.

        Parameters
        ----------
        column : int
            Coluna da tela.
        line : int
            Linha da tela.

        Returns
        -------
        bool
            Verdadeiro dentro da área visível.
        """
        return column < self.h.visible and line < self.v.visible


def read_mode(dut: ModeDut) -> Mode:
    """Lê o modo dos generics da entidade sob teste.

    Parameters
    ----------
    dut : ModeDut
        Entidade que expõe os generics de temporização.

    Returns
    -------
    Mode
        A temporização do modo.
    """
    return Mode(
        h=Axis(
            visible=int(dut.h_visible.value),
            front=int(dut.h_front_porch.value),
            sync=int(dut.h_sync.value),
            back=int(dut.h_back_porch.value),
            positive=bool(int(dut.h_sync_positive.value)),
        ),
        v=Axis(
            visible=int(dut.v_visible.value),
            front=int(dut.v_front_porch.value),
            sync=int(dut.v_sync.value),
            back=int(dut.v_back_porch.value),
            positive=bool(int(dut.v_sync_positive.value)),
        ),
    )

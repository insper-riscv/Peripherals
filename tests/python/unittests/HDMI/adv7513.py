"""Modelo comportamental de escravo I2C de escrita (ADV7513)."""

from dataclasses import dataclass, field

import cocotb
from cocotb.handle import LogicObject
from cocotb.triggers import First, Timer
from cocotb.utils import get_sim_time

SLAVE_ADDRESS = 0x39
BITS_PER_BYTE = 8
WRITE_BYTES = 3
VALUE_INDEX = 2


@dataclass(frozen=True)
class Write:
    """Uma escrita de registrador vista no barramento.

    Attributes
    ----------
    device : int
        Endereço de 7 bits que o mestre enviou.
    register : int
        Registrador escrito.
    value : int
        Valor escrito.
    acked : bool
        O escravo confirmou o byte de valor.
    """

    device: int
    register: int
    value: int
    acked: bool


@dataclass(frozen=True)
class I2cPins:
    """Pinos de dreno aberto do mestre, vistos pelo escravo.

    Attributes
    ----------
    scl_oe : LogicObject
        Habilitação de saída de SCL do mestre.
    sda_oe : LogicObject
        Habilitação de saída de SDA do mestre.
    sda_in : LogicObject
        Entrada de SDA do mestre, que o modelo conduz.
    """

    scl_oe: LogicObject
    sda_oe: LogicObject
    sda_in: LogicObject


@dataclass
class _Wire:
    """Estado interno de decodificação do barramento."""

    pull: bool = False
    active: bool = False
    bits: int = 0
    shift: int = 0
    bytes: list[int] = field(default_factory=list[int])
    last_rise_ns: float | None = None


@dataclass
class Adv7513Model:
    """Escravo I2C de escrita que registra as escritas de inicialização.

    O modelo observa as habilitações de saída do mestre (dreno aberto:
    habilitada é linha em zero), reconstrói SDA e SCL no barramento,
    reconhece partida, parada e bits, confirma bytes e devolve o nível
    de SDA ao mestre pelo sinal de entrada.

    Attributes
    ----------
    pins : I2cPins
        Pinos de dreno aberto do mestre.
    address : int
        Endereço de 7 bits que o escravo reconhece.
    nack_registers : set[int]
        Registradores cujo byte de valor o escravo não confirma.
    writes : list[Write]
        Escritas completas, na ordem em que ocorreram.
    scl_periods_ns : list[float]
        Períodos de SCL medidos entre subidas consecutivas.
    errors : list[str]
        Violações do protocolo vistas pelo modelo.
    """

    pins: I2cPins
    address: int = SLAVE_ADDRESS
    nack_registers: set[int] = field(default_factory=set[int])
    writes: list[Write] = field(default_factory=list[Write])
    scl_periods_ns: list[float] = field(default_factory=list[float])
    errors: list[str] = field(default_factory=list[str])
    _w: _Wire = field(default_factory=_Wire)

    def _bus(self) -> tuple[int, int]:
        """Níveis de SCL e de SDA no barramento.

        Returns
        -------
        tuple[int, int]
            SCL e SDA, com a linha em zero se alguém a puxa.
        """
        scl = 0 if int(self.pins.scl_oe.value) else 1
        low = int(self.pins.sda_oe.value) or self._w.pull
        return scl, 0 if low else 1

    def _drive(self) -> int:
        """Aplica o nível de SDA do barramento à entrada do mestre.

        Returns
        -------
        int
            O nível aplicado.
        """
        sda = self._bus()[1]
        self.pins.sda_in.value = sda
        return sda

    def _ack_wanted(self) -> bool:
        """Decide se o byte recém-recebido deve ser confirmado.

        Returns
        -------
        bool
            Verdadeiro para confirmar.
        """
        index = len(self._w.bytes) - 1
        if index == 0:
            return (self._w.bytes[0] >> 1) == self.address
        if index == VALUE_INDEX:
            return self._w.bytes[1] not in self.nack_registers
        return True

    def _byte_done(self) -> bool:
        """Fecha um byte recebido e devolve se deve ser confirmado.

        Returns
        -------
        bool
            Verdadeiro para confirmar o byte.
        """
        self._w.bytes.append(self._w.shift)
        self._w.shift = 0
        self._w.bits = 0
        ack = self._ack_wanted()
        if len(self._w.bytes) == 1 and self._w.bytes[0] & 1:
            self.errors.append("o mestre pediu leitura, o modelo só escreve")
        return ack

    def _finish(self) -> None:
        """Registra a escrita ao ver a parada."""
        if len(self._w.bytes) == WRITE_BYTES:
            device, register, value = self._w.bytes
            self.writes.append(
                Write(
                    device >> 1,
                    register,
                    value,
                    register not in self.nack_registers,
                )
            )
        else:
            self.errors.append(f"parada com {len(self._w.bytes)} bytes")
        self._w.active = False
        self._w.bytes = []
        self._w.bits = 0

    def _on_scl_rise(self, sda: int) -> None:
        """Trata a subida de SCL: amostra o bit de dados.

        Parameters
        ----------
        sda : int
            Nível de SDA na subida.
        """
        now = get_sim_time("ns")
        if self._w.last_rise_ns is not None:
            self.scl_periods_ns.append(now - self._w.last_rise_ns)
        self._w.last_rise_ns = now
        if self._w.active and self._w.bits < BITS_PER_BYTE:
            self._w.shift = (self._w.shift << 1) | sda
            self._w.bits += 1
        elif self._w.active:
            self._w.bits += 1

    def _on_scl_fall(self) -> None:
        """Trata a descida de SCL: confirma o byte ou solta SDA."""
        if not self._w.active:
            return
        if self._w.bits == BITS_PER_BYTE:
            self._w.pull = self._byte_done_ack()
        elif self._w.bits == BITS_PER_BYTE + 1:
            self._w.pull = False
            self._w.bits = 0

    def _byte_done_ack(self) -> bool:
        """Fecha o byte e decide se puxa SDA para confirmar.

        Returns
        -------
        bool
            Verdadeiro para puxar SDA (confirmar).
        """
        ack = self._byte_done()
        self._w.bits = BITS_PER_BYTE
        return ack

    async def run(self) -> None:
        """Observa o barramento até o fim da simulação."""
        await Timer(1, unit="ns")
        scl, sda = 1, 1
        self._drive()
        while True:
            await First(
                self.pins.scl_oe.value_change, self.pins.sda_oe.value_change
            )
            new_scl, new_sda = self._bus()
            if new_scl == 1 and scl == 1 and new_sda != sda:
                if new_sda == 0:
                    self._w.active = True
                    self._w.bytes = []
                    self._w.bits = 0
                    self._w.shift = 0
                elif self._w.active:
                    self._finish()
            elif new_scl == 1 and scl == 0:
                self._on_scl_rise(new_sda)
            elif new_scl == 0 and scl == 1:
                self._on_scl_fall()
            scl = new_scl
            sda = self._drive()


def start_model(model: Adv7513Model) -> None:
    """Põe o modelo para rodar em segundo plano.

    Parameters
    ----------
    model : Adv7513Model
        Modelo a executar.
    """
    cocotb.start_soon(model.run())

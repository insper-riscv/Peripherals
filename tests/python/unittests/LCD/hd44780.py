"""Modelo comportamental do HD44780 de 8 bits ligado ao controlador.

O modelo observa os pinos RS, RW, EN e os dados do controlador,
confere os tempos mínimos do barramento do datasheet (setup de 40 ns,
EN alto de 230 ns, ciclo de EN de 500 ns, hold de 10 ns), executa os
comandos sobre uma DDRAM de 128 posições e mantém o flag de ocupado.
Qualquer acesso fora das regras entra na lista ``violations``, que o
teste exige vazia.
"""

from dataclasses import dataclass, field

import cocotb
from cocotb.triggers import First
from cocotb.utils import get_sim_time

from tests.python.utils.dut import LcdDut

SETUP_NS = 40
PULSE_NS = 230
CYCLE_NS = 500
HOLD_NS = 10
POWER_UP_NS = 15_000_000
EXEC_NS = 37_000
LONG_EXEC_NS = 1_520_000
DDRAM_SIZE = 128
LINE_WIDTH = 16
LINE_ONE_BASE = 0x00
LINE_TWO_BASE = 0x40
BUSY_BIT = 0x80
ADDRESS_MASK = 0x7F
BLANK = 0x20
# Instante inicial bem antes do início da simulação, para que o
# primeiro acesso não acuse tempo curto contra um evento inexistente.
LONG_AGO_NS = -1.0e12


def _blank_ddram() -> list[int]:
    """Devolve uma DDRAM preenchida com espaços.

    Returns
    -------
    list[int]
        As 128 posições com o código do espaço.
    """
    return [BLANK] * DDRAM_SIZE


@dataclass
class ChipState:
    """Conteúdo e configuração do chip que os comandos alteram.

    Attributes
    ----------
    ddram : list[int]
        Conteúdo da DDRAM.
    address : int
        Contador de endereço.
    display_on : bool
        Estado do display.
    cursor_on : bool
        Estado do cursor.
    increment : bool
        Sentido do entry mode.
    two_lines : bool
        Função de duas linhas.
    function_set : bool
        Um function set de 8 bits já foi recebido.
    """

    ddram: list[int] = field(default_factory=_blank_ddram)
    address: int = 0
    display_on: bool = False
    cursor_on: bool = False
    increment: bool = True
    two_lines: bool = False
    function_set: bool = False

    def write_data(self, byte: int) -> None:
        """Grava um caractere na DDRAM e move o contador de endereço.

        Parameters
        ----------
        byte : int
            Código do caractere.
        """
        self.ddram[self.address] = byte
        step = 1 if self.increment else -1
        self.address = (self.address + step) & ADDRESS_MASK

    def command(self, byte: int) -> None:
        """Decodifica e executa um comando.

        Parameters
        ----------
        byte : int
            Byte do comando.
        """
        if byte & 0x80:
            self.address = byte & ADDRESS_MASK
        elif byte & 0x20:
            self.function_set = True
            self.two_lines = bool(byte & 0x08)
        elif byte & 0x10:
            return
        elif byte & 0x08:
            self.display_on = bool(byte & 0x04)
            self.cursor_on = bool(byte & 0x02)
        elif byte & 0x04:
            self.increment = bool(byte & 0x02)
        elif byte & 0x02:
            self.address = 0
        elif byte & 0x01:
            self.ddram = _blank_ddram()
            self.address = 0
            self.increment = True


@dataclass
class PinTimes:
    """Instantes, em nanossegundos, que as regras de tempo comparam.

    Attributes
    ----------
    en_rise_ns : float
        Última subida de EN.
    en_fall_ns : float
        Última descida de EN.
    ctrl_change_ns : float
        Última mudança de RS, RW ou do dado.
    busy_until_ns : float
        Fim do comando em execução.
    """

    en_rise_ns: float = LONG_AGO_NS
    en_fall_ns: float = LONG_AGO_NS
    ctrl_change_ns: float = LONG_AGO_NS
    busy_until_ns: float = 0.0


class Hd44780:
    """Estado e comportamento do chip.

    Attributes
    ----------
    state : ChipState
        DDRAM, contador de endereço e configuração do chip.
    violations : list[str]
        Regras do datasheet que o controlador quebrou.
    writes : list[tuple[int, int]]
        Cada escrita aceita, como o par RS e byte.
    busy_polls : int
        Quantidade de leituras do flag de ocupado.
    """

    def __init__(self, dut: LcdDut, power_up_ns: int = POWER_UP_NS) -> None:
        """Cria o chip e liga o observador dos pinos.

        Parameters
        ----------
        dut : LcdDut
            Controlador cujos pinos o chip observa e dirige.
        power_up_ns : int
            Tempo depois da criação em que o chip aceita escritas.
        """
        self.dut = dut
        self.state = ChipState()
        self.violations: list[str] = []
        self.writes: list[tuple[int, int]] = []
        self.busy_polls = 0
        self._times = PinTimes()
        self._ready_ns = float(get_sim_time(unit="ns")) + power_up_ns
        self._snapshot = self._pins()
        dut.i_lcd_data.value = 0
        cocotb.start_soon(self._observe())

    def _pins(self) -> tuple[str, str, str, str, str]:
        """Lê os pinos que o chip observa.

        Returns
        -------
        tuple[str, str, str, str, str]
            RS, RW, EN, dado e habilitação, em texto.
        """
        dut = self.dut
        return (
            str(dut.o_lcd_rs.value),
            str(dut.o_lcd_rw.value),
            str(dut.o_lcd_en.value),
            str(dut.o_lcd_data.value),
            str(dut.o_lcd_data_oe.value),
        )

    @property
    def busy(self) -> bool:
        """Informa se o chip está executando um comando."""
        return float(get_sim_time(unit="ns")) < self._times.busy_until_ns

    def line(self, number: int) -> str:
        """Devolve o texto visível de uma linha.

        Parameters
        ----------
        number : int
            Linha, 0 ou 1.

        Returns
        -------
        str
            Os 16 caracteres visíveis.
        """
        base = LINE_TWO_BASE if number else LINE_ONE_BASE
        ddram = self.state.ddram
        return "".join(chr(ddram[base + i]) for i in range(LINE_WIDTH))

    async def _observe(self) -> None:
        """Acompanha os pinos e reage a cada mudança."""
        dut = self.dut
        while True:
            await First(
                dut.o_lcd_en.value_change,
                dut.o_lcd_rs.value_change,
                dut.o_lcd_rw.value_change,
                dut.o_lcd_data.value_change,
                dut.o_lcd_data_oe.value_change,
            )
            now = float(get_sim_time(unit="ns"))
            pins = self._pins()
            old = self._snapshot
            self._snapshot = pins
            if pins[:2] != old[:2] or pins[3:] != old[3:]:
                self._on_control_change(now, pins)
            if pins[2] != old[2]:
                if pins[2] == "1":
                    self._on_en_rise(now, pins)
                elif pins[2] == "0":
                    self._on_en_fall(now, pins)

    def _on_control_change(self, now: float, pins: tuple[str, ...]) -> None:
        """Confere o hold quando RS, RW ou o dado mudam.

        Parameters
        ----------
        now : float
            Tempo da simulação em nanossegundos.
        pins : tuple[str, ...]
            Estado atual dos pinos.
        """
        self._times.ctrl_change_ns = now
        if pins[2] == "1":
            self.violations.append(f"{now}: RS, RW ou dado mudou com EN alto")
        elif now - self._times.en_fall_ns < HOLD_NS:
            self.violations.append(f"{now}: hold menor que {HOLD_NS} ns")

    def _on_en_rise(self, now: float, pins: tuple[str, ...]) -> None:
        """Confere o setup e dirige o barramento numa leitura.

        Parameters
        ----------
        now : float
            Tempo da simulação em nanossegundos.
        pins : tuple[str, ...]
            Estado atual dos pinos.
        """
        times = self._times
        if now - times.ctrl_change_ns < SETUP_NS:
            self.violations.append(f"{now}: setup menor que {SETUP_NS} ns")
        if now - times.en_rise_ns < CYCLE_NS:
            self.violations.append(
                f"{now}: ciclo de EN menor que {CYCLE_NS} ns"
            )
        times.en_rise_ns = now
        rs, rw, _, _, oe = pins
        if rw == "1":
            if oe == "1":
                self.violations.append(
                    f"{now}: conflito no barramento de dados"
                )
            self._drive_read(rs)
        elif oe != "1":
            self.violations.append(f"{now}: escrita sem conduzir o dado")

    def _drive_read(self, rs: str) -> None:
        """Coloca o byte de uma leitura nos pinos de dados.

        Parameters
        ----------
        rs : str
            Nível de RS da leitura.
        """
        state = self.state
        if rs == "0":
            self.busy_polls += 1
            value = state.address | (BUSY_BIT if self.busy else 0)
        else:
            value = state.ddram[state.address]
        self.dut.i_lcd_data.value = value

    def _on_en_fall(self, now: float, pins: tuple[str, ...]) -> None:
        """Confere o pulso e executa a escrita na descida de EN.

        Parameters
        ----------
        now : float
            Tempo da simulação em nanossegundos.
        pins : tuple[str, ...]
            Estado atual dos pinos.
        """
        self._times.en_fall_ns = now
        if now - self._times.en_rise_ns < PULSE_NS:
            self.violations.append(f"{now}: EN alto menor que {PULSE_NS} ns")
        rs, rw, _, data, oe = pins
        self.dut.i_lcd_data.value = 0
        if rw == "1" or oe != "1":
            return
        self._write(now, int(rs), int(data, 2))

    def _write(self, now: float, rs: int, byte: int) -> None:
        """Executa uma escrita de comando ou de dado.

        Parameters
        ----------
        now : float
            Tempo da simulação em nanossegundos.
        rs : int
            Nível de RS.
        byte : int
            Byte escrito.
        """
        if now < self._ready_ns:
            self.violations.append(
                f"{now}: escrita antes de 15 ms de energização"
            )
            return
        if self.busy:
            self.violations.append(
                f"{now}: escrita {rs}:{byte:#04x} com o chip ocupado"
            )
            return
        self.writes.append((rs, byte))
        if rs:
            self.state.write_data(byte)
            self._times.busy_until_ns = now + EXEC_NS
        else:
            self.state.command(byte)
            slow = byte & 0xFC == 0
            self._times.busy_until_ns = now + (
                LONG_EXEC_NS if slow else EXEC_NS
            )

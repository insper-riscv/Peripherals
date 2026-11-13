"""Modelo comportamental do protocolo de acesso do chip USB.

O modelo imita só o protocolo de acesso paralelo: cada controlador (host
e dispositivo) tem uma porta de comando e uma de dado; escrever o código
de um registrador na porta de comando seleciona o registrador, e a porta
de dado lê ou escreve o registrador selecionado. Os códigos e os valores
de identificador abaixo são do modelo, não do chip real.
"""

from dataclasses import dataclass, field

import cocotb
from cocotb.task import Task
from cocotb.triggers import RisingEdge, Timer

from tests.python.unittests.USB.signals import UsbDut

HC_ID_CMD = 0x10
DC_ID_CMD = 0x20
HC_ID = 0xA5C3
DC_ID = 0x3C5A
IDLE_BUS = 0x0000
PORT_IS_DC = 0b10
PORT_IS_CMD = 0b01
MASK16 = 0xFFFF


@dataclass(frozen=True)
class Sample:
    """Estado dos pinos da ponte num ciclo de clock."""

    cs_n: int
    rd_n: int
    wr_n: int
    addr: int
    data: int
    oe: int


@dataclass
class ChipModel:
    """Chip com dois controladores e o histórico dos pinos."""

    dut: UsbDut
    regs: list[dict[int, int]] = field(
        default_factory=lambda: [
            {HC_ID_CMD: HC_ID},
            {DC_ID_CMD: DC_ID},
        ]
    )
    command: list[int] = field(default_factory=lambda: [0, 0])
    log: list[Sample] = field(default_factory=list[Sample])
    writes: list[tuple[int, int]] = field(
        default_factory=list[tuple[int, int]]
    )
    contention: bool = False
    task: Task[None] | None = None

    def start(self) -> None:
        """Inicia a tarefa que observa os pinos e responde."""
        self.task = cocotb.start_soon(self._run())

    def stop(self) -> None:
        """Encerra a tarefa do modelo."""
        if self.task is not None:
            self.task.cancel()

    def _read_value(self, addr: int) -> int:
        """Devolve o dado que o chip apresenta numa leitura."""
        which = 1 if addr & PORT_IS_DC else 0
        if addr & PORT_IS_CMD:
            return IDLE_BUS
        return self.regs[which].get(self.command[which], IDLE_BUS)

    def _commit_write(self, sample: Sample) -> None:
        """Aplica uma escrita completa ao modelo."""
        which = 1 if sample.addr & PORT_IS_DC else 0
        self.writes.append((sample.addr, sample.data))
        if sample.addr & PORT_IS_CMD:
            self.command[which] = sample.data
        else:
            self.regs[which][self.command[which]] = sample.data

    async def _run(self) -> None:
        """Amostra os pinos a cada clock e dirige o dado."""
        previous: Sample | None = None
        while True:
            await RisingEdge(self.dut.i_clk)
            await Timer(1, unit="ns")
            sample = Sample(
                cs_n=int(self.dut.o_otg_cs_n.value),
                rd_n=int(self.dut.o_otg_rd_n.value),
                wr_n=int(self.dut.o_otg_wr_n.value),
                addr=int(self.dut.o_otg_addr.value),
                data=int(self.dut.o_otg_data.value),
                oe=int(self.dut.o_otg_data_oe.value),
            )
            self.log.append(sample)
            if sample.rd_n == 0 and sample.oe == 1:
                self.contention = True
            if (
                previous is not None
                and previous.wr_n == 0
                and sample.wr_n == 1
            ):
                self._commit_write(previous)
            if sample.cs_n == 0 and sample.rd_n == 0:
                value = self._read_value(sample.addr)
            else:
                value = IDLE_BUS
            self.dut.i_otg_data.value = value
            previous = sample

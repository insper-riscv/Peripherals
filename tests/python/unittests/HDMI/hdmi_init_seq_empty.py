"""Sequenciador de tabela vazia: o início só marca o fim."""

from cocotb import test
from cocotb.triggers import RisingEdge

from tests.python.unittests.HDMI.seq_bench import (
    SeqDut,
    check_counts,
    pulse_start,
    start,
)
from tests.python.utils.check import check


@test()
async def test_empty_table_only_marks_done(dut: SeqDut) -> None:
    """Sem entradas, o início conclui sem nenhum pedido de escrita."""
    writer = await start(dut)
    check(int(dut.o_busy.value) == 0, "nunca ocupado")
    check(int(dut.o_done.value) == 0, "só conclui depois do início")
    await pulse_start(dut)
    for _ in range(10):
        await RisingEdge(dut.i_clk)
    check(int(dut.o_done.value) == 1, "concluído")
    check(int(dut.o_busy.value) == 0, "nunca ocupado")
    check(not writer.requests, "nenhum pedido de escrita")
    check_counts(dut, 0, 0)

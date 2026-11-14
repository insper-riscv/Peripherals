"""Sequenciador com início automático depois do reset."""

from cocotb import test
from cocotb.triggers import RisingEdge

from tests.python.unittests.HDMI.seq_bench import (
    TABLE,
    SeqDut,
    check_counts,
    pulse_start,
    start,
    wait_idle,
)
from tests.python.utils.check import check


@test()
async def test_auto_start_sends_table_in_order(dut: SeqDut) -> None:
    """Depois do reset, a tabela sai inteira e na ordem, uma vez."""
    writer = await start(dut)
    check(int(dut.o_busy.value) == 1, "ocupado logo depois do reset")
    check(int(dut.o_done.value) == 0, "ainda não concluído")
    await wait_idle(dut)
    check(writer.requests == TABLE, f"pedidos: {writer.requests}")
    check(int(dut.o_done.value) == 1, "concluído no fim")
    check_counts(dut, len(TABLE), 0)
    for _ in range(100):
        await RisingEdge(dut.i_clk)
    check(len(writer.requests) == len(TABLE), "nada mais é pedido")


@test()
async def test_restart_repeats_and_clears_counters(dut: SeqDut) -> None:
    """Um novo início repete a tabela e zera estado e contadores."""
    writer = await start(dut, nack_on={1})
    await wait_idle(dut)
    check_counts(dut, len(TABLE), 1)
    await pulse_start(dut)
    check(int(dut.o_done.value) == 0, "o início limpa o estado concluído")
    check_counts(dut, 0, 0)
    await wait_idle(dut)
    check(writer.requests == TABLE + TABLE, f"pedidos: {writer.requests}")
    check_counts(dut, len(TABLE), 0)
    check(int(dut.o_done.value) == 1, "concluído de novo")


@test()
async def test_start_while_busy_is_ignored(dut: SeqDut) -> None:
    """Um início com a sequência em andamento não a reinicia."""
    writer = await start(dut)
    for _ in range(3):
        await pulse_start(dut)
    await wait_idle(dut)
    check(writer.requests == TABLE, f"pedidos: {writer.requests}")

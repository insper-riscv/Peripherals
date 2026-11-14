"""Sequenciador sem início automático e com escritas sem confirmação."""

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
async def test_idle_until_start(dut: SeqDut) -> None:
    """Sem início automático nada é pedido até o pulso de i_start."""
    writer = await start(dut)
    for _ in range(100):
        await RisingEdge(dut.i_clk)
    check(not writer.requests, "nenhum pedido antes do início")
    check(int(dut.o_busy.value) == 0, "parado")
    check(int(dut.o_done.value) == 0, "não concluído")
    await pulse_start(dut)
    await wait_idle(dut)
    check(writer.requests == TABLE, f"pedidos: {writer.requests}")
    check_counts(dut, len(TABLE), 0)


@test()
async def test_nacks_are_counted_and_do_not_stop(dut: SeqDut) -> None:
    """Escritas sem ACK são contadas e a tabela segue até o fim."""
    writer = await start(dut, nack_on={1, 2})
    await pulse_start(dut)
    await wait_idle(dut)
    check(writer.requests == TABLE, f"pedidos: {writer.requests}")
    check_counts(dut, len(TABLE), 2)
    check(int(dut.o_done.value) == 1, "concluído apesar dos NACK")

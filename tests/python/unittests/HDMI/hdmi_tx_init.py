"""Periférico HDMI: inicialização do transmissor pelo I2C."""

import cocotb
from cocotb.triggers import RisingEdge

from tests.python.unittests.HDMI import hdmi_bench as bench
from tests.python.unittests.HDMI.adv7513 import (
    SLAVE_ADDRESS,
    Write,
    start_model,
)
from tests.python.unittests.HDMI.hdmi_bench import TxDut
from tests.python.utils.check import check

# A tabela de tests.json. Os quatro pares servem só ao teste do
# sequenciador; os valores reais do ADV7513 vêm do guia do fabricante.
TABLE = [(0x98, 0x03), (0x01, 0x00), (0x15, 0x20), (0xAF, 0x16)]
SEQ_LIMIT_CYCLES = 20_000


async def wait_done(dut: TxDut) -> None:
    """Espera o sequenciador concluir.

    Parameters
    ----------
    dut : TxDut
        Periférico sob teste.
    """
    for _ in range(SEQ_LIMIT_CYCLES):
        await RisingEdge(dut.i_clk)
        status = await bench.read(dut, bench.HDMI_STATUS)
        if status & bench.ST_DONE:
            return
    message = "o sequenciador não concluiu"
    raise AssertionError(message)


def writes(model: bench.Adv7513Model) -> list[Write]:
    """Escritas esperadas da tabela.

    Parameters
    ----------
    model : bench.Adv7513Model
        Modelo do escravo, que define os registradores rejeitados.

    Returns
    -------
    list[Write]
        Uma escrita por entrada da tabela.
    """
    return [
        Write(SLAVE_ADDRESS, r, v, r not in model.nack_registers)
        for r, v in TABLE
    ]


@cocotb.test()
async def test_table_is_written_without_software(dut: TxDut) -> None:
    """Depois do reset a tabela sai inteira e na ordem, sem software."""
    model = bench.build_model(dut)
    start_model(model)
    await bench.start(dut)
    status = await bench.read(dut, bench.HDMI_STATUS)
    check(status & bench.ST_INIT != 0, "sequenciador presente")
    await wait_done(dut)
    check(model.writes == writes(model), f"escritas: {model.writes}")
    check(not model.errors, f"violações: {model.errors}")
    count = await bench.read(dut, bench.SEQ_COUNT)
    check(count & 0xFF == len(TABLE), f"entradas concluídas {count:#x}")
    check(count >> 8 & 0xFF == 0, "nenhum NACK")
    check(count >> 16 & 0xFF == len(TABLE), "entradas da tabela")
    status = await bench.read(dut, bench.HDMI_STATUS)
    check(status & (bench.ST_NACK | bench.ST_BUSY) == 0, "sem NACK, parado")
    check(int(dut.o_i2c_sda_out.value) == 0, "o_i2c_sda_out zero")
    check(int(dut.o_i2c_scl_out.value) == 0, "o_i2c_scl_out zero")


@cocotb.test()
async def test_restart_and_nack(dut: TxDut) -> None:
    """Reiniciar repete a tabela; o NACK é contado e não interrompe."""
    model = bench.build_model(dut)
    model.nack_registers = {0x15}
    start_model(model)
    await bench.start(dut)
    await wait_done(dut)
    count = await bench.read(dut, bench.SEQ_COUNT)
    check(count & 0xFF == len(TABLE), "a tabela inteira foi enviada")
    check(count >> 8 & 0xFF == 1, f"um NACK contado: {count:#x}")
    status = await bench.read(dut, bench.HDMI_STATUS)
    check(status & bench.ST_NACK != 0, "estado de NACK")
    await bench.write(dut, bench.SEQ_CTRL, 1)
    check(
        await bench.read(dut, bench.HDMI_STATUS) & bench.ST_DONE == 0,
        "o reinício limpa o concluído",
    )
    await bench.cycles(dut, 5)
    await bench.write(dut, bench.SEQ_CTRL, 1)
    await wait_done(dut)
    check(model.writes == writes(model) * 2, f"escritas: {model.writes}")
    check(not model.errors, f"violações: {model.errors}")

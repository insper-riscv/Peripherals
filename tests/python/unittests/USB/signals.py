"""Visão tipada da ponte USB sob teste."""

from typing import Protocol

from cocotb.handle import LogicArrayObject, LogicObject

from tests.python.utils.dut import IrqDut


class UsbDut(IrqDut, Protocol):
    """Sinais da ponte paralela para o chip USB."""

    o_otg_cs_n: LogicObject
    o_otg_rd_n: LogicObject
    o_otg_wr_n: LogicObject
    o_otg_rst_n: LogicObject
    o_otg_addr: LogicArrayObject
    o_otg_data: LogicArrayObject
    o_otg_data_oe: LogicObject
    i_otg_data: LogicArrayObject
    i_otg_int: LogicArrayObject
    i_otg_dreq: LogicObject
    o_otg_dack: LogicObject


class MasterDut(Protocol):
    """Sinais do mestre do barramento do chip."""

    i_clk: LogicObject
    i_rst: LogicObject
    i_start: LogicObject
    i_is_read: LogicObject
    i_port: LogicArrayObject
    i_wdata: LogicArrayObject
    i_setup: LogicArrayObject
    i_pulse: LogicArrayObject
    i_recovery: LogicArrayObject
    o_busy: LogicObject
    o_rdata: LogicArrayObject
    i_chip_data: LogicArrayObject
    o_cs_n: LogicObject
    o_rd_n: LogicObject
    o_wr_n: LogicObject
    o_chip_addr: LogicArrayObject
    o_chip_data: LogicArrayObject
    o_chip_data_oe: LogicObject


class RegsDut(IrqDut, Protocol):
    """Sinais dos registradores da ponte."""

    o_start: LogicObject
    o_is_read: LogicObject
    o_port: LogicArrayObject
    o_wdata: LogicArrayObject
    o_setup: LogicArrayObject
    o_pulse: LogicArrayObject
    o_recovery: LogicArrayObject
    i_busy: LogicObject
    i_rdata: LogicArrayObject
    i_int: LogicArrayObject
    i_dreq: LogicObject
    o_chip_reset: LogicObject
    o_dack: LogicObject

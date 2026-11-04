"""Typed views of the designs under test.

The handle that cocotb passes to a test resolves its signals by name at
run time, so a type checker only sees an untyped object. These
protocols declare the signals each testbench exposes.
"""

from typing import Protocol

from cocotb.handle import LogicArrayObject, LogicObject


class BusDut(Protocol):
    """Signals of any peripheral on the memory-mapped bus."""

    i_clk: LogicObject
    i_rst: LogicObject
    i_write: LogicObject
    i_read: LogicObject
    i_address: LogicArrayObject
    i_data_in: LogicArrayObject
    o_data_out: LogicArrayObject


class IrqDut(BusDut, Protocol):
    """A bus peripheral with an interrupt output."""

    o_irq: LogicObject


class GpioDut(IrqDut, Protocol):
    """Signals of the GPIO testbench."""

    i_pin_drive: LogicArrayObject
    i_pin_drive_en: LogicArrayObject
    o_pins: LogicArrayObject


class TimerDut(IrqDut, Protocol):
    """Signals of the TIMER."""

    o_pwm: LogicObject
    counter: LogicArrayObject


class UartDut(IrqDut, Protocol):
    """Signals of the UART."""

    i_uart_rx: LogicObject
    o_uart_tx: LogicObject
    phy_new_rx_data: LogicObject


class UartFifoDut(Protocol):
    """Signals of the synchronous FIFO used by the serial UART."""

    i_clk: LogicObject
    i_rst: LogicObject
    i_push: LogicObject
    i_push_data: LogicArrayObject
    i_pop: LogicObject
    o_pop_data: LogicArrayObject
    o_push_accepted: LogicObject
    o_pop_accepted: LogicObject
    o_full: LogicObject
    o_empty: LogicObject
    o_level: LogicArrayObject


class DecoderDut(Protocol):
    """Inputs shared by the operation decoders."""

    i_address: LogicArrayObject
    i_write: LogicObject
    i_read: LogicObject
    o_wr_en: LogicArrayObject
    o_rd_sel: LogicArrayObject


class GpioDecoderDut(DecoderDut, Protocol):
    """Signals of the GPIO operation decoder."""

    o_wr_op: LogicArrayObject


class TimerDecoderDut(DecoderDut, Protocol):
    """Signals of the TIMER operation decoder."""

    o_cnt_sel: LogicObject

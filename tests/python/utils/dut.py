"""Typed views of the designs under test.

The handle that cocotb passes to a test resolves its signals by name at
run time, so a type checker only sees an untyped object. These
protocols declare the signals each testbench exposes.
"""

from typing import Protocol

from cocotb.handle import LogicArrayObject, LogicObject


class ClockedDut(Protocol):
    """A design with a clock."""

    i_clk: LogicObject


class ResettableDut(ClockedDut, Protocol):
    """A clocked design with a synchronous reset."""

    i_rst: LogicObject


class BusDut(ResettableDut, Protocol):
    """Signals of any peripheral on the memory-mapped bus."""

    i_write: LogicObject
    i_read: LogicObject
    i_address: LogicArrayObject
    i_data_in: LogicArrayObject
    o_data_out: LogicArrayObject


class IrqDut(BusDut, Protocol):
    """A bus peripheral with an interrupt output."""

    o_irq: LogicObject


class ClintDut(BusDut, Protocol):
    """Signals of the CLINT."""

    o_irq_timer: LogicObject
    o_irq_software: LogicObject
    o_mtime: LogicArrayObject


class PlicDut(BusDut, Protocol):
    """Signals of the PLIC."""

    i_sources: LogicArrayObject
    o_meip: LogicObject


class PlicGatewayDut(ResettableDut, Protocol):
    """Signals of the gateway of one PLIC source."""

    i_source: LogicObject
    i_claim: LogicObject
    i_complete: LogicObject
    o_pending: LogicObject


class PlicArbiterDut(Protocol):
    """Signals of the PLIC arbiter."""

    i_pending: LogicArrayObject
    i_enable: LogicArrayObject
    i_priorities: LogicArrayObject
    i_threshold: LogicArrayObject
    o_id: LogicArrayObject
    o_valid: LogicObject


class GpioGroupDut(IrqDut, Protocol):
    """Signals of one GPIO group, which does not touch the pads."""

    i_pins: LogicArrayObject
    o_pins_drv: LogicArrayObject
    o_pins_en: LogicArrayObject


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
    o_rd_level: LogicObject


class TimerDecoderDut(DecoderDut, Protocol):
    """Signals of the TIMER operation decoder."""

    o_cnt_sel: LogicObject


class ComparatorDut(Protocol):
    """Operands of the unsigned comparators."""

    i_source_1: LogicArrayObject
    o_ge: LogicObject


class AluGeDut(ComparatorDut, Protocol):
    """Signals of the ALU greater-or-equal comparator."""

    i_source_2: LogicArrayObject


class CounterOverflowDut(Protocol):
    """Signals of the counter overflow unit."""

    i_counter_value: LogicArrayObject
    i_top_value: LogicArrayObject
    o_overflow: LogicObject


class PrescalerDut(ResettableDut, Protocol):
    """Signals of the clock prescaler."""

    i_prescaler_in: LogicArrayObject
    o_tick: LogicObject


class GpioCellDut(ResettableDut, Protocol):
    """Signals of the GPIO cell testbench."""

    i_data_in: LogicObject
    o_data_out: LogicArrayObject
    i_wr_signals: LogicArrayObject
    i_wr_op: LogicArrayObject
    i_pin_drive: LogicObject
    i_pin_drive_en: LogicObject
    o_pin: LogicObject


class Seg7Dut(Protocol):
    """Signals of the hexadecimal digit decoder."""

    i_digit: LogicArrayObject
    o_seg: LogicArrayObject


class JtagDut(Protocol):
    """Scan signals of a design behind a Virtual JTAG instance."""

    i_tck: LogicObject
    i_ir_in: LogicArrayObject
    i_state_cdr: LogicObject
    i_state_sdr: LogicObject
    i_state_udr: LogicObject
    i_state_uir: LogicObject


class JtagScanDut(JtagDut, Protocol):
    """Serial data pins of a Virtual JTAG scan."""

    i_tdi: LogicObject
    o_tdo: LogicObject


class JtagUartDut(JtagDut, ResettableDut, Protocol):
    """Signals of the UART over JTAG."""

    i_addr: LogicArrayObject
    i_wdata: LogicArrayObject
    i_we: LogicObject
    i_re: LogicObject
    o_rdata: LogicArrayObject
    o_irq: LogicObject
    i_tdi: LogicObject
    o_tdo: LogicObject


class ConsolePinsDut(ResettableDut, Protocol):
    """Signals of the console with the pins backend."""

    i_rx: LogicObject
    o_tx: LogicObject
    i_addr: LogicArrayObject
    i_wdata: LogicArrayObject
    i_we: LogicObject
    i_re: LogicObject
    o_rdata: LogicArrayObject
    o_irq: LogicObject


class FlashControllerDut(BusDut, Protocol):
    """Signals of the FLASH controller."""

    o_irq: LogicObject
    o_cmd_valid: LogicObject
    o_cmd_op: LogicArrayObject
    o_cmd_addr: LogicArrayObject
    i_busy: LogicObject
    i_wel: LogicObject
    i_refused: LogicObject
    i_buf_idx: LogicArrayObject
    o_buf_data: LogicArrayObject


class Ps2HostTbDut(ClockedDut, Protocol):
    """Signals comuns do testbench de dois canais ps2_host."""

    i_rst_n: LogicObject


class Ps2FilterDut(ClockedDut, Protocol):
    """Sinais do filtro de glitch de uma linha PS/2."""

    i_rst_n: LogicObject
    i_d: LogicObject
    o_d: LogicObject


class Ps2KeyboardTbDut(IrqDut, Protocol):
    """Sinais do testbench do teclado PS/2."""

    i_dev_clk_low0: LogicObject
    i_dev_dat_low0: LogicObject
    o_clk0: LogicObject
    o_dat0: LogicObject


class ByteHostDut(ResettableDut, Protocol):
    """Interface de bytes do ps2_host, vista do lado do mouse."""

    i_rx_data: LogicArrayObject
    i_rx_valid: LogicObject
    i_rx_error: LogicObject
    o_tx_data: LogicArrayObject
    o_tx_valid: LogicObject
    i_tx_ready: LogicObject


class AxisAccumulatorDut(ResettableDut, Protocol):
    """Sinais do acumulador saturado de um eixo do mouse."""

    i_clear: LogicObject
    i_add_valid: LogicObject
    i_delta: LogicArrayObject
    o_value: LogicArrayObject
    o_saturated: LogicObject


class MouseDut(IrqDut, ByteHostDut, Protocol):
    """Sinais do mouse PS/2, no barramento e na interface de bytes."""


class MouseDecoderDut(ByteHostDut, Protocol):
    """Sinais do decodificador de protocolo do mouse PS/2."""

    i_restart: LogicObject
    o_streaming: LogicObject
    o_packet_valid: LogicObject
    o_buttons: LogicArrayObject
    o_dx: LogicArrayObject
    o_dy: LogicArrayObject
    o_overflow: LogicObject
    o_error: LogicObject


class MouseOperationDecoderDut(Protocol):
    """Sinais do decodificador de operações do mouse PS/2."""

    i_address: LogicArrayObject
    i_write: LogicObject
    i_read: LogicObject
    o_rd_sel: LogicArrayObject
    o_status_read: LogicObject
    o_dx_read: LogicObject
    o_dy_read: LogicObject
    o_control_write: LogicObject


class Ps2CableTbDut(ResettableDut, Protocol):
    """Sinais comuns do testbench do cabo Y, com teclado e mouse."""


class SdSpiDut(IrqDut, Protocol):
    """Signals of the SD card controller in SPI mode."""

    o_sd_sclk: LogicObject
    o_sd_mosi: LogicObject
    i_sd_miso: LogicObject
    o_sd_cs_n: LogicObject


class SdSpiPhyDut(ResettableDut, Protocol):
    """Signals of the one-byte SPI master of the SD controller."""

    i_divider: LogicArrayObject
    i_start: LogicObject
    i_tx_data: LogicArrayObject
    o_busy: LogicObject
    o_done: LogicObject
    o_rx_data: LogicArrayObject
    o_sclk: LogicObject
    o_mosi: LogicObject
    i_miso: LogicObject
class IrDut(IrqDut, Protocol):
    """Signals of the infrared receiver."""
    i_irda_rxd: LogicObject

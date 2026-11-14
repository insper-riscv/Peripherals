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


class LcdDut(IrqDut, Protocol):
    """Signals of the LCD controller."""

    i_lcd_data: LogicArrayObject
    o_lcd_data: LogicArrayObject
    o_lcd_data_oe: LogicObject
    o_lcd_rs: LogicObject
    o_lcd_rw: LogicObject
    o_lcd_en: LogicObject
    o_lcd_on: LogicObject
    o_lcd_blon: LogicObject


class LcdRegsDut(BusDut, Protocol):
    """Signals of the LCD registers."""

    o_irq: LogicObject
    o_push: LogicObject
    o_push_rs: LogicObject
    o_push_data: LogicArrayObject
    i_push_accepted: LogicObject
    i_fifo_full: LogicObject
    i_fifo_empty: LogicObject
    i_fifo_level: LogicArrayObject
    i_phy_busy: LogicObject
    i_init_busy: LogicObject
    i_timeout: LogicObject
    o_poll_enable: LogicObject
    o_delay: LogicArrayObject
    o_delay_long: LogicArrayObject
    o_lcd_on: LogicObject
    o_lcd_blon: LogicObject


class LcdPhyDut(ResettableDut, Protocol):
    """Signals of the LCD physical layer."""

    i_start: LogicObject
    i_rs: LogicObject
    i_data: LogicArrayObject
    i_poll: LogicObject
    i_delay: LogicArrayObject
    i_busy_flag: LogicObject
    o_ready: LogicObject
    o_timeout: LogicObject
    o_lcd_rs: LogicObject
    o_lcd_rw: LogicObject
    o_lcd_en: LogicObject
    o_lcd_data: LogicArrayObject
    o_lcd_data_oe: LogicObject


class LcdInitDut(ResettableDut, Protocol):
    """Signals of the LCD initialization sequence."""

    i_phy_ready: LogicObject
    o_start: LogicObject
    o_data: LogicArrayObject
    o_delay: LogicArrayObject
    o_busy: LogicObject


class I2cDut(IrqDut, Protocol):
    """Signals of the I2C master testbench."""

    i_slave_scl_low: LogicObject
    i_slave_sda_low: LogicObject
    o_scl: LogicObject
    o_sda: LogicObject


class I2cCoreDut(ResettableDut, Protocol):
    """Signals of the line state machine of the I2C master."""

    i_enable: LogicObject
    i_abort: LogicObject
    i_divider: LogicArrayObject
    i_cmd_valid: LogicObject
    i_cmd_start: LogicObject
    i_cmd_stop: LogicObject
    i_cmd_read: LogicObject
    i_cmd_write: LogicObject
    i_cmd_nack: LogicObject
    i_tx_data: LogicArrayObject
    i_scl: LogicObject
    i_sda: LogicObject
    o_busy: LogicObject
    o_bus_active: LogicObject
    o_done: LogicObject
    o_nack: LogicObject
    o_arb_lost: LogicObject
    o_rx_data: LogicArrayObject
    o_scl_low: LogicObject
    o_sda_low: LogicObject


class AudioDut(IrqDut, Protocol):
    """Sinais do periférico de áudio I2S."""

    o_xck: LogicObject
    i_bclk: LogicObject
    o_bclk: LogicObject
    o_bclk_oe: LogicObject
    i_adclrck: LogicObject
    o_adclrck: LogicObject
    i_daclrck: LogicObject
    o_daclrck: LogicObject
    i_adcdat: LogicObject
    o_dacdat: LogicObject


class AudioXckGenDut(ResettableDut, Protocol):
    """Sinais do gerador do clock mestre do áudio."""

    i_enable: LogicObject
    i_step: LogicArrayObject
    i_mod: LogicArrayObject
    o_xck: LogicObject
    o_edge: LogicObject


class AudioFrameClocksDut(ResettableDut, Protocol):
    """Sinais dos clocks de bit e de canal do áudio."""

    i_enable: LogicObject
    i_xck_edge: LogicObject
    i_bclk_div: LogicArrayObject
    i_slot_bits: LogicArrayObject
    o_bclk: LogicObject
    o_lrck: LogicObject


class AudioToneDut(ResettableDut, Protocol):
    """Sinais do gerador de tom do áudio."""

    i_enable: LogicObject
    i_half: LogicArrayObject
    i_advance: LogicObject
    o_level: LogicObject


class AudioTxDut(ResettableDut, Protocol):
    """Sinais do serializador I2S de reprodução."""

    i_enable: LogicObject
    i_bclk: LogicObject
    i_lrck: LogicObject
    i_available: LogicObject
    i_data: LogicArrayObject
    o_load: LogicObject
    o_right_slot: LogicObject
    o_underflow: LogicObject
    o_sdata: LogicObject


class AudioRxDut(ResettableDut, Protocol):
    """Sinais do desserializador I2S de gravação."""

    i_enable: LogicObject
    i_word_bits: LogicArrayObject
    i_bclk: LogicObject
    i_lrck: LogicObject
    i_sdata: LogicObject
    o_valid: LogicObject
    o_right: LogicObject
    o_word: LogicArrayObject


class TvDut(IrqDut, Protocol):
    """Signals of the TV capture peripheral."""

    i_td_clk27: LogicObject
    i_td_data: LogicArrayObject
    o_td_reset_n: LogicObject


class TvRxDut(ResettableDut, Protocol):
    """Signals of the BT.656 receiver of the TV capture."""

    i_data: LogicArrayObject
    o_line_start: LogicObject
    o_field_start: LogicObject
    o_field_end: LogicObject
    o_error: LogicObject
    o_field: LogicObject
    o_present: LogicObject
    o_pix_valid: LogicObject
    o_y: LogicArrayObject
    o_cb: LogicArrayObject
    o_cr: LogicArrayObject


class TvColorDut(ClockedDut, Protocol):
    """Signals of the color conversion of the TV capture."""

    i_we: LogicObject
    i_index: LogicArrayObject
    i_format: LogicObject
    i_y: LogicArrayObject
    i_cb: LogicArrayObject
    i_cr: LogicArrayObject
    o_we: LogicArrayObject
    o_waddr: LogicArrayObject
    o_wdata: LogicArrayObject


class TvRegsDut(IrqDut, Protocol):
    """Signals of the register block of the TV capture."""

    i_present: LogicObject
    i_done_tog: LogicObject
    i_cap_ok: LogicObject
    i_err_tog: LogicObject
    i_rd_data: LogicArrayObject
    o_start_tog: LogicObject
    o_x_div: LogicArrayObject
    o_y_div: LogicArrayObject
    o_field_sel: LogicArrayObject
    o_format: LogicObject
    o_decoder_run: LogicObject
    o_rd_addr: LogicArrayObject


class TvCaptureDut(ResettableDut, Protocol):
    """Signals of the capture control of the TV capture."""

    i_start: LogicObject
    i_x_div: LogicArrayObject
    i_y_div: LogicArrayObject
    i_field_sel: LogicArrayObject
    i_format: LogicObject
    i_line_start: LogicObject
    i_field_start: LogicObject
    i_field_end: LogicObject
    i_field: LogicObject
    i_present: LogicObject
    i_pix_valid: LogicObject
    i_y: LogicArrayObject
    i_cb: LogicArrayObject
    i_cr: LogicArrayObject
    o_busy: LogicObject
    o_done: LogicObject
    o_ok: LogicObject
    o_we: LogicObject
    o_index: LogicArrayObject
    o_format: LogicObject
    o_y: LogicArrayObject

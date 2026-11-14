"""Visão tipada do periférico de vídeo sob teste."""

from typing import Protocol

from cocotb.handle import LogicArrayObject, LogicObject

from tests.python.unittests.video.registers import ModeDut


class VideoDut(ModeDut, Protocol):
    """Sinais do periférico de vídeo."""

    i_clk: LogicObject
    i_pixel_clk: LogicObject
    i_rst: LogicObject
    i_data_in: LogicArrayObject
    i_address: LogicArrayObject
    i_byteena: LogicArrayObject
    i_write: LogicObject
    o_data_out: LogicArrayObject
    o_vga_r: LogicArrayObject
    o_vga_g: LogicArrayObject
    o_vga_b: LogicArrayObject
    o_vga_hs: LogicObject
    o_vga_vs: LogicObject
    o_vga_blank_n: LogicObject
    o_vga_sync_n: LogicObject


class TimingDut(ModeDut, Protocol):
    """Sinais do gerador de temporização."""

    fb_width: LogicArrayObject
    fb_height: LogicArrayObject
    scale: LogicArrayObject
    i_clk: LogicObject
    i_rst: LogicObject
    o_hs: LogicObject
    o_vs: LogicObject
    o_vsync: LogicObject
    o_vblank: LogicObject
    o_visible: LogicObject
    o_image: LogicObject
    o_fb_x: LogicArrayObject
    o_fb_y: LogicArrayObject


class DpramDut(Protocol):
    """Sinais da memória de duas portas."""

    i_wclk: LogicObject
    i_we: LogicArrayObject
    i_waddr: LogicArrayObject
    i_wdata: LogicArrayObject
    i_rclk: LogicObject
    i_raddr: LogicArrayObject
    o_rdata: LogicArrayObject


class RegsDut(Protocol):
    """Sinais dos registradores do lado do processador."""

    channel_bits: LogicArrayObject
    i_clk: LogicObject
    i_rst: LogicObject
    i_data_in: LogicArrayObject
    i_address: LogicArrayObject
    i_byteena: LogicArrayObject
    i_write: LogicObject
    o_data_out: LogicArrayObject
    i_vsync: LogicObject
    i_vblank: LogicObject
    o_enable: LogicObject
    o_wdata: LogicArrayObject
    o_fb_we: LogicArrayObject
    o_fb_addr: LogicArrayObject
    o_pal_we: LogicObject
    o_pal_addr: LogicArrayObject


class ScanoutDut(Protocol):
    """Sinais do caminho de pixel."""

    fb_width: LogicArrayObject
    fb_height: LogicArrayObject
    channel_bits: LogicArrayObject
    i_clk: LogicObject
    i_enable: LogicObject
    i_hs: LogicObject
    i_vs: LogicObject
    i_visible: LogicObject
    i_image: LogicObject
    i_fb_x: LogicArrayObject
    i_fb_y: LogicArrayObject
    o_fb_addr: LogicArrayObject
    i_fb_data: LogicArrayObject
    o_pal_addr: LogicArrayObject
    i_pal_data: LogicArrayObject
    o_color: LogicArrayObject
    o_lit: LogicObject
    o_visible: LogicObject
    o_hs: LogicObject
    o_vs: LogicObject


class VgaDut(Protocol):
    """Sinais do backend VGA."""

    channel_bits: LogicArrayObject
    h_sync_positive: LogicObject
    v_sync_positive: LogicObject
    i_clk: LogicObject
    i_rst: LogicObject
    i_color: LogicArrayObject
    i_lit: LogicObject
    i_visible: LogicObject
    i_hs: LogicObject
    i_vs: LogicObject
    o_r: LogicArrayObject
    o_g: LogicArrayObject
    o_b: LogicArrayObject
    o_hs: LogicObject
    o_vs: LogicObject
    o_blank_n: LogicObject
    o_sync_n: LogicObject

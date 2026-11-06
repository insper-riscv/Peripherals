-- =============================================================================
-- Testbench do seg_display sem dígito (digits zero)
--
-- O cocotb não enxerga portas de largura zero. Este testbench liga o
-- seg_display com digits zero e mostra por portas escalares o que o módulo faz:
-- a palavra lida (sempre zero), o comprimento dos segmentos e do valor, e o
-- bit de passagem da cadeia JTAG.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity seg_display_zero_tb is
  port (
    -- Clock do core.
    i_clk      : in  std_logic;
    -- Reset síncrono, ativo em '1'.
    i_rst      : in  std_logic;
    -- Dado escrito pelo core.
    i_wdata    : in  std_logic_vector(31 downto 0);
    -- Pulso de escrita do core.
    i_we       : in  std_logic;
    -- Dado lido pelo core.
    o_rdata    : out std_logic_vector(31 downto 0);
    -- Comprimento dos segmentos, que deve ser zero.
    o_hex_len  : out natural;
    -- Comprimento do valor, que deve ser zero.
    o_value_len : out natural
  );
end entity seg_display_zero_tb;

architecture rtl of seg_display_zero_tb is
  -- Segmentos sem bits.
  signal hex   : std_logic_vector(-1 downto 0);
  -- Valor sem bits.
  signal value : std_logic_vector(-1 downto 0);
begin
  u_dut : entity work.seg_display
    generic map (digits => 0)
    port map (
      i_clk       => i_clk,
      i_rst       => i_rst,
      i_addr      => (others => '0'),
      i_wdata     => i_wdata,
      i_we        => i_we,
      i_re        => '0',
      o_rdata     => o_rdata,
      i_tck       => '0',
      i_tdi       => '0',
      o_tdo       => open,
      i_ir_in     => "00",
      i_state_cdr => '0',
      i_state_sdr => '0',
      i_state_udr => '0',
      i_state_uir => '0',
      o_value     => value,
      o_fail      => open,
      o_hex       => hex
    );

  o_hex_len   <= hex'length;
  o_value_len <= value'length;
end architecture rtl;

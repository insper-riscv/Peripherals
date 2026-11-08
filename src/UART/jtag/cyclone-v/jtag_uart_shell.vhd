-- =============================================================================
-- Instância do Virtual JTAG da UART sobre JTAG
--
-- Exclusiva da placa: precisa do sld_virtual_jtag da Intel, então não é analisada
-- em simulação, onde o testbench faz o papel da instância e conduz o jtag_uart
-- diretamente. O hospedeiro vê uma segunda instância ao lado da porta de debug da
-- SDRAM, com registrador de instrução de 2 bits; a instrução 1 seleciona o
-- registrador de 48 bits do jtag_uart.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity jtag_uart_shell is
  port (
    -- Clock do módulo.
    i_clk     : in  std_logic;
    -- Reset, ativo em '1'.
    i_rst     : in  std_logic;
    -- Endereço do acesso.
    i_addr    : in  std_logic_vector(7 downto 0);
    -- Dado de escrita.
    i_wdata   : in  std_logic_vector(31 downto 0);
    -- Escrita ('1') ou leitura ('0').
    i_we      : in  std_logic;
    -- Leitura ('1').
    i_re      : in  std_logic;
    -- Dado lido.
    o_rdata   : out std_logic_vector(31 downto 0);
    -- Requisição de interrupção de nível da UART.
    o_irq     : out std_logic
  );
end entity jtag_uart_shell;

architecture rtl of jtag_uart_shell is

  -- Clock da cadeia JTAG.
  signal tck : std_logic;
  -- Dado serial vindo do hospedeiro.
  signal tdi : std_logic;
  -- Dado serial para o hospedeiro.
  signal tdo : std_logic;
  -- Registrador de instrução do Virtual JTAG.
  signal ir_in         : std_logic_vector(1 downto 0);
  -- Estado Capture-DR da cadeia virtual.
  signal st_cdr : std_logic;
  -- Estado Shift-DR da cadeia virtual.
  signal st_sdr : std_logic;
  -- Estado Update-DR da cadeia virtual.
  signal st_udr : std_logic;
  -- Estado Update-IR da cadeia virtual.
  signal st_uir : std_logic;

begin

  u_vjtag : entity work.virtual_jtag
    generic map (
      instance_index => 1,
      auto_instance_index => "NO",
      ir_width => 2
    )
    port map (
      o_tck => tck, o_tdi => tdi, i_tdo => tdo, o_ir_in => ir_in,
      o_state_cdr => st_cdr, o_state_sdr => st_sdr, o_state_udr => st_udr, o_state_uir => st_uir
    );

  u_uart : entity work.jtag_uart
    port map (
      i_clk => i_clk, i_rst => i_rst, i_addr => i_addr, i_wdata => i_wdata, i_we => i_we, i_re => i_re, o_rdata => o_rdata, o_irq => o_irq,
      i_tck => tck, i_tdi => tdi, o_tdo => tdo, i_ir_in => ir_in,
      i_state_cdr => st_cdr, i_state_sdr => st_sdr, i_state_udr => st_udr, i_state_uir => st_uir
    );

end architecture rtl;

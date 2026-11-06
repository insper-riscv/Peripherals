-- =============================================================================
-- Testbench da célula de GPIO com o pino acessível ao cocotb
--
-- O pino da célula é uma porta inout, que o cocotb não consegue conduzir
-- diretamente. i_pin_drive e i_pin_drive_en fazem o papel do mundo externo (um
-- driver solto em 'Z' quando a habilitação é '0'); o_pin mostra o que o pino
-- resolve.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity gpio_cell_tb is
  port (
    -- Clock do módulo.
    i_clk          : in  std_logic;
    -- Reset, ativo em '1'.
    i_rst          : in  std_logic;
    -- Dado de 1 bit vindo do processador.
    i_data_in      : in  std_logic;
    -- Estado interno lido pelo processador, um bit por registrador.
    o_data_out     : out std_logic_vector(7 downto 0);
    -- Habilitações de escrita dos registradores.
    i_wr_signals   : in  std_logic_vector(7 downto 0);
    -- Operação de saída: 00 carrega, 01 liga, 10 limpa, 11 inverte.
    i_wr_op        : in  std_logic_vector(1 downto 0);
    -- Valor que o mundo externo coloca no pino.
    i_pin_drive    : in  std_logic;
    -- O mundo externo dirige o pino ('1') ou o solta em 'Z' ('0').
    i_pin_drive_en : in  std_logic;
    -- Valor resolvido do pino.
    o_pin          : out std_logic
  );
end entity gpio_cell_tb;

architecture rtl of gpio_cell_tb is
  -- Pino da célula, resolvido entre a célula e o mundo externo.
  signal pin : std_logic;
begin
  pin   <= i_pin_drive when i_pin_drive_en = '1' else 'Z';
  o_pin <= pin;

  u_dut : entity work.gpio_cell
    port map (
      i_clk        => i_clk,
      i_rst        => i_rst,
      i_data_in    => i_data_in,
      o_data_out   => o_data_out,
      i_wr_signals => i_wr_signals,
      i_wr_op      => i_wr_op,
      io_gpio_pin  => pin
    );
end architecture rtl;

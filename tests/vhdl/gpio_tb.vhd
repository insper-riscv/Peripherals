-- =============================================================================
-- Testbench do gpio com os pinos acessíveis ao cocotb
--
-- Os pinos do gpio são uma porta inout, que o cocotb não consegue conduzir
-- diretamente. i_pin_drive e i_pin_drive_en fazem o papel do mundo externo (um
-- driver por pino, solto em 'Z' quando a habilitação é '0'); o_pins mostra o
-- que os pinos resolvem.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity gpio_tb is
  generic (
    -- Largura do barramento de dados e número de pinos.
    data_width : natural := 8
  );
  port (
    -- Clock do módulo.
    i_clk          : in  std_logic;
    -- Reset, ativo em '1'.
    i_rst          : in  std_logic;
    -- Dado de escrita vindo do processador.
    i_data_in      : in  std_logic_vector(data_width - 1 downto 0);
    -- Endereço de palavra acessado pelo processador.
    i_address      : in  std_logic_vector(3 downto 0);
    -- Pulso de escrita do processador ('1' = escreve).
    i_write        : in  std_logic;
    -- Pulso de leitura do processador ('1' = lê).
    i_read         : in  std_logic;
    -- Dado de leitura para o processador.
    o_data_out     : out std_logic_vector(data_width - 1 downto 0);
    -- Requisição de interrupção, ativa em '1'.
    o_irq          : out std_logic;
    -- Valor que o mundo externo coloca em cada pino.
    i_pin_drive    : in  std_logic_vector(data_width - 1 downto 0);
    -- O mundo externo dirige o pino ('1') ou o solta em 'Z' ('0').
    i_pin_drive_en : in  std_logic_vector(data_width - 1 downto 0);
    -- Valor resolvido de cada pino.
    o_pins         : out std_logic_vector(data_width - 1 downto 0)
  );
end entity gpio_tb;

architecture rtl of gpio_tb is
  -- Pinos do gpio, resolvidos entre o gpio e o mundo externo.
  signal gpio_pins : std_logic_vector(data_width - 1 downto 0);
begin
  gen_drivers : for i in 0 to data_width - 1 generate
    gpio_pins(i) <= i_pin_drive(i) when i_pin_drive_en(i) = '1' else 'Z';
  end generate;

  o_pins <= gpio_pins;

  u_dut : entity work.gpio
    generic map (data_width => data_width)
    port map (
      i_clk        => i_clk,
      i_rst        => i_rst,
      i_data_in    => i_data_in,
      i_address    => i_address,
      i_write      => i_write,
      i_read       => i_read,
      o_data_out   => o_data_out,
      o_irq        => o_irq,
      io_gpio_pins => gpio_pins
    );
end architecture rtl;

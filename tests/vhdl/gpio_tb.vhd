-- Test wrapper of GPIO: the pins are an inout port, which cocotb cannot drive
-- directly. pin_drive/pin_drive_en act as the outside world (a driver per pin,
-- released with 'Z' when its enable is 0); pins shows what the pins resolve to.
library ieee;
use ieee.std_logic_1164.all;

entity gpio_tb is
  generic (data_width : natural := 8);
  port (
    i_clk        : in  std_logic;
    i_rst        : in  std_logic;
    i_data_in      : in  std_logic_vector(data_width - 1 downto 0);
    i_address      : in  std_logic_vector(3 downto 0);
    i_write        : in  std_logic;
    i_read         : in  std_logic;
    o_data_out     : out std_logic_vector(data_width - 1 downto 0);
    o_irq          : out std_logic;
    i_pin_drive    : in  std_logic_vector(data_width - 1 downto 0);
    i_pin_drive_en : in  std_logic_vector(data_width - 1 downto 0);
    o_pins         : out std_logic_vector(data_width - 1 downto 0)
  );
end entity gpio_tb;

architecture tb of gpio_tb is
  signal gpio_pins : std_logic_vector(data_width - 1 downto 0);
begin
  drivers : for i in 0 to data_width - 1 generate
    gpio_pins(i) <= i_pin_drive(i) when i_pin_drive_en(i) = '1' else 'Z';
  end generate;

  o_pins <= gpio_pins;

  dut : entity work.gpio
    generic map (data_width => data_width)
    port map (
      i_clk     => i_clk,
      i_rst     => i_rst,
      i_data_in   => i_data_in,
      i_address   => i_address,
      i_write     => i_write,
      i_read      => i_read,
      o_data_out  => o_data_out,
      o_irq       => o_irq,
      io_gpio_pins => gpio_pins
    );
end architecture tb;

-- Test wrapper of GPIO: the pins are an inout port, which cocotb cannot drive
-- directly. pin_drive/pin_drive_en act as the outside world (a driver per pin,
-- released with 'Z' when its enable is 0); pins shows what the pins resolve to.
library ieee;
use ieee.std_logic_1164.all;

entity gpio_tb is
  generic (DATA_WIDTH : natural := 8);
  port (
    clock        : in  std_logic;
    clear        : in  std_logic;
    data_in      : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    address      : in  std_logic_vector(3 downto 0);
    write        : in  std_logic;
    read         : in  std_logic;
    data_out     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    irq          : out std_logic;
    pin_drive    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    pin_drive_en : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    pins         : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity gpio_tb;

architecture tb of gpio_tb is
  signal gpio_pins : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
  drivers : for i in 0 to DATA_WIDTH - 1 generate
    gpio_pins(i) <= pin_drive(i) when pin_drive_en(i) = '1' else 'Z';
  end generate;

  pins <= gpio_pins;

  dut : entity work.GPIO
    generic map (DATA_WIDTH => DATA_WIDTH)
    port map (
      clock     => clock,
      clear     => clear,
      data_in   => data_in,
      address   => address,
      write     => write,
      read      => read,
      data_out  => data_out,
      irq       => irq,
      gpio_pins => gpio_pins
    );
end architecture tb;

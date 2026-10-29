-- =============================================================================
-- Entity: CLOCK_PRESCALER
-- Description:
--   Generates a 1-cycle tick when the internal counter reaches a configurable
--   prescaler value. The counter resets after each tick. Fully modular structure.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity clock_prescaler is
  generic (
    data_width : integer := 32 -- Width of the counter
  );
  port (
    i_clk        : in  std_logic;                                -- System clock
    i_rst        : in  std_logic;                                -- Asynchronous clear
    i_prescaler_in : in  std_logic_vector(data_width-1 downto 0);  -- Prescaler value (from register)
    o_tick         : out std_logic                                 -- One-cycle tick when counter matches prescaler
  );
end entity;

architecture rtl of clock_prescaler is
  signal counter       : std_logic_vector(data_width-1 downto 0); -- Prescaler counter
  signal next_counter  : std_logic_vector(data_width-1 downto 0); -- Incremented counter
  signal comp_result   : std_logic;                               -- Comparison result (counter >= prescaler)
  signal tick_out      : std_logic;                               -- 1-cycle pulse
  -- Port-map actual as a signal: GHDL requires a name or a globally static
  -- expression there.
  signal counter_clear : std_logic;

  -- Constante 1 usada como segundo operando do somador U_ADDER.
  constant U_ADDER_ONE : std_logic_vector(data_width - 1 downto 0) := std_logic_vector(to_unsigned(1, data_width));

begin

  counter_clear <= i_rst or comp_result;

  ---------------------------------------------------------------------------
  -- Compare counter >= prescaler_in
  ---------------------------------------------------------------------------
  u_ge : entity work.alu_ge_unsigned
    generic map (data_width => data_width)
    port map (
      i_source_1 => counter,
      i_source_2 => i_prescaler_in,
      o_ge       => comp_result
    );

  ---------------------------------------------------------------------------
  -- next_counter = counter + 1
  ---------------------------------------------------------------------------
  u_adder : entity work.adder
    generic map (
      data_width => data_width
    )
    port map (
      i_a => counter,
      i_b => U_ADDER_ONE,
      o_d => next_counter
    );

  ---------------------------------------------------------------------------
  -- Counter Register
  -- Clears to 0 when tick fires
  ---------------------------------------------------------------------------
  u_counter : entity work.clearable_register
    generic map (
      data_width => data_width
    )
    port map (
      i_clk    => i_clk,
      i_clear  => counter_clear,
      i_enable => '1',
      i_d      => next_counter,
      o_d      => counter
    );

  ---------------------------------------------------------------------------
  -- Tick Flip-Flop (1-cycle pulse)
  ---------------------------------------------------------------------------
  u_tick_ff : entity work.flip_flop
    port map (
      i_clk    => i_clk,
      i_rst    => i_rst,
      i_enable => '1',         -- Same gating
      i_d      => comp_result,
      o_d      => tick_out
    );

  o_tick <= tick_out; -- Output pulse

end architecture;


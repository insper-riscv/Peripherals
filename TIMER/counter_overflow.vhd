-- =============================================================================
-- Entity: COUNTER_OVERFLOW
-- Description:
--   Pure-combinational “overflow unit” for an unsigned timer / counter.
--   Asserts overflow = '1' when the counter reaches or exceeds the top value.
--   The overflow flag is a combinational pulse that is cleared on the next read.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

-- -----------------------------------------------------------------------------
-- Entity Declaration
-- -----------------------------------------------------------------------------
entity counter_overflow is
  generic (
    --! Data width of the counter (in bits)
    data_width : natural := 32
  );
  port (
    -- -------------------------------------------------------------------------
    -- Counter interface
    -- -------------------------------------------------------------------------
    i_counter_value : in  std_logic_vector(data_width-1 downto 0); -- Present count
    i_top_value     : in  std_logic_vector(data_width-1 downto 0); -- Terminal count

    -- -------------------------------------------------------------------------
    -- Overflow flag (combinational pulse)
    -- -------------------------------------------------------------------------
    o_overflow      : out std_logic -- overflow flag (active high)
  );
end entity counter_overflow;

-- -----------------------------------------------------------------------------
-- Architecture Definition
-- -----------------------------------------------------------------------------
architecture rtl of counter_overflow is

  -- Internal comparator signal
  signal cnt_ge_top : std_logic; -- counter_value ≥ top_value

begin
  -----------------------------------------------------------------------------
  -- GREATER-OR-EQUAL COMPARATOR
  -----------------------------------------------------------------------------
  u_ge_counter_top : entity work.alu_ge_unsigned
    generic map ( data_width => data_width )
    port map (
      i_source_1 => i_counter_value,   -- A
      i_source_2 => i_top_value,       -- B
      o_ge       => cnt_ge_top       -- A ≥ B
    );

  -----------------------------------------------------------------------------
  -- OVERFLOW FLAG = counter ≥ top
  -----------------------------------------------------------------------------
  o_overflow <= cnt_ge_top;

end architecture rtl;


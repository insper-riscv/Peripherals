-- =============================================================================
--  File:        alu_ge_unsigned.vhd
--  Description: Unsigned "greater-or-equal" comparator that outputs one bit
--               (ge = '1' when source_1 ≥ source_2). Pure combinational
--               gate logic; no use of built‑in adders or numeric_std.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

-- ============================================================================
--  Entity Declaration
-- ============================================================================
entity alu_ge_unsigned is
  generic (
    data_width : natural := 32  --! Operand width
  );
  port (
    i_source_1 : in  std_logic_vector(data_width-1 downto 0);
    i_source_2 : in  std_logic_vector(data_width-1 downto 0);
    o_ge       : out std_logic  --! '1' when source_1 ≥ source_2 (unsigned)
  );
end entity alu_ge_unsigned;

-- ============================================================================
--  Architecture (combinational – borrow detection via ripple adder)
-- ============================================================================
architecture rtl of alu_ge_unsigned is
  signal b_inv : std_logic_vector(data_width-1 downto 0);  -- ¬B
  signal c     : std_logic_vector(data_width downto 0);    -- ripple carry/borrow
begin
  -----------------------------------------------------------------------------
  -- Pre-invert B and seed carry(0)=1 to form A + (¬B) + 1 (two's complement)
  -----------------------------------------------------------------------------
  b_inv <= not i_source_2;
  c(0)  <= '1';
  
  -----------------------------------------------------------------------------
  -- Ripple subtractor: generate/propagate borrow bit-by-bit
  -----------------------------------------------------------------------------
  gen_ripple: for i in 0 to data_width-1 generate
    c(i+1) <= (i_source_1(i) and b_inv(i))              -- generate borrow
            or ((i_source_1(i) xor b_inv(i)) and c(i)); -- propagate borrow
  end generate;

  -----------------------------------------------------------------------------
  -- No borrow means A ≥ B → ge = c(DATA_WIDTH)
  -----------------------------------------------------------------------------
  o_ge <= c(data_width);
end architecture rtl;

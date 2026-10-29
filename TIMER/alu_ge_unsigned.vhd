-- =============================================================================
-- Comparador sem sinal "maior ou igual"
--
-- Produz um bit, ge = '1' quando source_1 >= source_2. É lógica puramente
-- combinacional de portas, sem somadores prontos nem numeric_std: o comparador é
-- o vai-um de uma subtração em cadeia.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity alu_ge_unsigned is
  generic (
    -- Largura dos operandos em bits.
    data_width : natural := 32
  );
  port (
    -- Primeiro operando.
    i_source_1 : in  std_logic_vector(data_width-1 downto 0);
    -- Segundo operando.
    i_source_2 : in  std_logic_vector(data_width-1 downto 0);
    -- '1' quando i_source_1 >= i_source_2 (sem sinal).
    o_ge       : out std_logic
  );
end entity alu_ge_unsigned;

-- ============================================================================
--  Architecture (combinational – borrow detection via ripple adder)
-- ============================================================================
architecture rtl of alu_ge_unsigned is
  -- Segundo operando invertido.
  signal b_inv : std_logic_vector(data_width-1 downto 0);
  -- Vai-um da cadeia de subtração.
  signal c     : std_logic_vector(data_width downto 0);
begin
  -----------------------------------------------------------------------------
  -- Inverte B e semeia carry(0) = 1 para formar A + (¬B) + 1 (complemento de dois)
  -----------------------------------------------------------------------------
  b_inv <= not i_source_2;
  c(0)  <= '1';
  
  -----------------------------------------------------------------------------
  -- Subtrator em cadeia: gera e propaga o empréstimo bit a bit
  -----------------------------------------------------------------------------
  gen_ripple: for i in 0 to data_width-1 generate
    c(i+1) <= (i_source_1(i) and b_inv(i))              -- gera empréstimo
            or ((i_source_1(i) xor b_inv(i)) and c(i)); -- propaga empréstimo
  end generate;

  -----------------------------------------------------------------------------
  -- Sem empréstimo, A ≥ B: ge = c(data_width)
  -----------------------------------------------------------------------------
  o_ge <= c(data_width);
end architecture rtl;

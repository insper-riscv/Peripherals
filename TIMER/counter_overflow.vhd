-- =============================================================================
-- Unidade de overflow de um contador sem sinal
--
-- Puramente combinacional: afirma o_overflow = '1' quando o contador alcança ou
-- supera o valor de topo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity counter_overflow is
  generic (
    -- Largura do contador em bits.
    data_width : natural := 32
  );
  port (
    -- Contagem atual.
    i_counter_value : in  std_logic_vector(data_width-1 downto 0);
    -- Contagem final (topo).
    i_top_value     : in  std_logic_vector(data_width-1 downto 0);

    -- Overflow ('1' quando a contagem alcança o topo).
    o_overflow      : out std_logic
  );
end entity counter_overflow;

architecture rtl of counter_overflow is

  -- A contagem é maior ou igual ao topo.
  signal cnt_ge_top : std_logic;

begin
  -----------------------------------------------------------------------------
  -- Comparador maior ou igual
  -----------------------------------------------------------------------------
  u_ge_counter_top : entity work.alu_ge_unsigned
    generic map ( data_width => data_width )
    port map (
      i_source_1 => i_counter_value,   -- A
      i_source_2 => i_top_value,       -- B
      o_ge       => cnt_ge_top       -- A ≥ B
    );

  -----------------------------------------------------------------------------
  -- Overflow = contador ≥ topo
  -----------------------------------------------------------------------------
  o_overflow <= cnt_ge_top;

end architecture rtl;


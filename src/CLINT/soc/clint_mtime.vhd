-- =============================================================================
-- Contador mtime de 64 bits em duas metades, com vai-um registrado
--
-- Guarda o valor de 64 bits como metade baixa (o_lo) e metade alta (o_hi). A
-- cada ciclo com i_inc = '1' a metade baixa soma 1; quando ela estava com todos
-- os bits em '1', o vai-um fica registrado e a metade alta soma 1 no ciclo
-- seguinte, de modo que nenhuma soma de 64 bits entra em um caminho
-- combinacional.
--
-- Leitura coerente: no ciclo em que o vai-um está pendente a metade alta
-- armazenada ainda não somou, então o_hi devolve a metade alta mais o vai-um
-- pendente. O par (o_hi, o_lo) é sempre o valor do contador de 64 bits ideal.
--
-- Prioridade da escrita sobre a soma, em cada metade:
--   1. i_we_lo = '1': a metade baixa recebe i_wdata e não há vai-um neste ciclo.
--   2. i_we_hi = '1': a metade alta recebe i_wdata e o vai-um pendente se perde.
--   3. Sem escrita: a metade baixa soma 1 com i_inc = '1' e a alta soma o vai-um.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clint_mtime is
  port (
    -- Clock do módulo.
    i_clk   : in  std_logic;
    -- Reset assíncrono, ativo em '1' (zera as duas metades e o vai-um).
    i_rst   : in  std_logic;
    -- Soma 1 ao contador neste ciclo quando '1'.
    i_inc   : in  std_logic;
    -- Escrita da metade baixa com i_wdata quando '1'.
    i_we_lo : in  std_logic;
    -- Escrita da metade alta com i_wdata quando '1'.
    i_we_hi : in  std_logic;
    -- Valor escrito na metade selecionada.
    i_wdata : in  std_logic_vector(31 downto 0);
    -- Metade baixa do contador.
    o_lo    : out std_logic_vector(31 downto 0);
    -- Metade alta do contador, já com o vai-um pendente somado.
    o_hi    : out std_logic_vector(31 downto 0)
  );
end entity clint_mtime;

architecture rtl of clint_mtime is

  -- Valor da metade baixa que gera o vai-um (todos os bits em '1').
  constant LO_ALL_ONES : std_logic_vector(31 downto 0) := (others => '1');

  -- Metade baixa armazenada.
  signal lo        : std_logic_vector(31 downto 0);
  -- Metade alta armazenada, sem o vai-um pendente.
  signal hi        : std_logic_vector(31 downto 0);
  -- A metade baixa deu a volta no ciclo anterior e a alta ainda não somou.
  signal carry     : std_logic;
  -- Vai-um que a metade baixa gera neste ciclo.
  signal carry_nxt : std_logic;
  -- Metade baixa mais 1.
  signal lo_inc    : std_logic_vector(31 downto 0);
  -- Metade alta mais 1.
  signal hi_inc    : std_logic_vector(31 downto 0);
  -- Próximo valor da metade baixa.
  signal lo_nxt    : std_logic_vector(31 downto 0);
  -- Próximo valor da metade alta.
  signal hi_nxt    : std_logic_vector(31 downto 0);
  -- Habilita a atualização da metade baixa.
  signal lo_en     : std_logic;
  -- Habilita a atualização da metade alta.
  signal hi_en     : std_logic;

begin

  lo_inc <= std_logic_vector(unsigned(lo) + 1);
  hi_inc <= std_logic_vector(unsigned(hi) + 1);

  lo_nxt <= i_wdata when i_we_lo = '1' else lo_inc;
  lo_en  <= i_we_lo or i_inc;

  hi_nxt <= i_wdata when i_we_hi = '1' else hi_inc;
  hi_en  <= i_we_hi or carry;

  carry_nxt <= '1' when (i_inc = '1' and i_we_lo = '0' and lo = LO_ALL_ONES) else '0';

  o_lo <= lo;
  o_hi <= hi_inc when carry = '1' else hi;

  u_lo : entity work.generic_register
    generic map (
      data_width => 32
    )
    port map (
      i_clk    => i_clk,
      i_rst    => i_rst,
      i_enable => lo_en,
      i_d      => lo_nxt,
      o_d      => lo
    );

  u_hi : entity work.generic_register
    generic map (
      data_width => 32
    )
    port map (
      i_clk    => i_clk,
      i_rst    => i_rst,
      i_enable => hi_en,
      i_d      => hi_nxt,
      o_d      => hi
    );

  u_carry : entity work.flip_flop
    port map (
      i_d      => carry_nxt,
      o_d      => carry,
      i_enable => '1',
      i_clk    => i_clk,
      i_rst    => i_rst
    );

end architecture rtl;

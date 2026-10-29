-- =============================================================================
-- Prescaler de relógio
--
-- Gera um tick de um ciclo quando o contador interno chega ao valor configurado
-- do prescaler. O contador zera a cada tick.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity clock_prescaler is
  generic (
    -- Largura do contador em bits.
    data_width : integer := 32
  );
  port (
    -- Clock do módulo.
    i_clk        : in  std_logic;
    -- Reset, ativo em '1'.
    i_rst        : in  std_logic;
    -- Valor do prescaler, vindo do registrador.
    i_prescaler_in : in  std_logic_vector(data_width-1 downto 0);
    -- Tick de um ciclo quando o contador alcança o prescaler.
    o_tick         : out std_logic
  );
end entity;

architecture rtl of clock_prescaler is
  -- Contador do prescaler.
  signal counter       : std_logic_vector(data_width-1 downto 0);
  -- Contador incrementado.
  signal next_counter  : std_logic_vector(data_width-1 downto 0);
  -- Resultado da comparação (contador maior ou igual ao prescaler).
  signal comp_result   : std_logic;
  -- Pulso de um ciclo.
  signal tick_out      : std_logic;
  -- Zera o contador (reset ou tick).
  signal counter_clear : std_logic;

  -- Constante 1, segundo operando do somador.
  constant ADDER_ONE : std_logic_vector(data_width - 1 downto 0) := std_logic_vector(to_unsigned(1, data_width));

begin

  counter_clear <= i_rst or comp_result;

  ---------------------------------------------------------------------------
  -- Compara contador >= i_prescaler_in
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
      i_b => ADDER_ONE,
      o_d => next_counter
    );

  ---------------------------------------------------------------------------
  -- Registrador do contador
  -- Zera quando o tick dispara
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
  -- Flip-flop do tick (pulso de um ciclo)
  ---------------------------------------------------------------------------
  u_tick_ff : entity work.flip_flop
    port map (
      i_clk    => i_clk,
      i_rst    => i_rst,
      i_enable => '1',         -- Mesma habilitação
      i_d      => comp_result,
      o_d      => tick_out
    );

  o_tick <= tick_out; -- Pulso de saída

end architecture;


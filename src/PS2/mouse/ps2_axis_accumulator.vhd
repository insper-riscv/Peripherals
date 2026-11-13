-- =============================================================================
-- Acumulador de deslocamento de um eixo com saturação
--
-- Soma o deslocamento de cada pacote (complemento de dois, delta_width bits)
-- ao valor acumulado (acc_width bits) e satura nos limites do tipo em vez de
-- dar a volta. Prioridade na borda de subida de i_clk:
--   1. i_rst = '1' -> zera o acumulador.
--   2. i_clear = '1' -> zera o acumulador; se i_add_valid = '1' no mesmo ciclo,
--      o acumulador passa a valer o deslocamento novo (a soma não se perde).
--   3. i_add_valid = '1' -> acumulador recebe a soma saturada.
-- A saída o_saturated vale '1' no ciclo em que a soma é cortada no limite.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_axis_accumulator is
    generic (
        -- Largura do acumulador em bits (complemento de dois).
        acc_width   : positive := 16;
        -- Largura do deslocamento somado em bits (complemento de dois).
        delta_width : positive := 9
    );
    port (
        -- Clock do módulo.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst       : in    std_logic;
        -- Zera o acumulador na borda ('1' = zera), usado na leitura do registrador.
        i_clear     : in    std_logic;
        -- Soma o deslocamento i_delta na borda ('1' = soma).
        i_add_valid : in    std_logic;
        -- Deslocamento do pacote em complemento de dois.
        i_delta     : in    std_logic_vector(delta_width - 1 downto 0);
        -- Valor acumulado em complemento de dois.
        o_value     : out   std_logic_vector(acc_width - 1 downto 0);
        -- A soma deste ciclo foi cortada no limite ('1' = saturou).
        o_saturated : out   std_logic
    );
end entity ps2_axis_accumulator;

architecture rtl of ps2_axis_accumulator is

    -- Largura da soma, um bit a mais que o acumulador para detectar o estouro.
    constant SUM_WIDTH : positive := acc_width + 1;

    -- Valor acumulado.
    signal acc      : signed(acc_width - 1 downto 0) := (others => '0');
    -- Base da soma: o acumulador, ou zero quando a leitura o zera no mesmo ciclo.
    signal base     : signed(SUM_WIDTH - 1 downto 0);
    -- Soma sem saturação.
    signal sum      : signed(SUM_WIDTH - 1 downto 0);
    -- Maior valor representável no acumulador.
    signal max_val  : signed(SUM_WIDTH - 1 downto 0);
    -- Menor valor representável no acumulador.
    signal min_val  : signed(SUM_WIDTH - 1 downto 0);
    -- Soma cortada nos limites.
    signal clamped  : signed(acc_width - 1 downto 0);
    -- A soma ultrapassou o limite superior.
    signal over_hi  : std_logic;
    -- A soma ultrapassou o limite inferior.
    signal over_lo  : std_logic;

begin

    max_val <= to_signed(2 ** (acc_width - 1) - 1, SUM_WIDTH);
    min_val <= to_signed(-(2 ** (acc_width - 1)), SUM_WIDTH);
    base    <= (others => '0') when i_clear = '1' else resize(acc, SUM_WIDTH);
    sum     <= base + resize(signed(i_delta), SUM_WIDTH);
    over_hi <= '1' when sum > max_val else '0';
    over_lo <= '1' when sum < min_val else '0';
    clamped <= max_val(acc_width - 1 downto 0) when over_hi = '1' else
               min_val(acc_width - 1 downto 0) when over_lo = '1' else
               sum(acc_width - 1 downto 0);

    o_saturated <= i_add_valid and (over_hi or over_lo);
    o_value     <= std_logic_vector(acc);

    -- Atualização do acumulador conforme a prioridade do cabeçalho.
    p_accumulate : process (i_clk) is
    begin
        if rising_edge(i_clk) then
            if i_rst = '1' then
                acc <= (others => '0');
            elsif i_add_valid = '1' then
                acc <= clamped;
            elsif i_clear = '1' then
                acc <= (others => '0');
            end if;
        end if;
    end process p_accumulate;

end architecture rtl;

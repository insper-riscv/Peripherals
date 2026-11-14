-- =============================================================================
-- Registrador DDR de entrada, modelo comportamental
--
-- Substitui, na simulação, o registrador DDR de entrada do fabricante (arquivo
-- de mesmo nome na pasta altera, que o Quartus usa na placa). Amostra i_d em
-- cada borda de subida e em cada borda de descida de i_clk e entrega, a cada
-- borda de subida, o par da borda anterior: o_q_rise é o dado amostrado na
-- borda de subida, e o_q_fall é o dado amostrado na borda de descida
-- seguinte. A saída tem, portanto, um ciclo de latência e muda só na borda de
-- subida de i_clk. Este arquivo e o de altera nunca entram no mesmo projeto.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity eth_ddr_in is
    generic (
        -- Largura em bits do dado.
        width : positive := 5
    );
    port (
        -- Clock de amostragem nas duas bordas.
        i_clk    : in    std_logic;
        -- Dado do pino.
        i_d      : in    std_logic_vector(width - 1 downto 0);
        -- Dado amostrado na borda de subida.
        o_q_rise : out   std_logic_vector(width - 1 downto 0);
        -- Dado amostrado na borda de descida que segue a de subida.
        o_q_fall : out   std_logic_vector(width - 1 downto 0)
    );
end entity eth_ddr_in;

architecture sim of eth_ddr_in is

    -- Dado amostrado na última borda de subida.
    signal rise_cap : std_logic_vector(width - 1 downto 0) := (others => '0');
    -- Dado amostrado na última borda de descida.
    signal fall_cap : std_logic_vector(width - 1 downto 0) := (others => '0');
    -- Saída da borda de subida.
    signal rise_q   : std_logic_vector(width - 1 downto 0) := (others => '0');
    -- Saída da borda de descida.
    signal fall_q   : std_logic_vector(width - 1 downto 0) := (others => '0');

begin

    p_fall : process (i_clk) is
    begin

        if falling_edge(i_clk) then
            fall_cap <= i_d;
        end if;

    end process p_fall;

    p_rise : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            rise_q   <= rise_cap;
            fall_q   <= fall_cap;
            rise_cap <= i_d;
        end if;

    end process p_rise;

    o_q_rise <= rise_q;
    o_q_fall <= fall_q;

end architecture sim;

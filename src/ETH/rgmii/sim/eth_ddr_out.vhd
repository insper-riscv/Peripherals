-- =============================================================================
-- Registrador DDR de saída, modelo comportamental
--
-- Substitui, na simulação, o registrador DDR de saída do fabricante (arquivo
-- de mesmo nome na pasta altera, que o Quartus usa na placa). Registra i_d_rise
-- e i_d_fall na borda de subida de i_clk e coloca i_d_rise no pino durante a
-- metade alta do clock e i_d_fall durante a metade baixa. Este arquivo e o de
-- altera nunca entram no mesmo projeto.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity eth_ddr_out is
    generic (
        -- Largura em bits do dado.
        width : positive := 5
    );
    port (
        -- Clock da saída, nas duas bordas.
        i_clk    : in    std_logic;
        -- Dado da metade alta do clock.
        i_d_rise : in    std_logic_vector(width - 1 downto 0);
        -- Dado da metade baixa do clock.
        i_d_fall : in    std_logic_vector(width - 1 downto 0);
        -- Dado do pino.
        o_q      : out   std_logic_vector(width - 1 downto 0)
    );
end entity eth_ddr_out;

architecture sim of eth_ddr_out is

    -- Dado registrado para a metade baixa.
    signal fall_reg : std_logic_vector(width - 1 downto 0) := (others => '0');
    -- Dado do pino, trocado só nas bordas do clock.
    signal pin      : std_logic_vector(width - 1 downto 0) := (others => '0');

begin

    p_reg : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            pin      <= i_d_rise;
            fall_reg <= i_d_fall;
        elsif falling_edge(i_clk) then
            pin <= fall_reg;
        end if;

    end process p_reg;

    o_q <= pin;

end architecture sim;

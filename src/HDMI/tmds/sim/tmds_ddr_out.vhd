-- =============================================================================
-- Registrador DDR de saída do transmissor TMDS, modelo comportamental
--
-- Substitui, na simulação, o registrador DDR de saída do fabricante (arquivo
-- de mesmo nome na pasta altera, que o Quartus usa na placa). Registra i_d_h e
-- i_d_l na borda de subida de i_clk e coloca i_d_h no pino durante a metade
-- alta do clock e i_d_l durante a metade baixa. Este arquivo e o de altera
-- nunca entram no mesmo projeto.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity tmds_ddr_out is
    generic (
        -- Largura em bits do dado.
        width         : positive := 4;
        -- Família da FPGA, ignorada no modelo.
        device_family : string   := "Cyclone 10 LP"
    );
    port (
        -- Clock da saída, nas duas bordas.
        i_clk : in    std_logic;
        -- Dado da metade alta do clock.
        i_d_h : in    std_logic_vector(width - 1 downto 0);
        -- Dado da metade baixa do clock.
        i_d_l : in    std_logic_vector(width - 1 downto 0);
        -- Dado do pino.
        o_q   : out   std_logic_vector(width - 1 downto 0)
    );
end entity tmds_ddr_out;

architecture sim of tmds_ddr_out is

    -- Dado registrado para a metade baixa.
    signal low_reg : std_logic_vector(width - 1 downto 0) := (others => '0');
    -- Dado do pino, trocado só nas bordas do clock.
    signal pin     : std_logic_vector(width - 1 downto 0) := (others => '0');

begin

    p_reg : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            pin     <= i_d_h;
            low_reg <= i_d_l;
        elsif falling_edge(i_clk) then
            pin <= low_reg;
        end if;

    end process p_reg;

    o_q <= pin;

end architecture sim;

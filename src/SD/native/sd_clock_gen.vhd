-- ==========================================================================
-- Gerador do clock do cartão SD com pulsos de borda
-- ==========================================================================
-- Gera SD_CLK a partir de i_clk com meio período de (divisor + 1) ciclos, ou
-- seja, f(SD_CLK) = f(i_clk) / (2 * (divisor + 1)). O clock só sobe quando
-- i_run vale 1; sem pedido ele termina o nível alto em curso e fica em nível
-- baixo. Os pulsos o_rise e o_fall duram um ciclo e valem no ciclo em que a
-- borda correspondente de SD_CLK acontece no fim do ciclo, de modo que os
-- circuitos que os usam como habilitação mudam de estado junto com a borda.
-- Os dados saem na borda de descida (o cartão amostra na subida, meio período
-- depois) e entram na borda de subida (o cartão os apresentou na subida
-- anterior). Com o contador parado em repouso, a primeira subida acontece
-- depois de um meio período inteiro do pedido.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_clock_gen is
    generic (
        -- Largura do divisor, em bits.
        divider_width : positive := 16
    );
    port (
        -- Clock do módulo.
        i_clk     : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst     : in    std_logic;
        -- Meio período de SD_CLK menos um, em ciclos de i_clk.
        i_divider : in    std_logic_vector(divider_width - 1 downto 0);
        -- Pedido de clock; sem ele SD_CLK fica em nível baixo.
        i_run     : in    std_logic;
        -- Clock do cartão.
        o_sclk    : out   std_logic;
        -- Pulso de um ciclo que antecede a borda de subida de SD_CLK.
        o_rise    : out   std_logic;
        -- Pulso de um ciclo que antecede a borda de descida de SD_CLK.
        o_fall    : out   std_logic
    );
end entity sd_clock_gen;

architecture rtl of sd_clock_gen is

    -- Nível atual de SD_CLK.
    signal sclk  : std_logic;
    -- Ciclos já contados na metade atual do período.
    signal count : unsigned(divider_width - 1 downto 0);
    -- Indica que a metade atual do período terminou.
    signal tick  : std_logic;

begin

    o_sclk <= sclk;
    tick   <= '1' when count >= unsigned(i_divider) else '0';
    o_rise <= tick and i_run and not sclk;
    o_fall <= tick and sclk;

    p_clock : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                sclk  <= '0';
                count <= (others => '0');
            elsif sclk = '0' and i_run = '0' then
                count <= (others => '0');
            elsif tick = '1' then
                count <= (others => '0');
                sclk  <= not sclk;
            else
                count <= count + 1;
            end if;
        end if;

    end process p_clock;

end architecture rtl;

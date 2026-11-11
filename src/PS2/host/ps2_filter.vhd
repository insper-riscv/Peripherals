-- ==========================================================================
-- Filtro de glitch de uma linha PS/2
-- ==========================================================================
-- Recebe uma linha já sincronizada ao clock do sistema e só repete na saída
-- um novo nível depois que a entrada o manteve por filter_cycles ciclos
-- seguidos. Pulsos mais curtos que isso são descartados. No reset a saída
-- vale '1', o nível de repouso das linhas PS/2.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ps2_filter is
    generic (
        -- Quantidade de ciclos de clock que um nível precisa durar para ser aceito.
        filter_cycles : positive := 8
    );
    port (
        -- Clock do módulo.
        i_clk   : in    std_logic;
        -- Reset, ativo em nível baixo.
        i_rst_n : in    std_logic;
        -- Linha sincronizada ao clock.
        i_d     : in    std_logic;
        -- Linha filtrada.
        o_d     : out   std_logic
    );
end entity ps2_filter;

architecture rtl of ps2_filter is

    -- Nível atualmente aceito.
    signal level : std_logic;
    -- Quantidade de ciclos seguidos em que a entrada difere do nível aceito.
    signal count : natural range 0 to filter_cycles;

begin

    o_d <= level;

    p_filter : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst_n = '0' then
                level <= '1';
                count <= 0;
            elsif i_d = level then
                count <= 0;
            elsif count = filter_cycles - 1 then
                level <= i_d;
                count <= 0;
            else
                count <= count + 1;
            end if;
        end if;

    end process p_filter;

end architecture rtl;

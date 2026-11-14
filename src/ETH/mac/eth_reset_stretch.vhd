-- =============================================================================
-- Alongador de reset
--
-- Mantém o_rst em '1' por cycles ciclos de i_clk depois que i_rst deixa de
-- valer, para que os domínios de clock lentos do MAC (RX_CLK e TX_CLK do PHY)
-- enxerguem um reset longo o bastante depois de sincronizado. Também vale '1'
-- nos primeiros ciclos depois da configuração do FPGA.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity eth_reset_stretch is
    generic (
        -- Ciclos de i_clk que o reset dura depois de i_rst.
        cycles : positive := 64
    );
    port (
        -- Clock do domínio.
        i_clk : in    std_logic;
        -- Pedido de reset, ativo em '1'.
        i_rst : in    std_logic;
        -- Reset alongado, ativo em '1'.
        o_rst : out   std_logic
    );
end entity eth_reset_stretch;

architecture rtl of eth_reset_stretch is

    -- Ciclos que ainda faltam para soltar o reset.
    signal remaining : natural range 0 to cycles := cycles;

begin

    p_count : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                remaining <= cycles;
            elsif remaining > 0 then
                remaining <= remaining - 1;
            end if;
        end if;

    end process p_count;

    o_rst <= '1' when remaining > 0 else '0';

end architecture rtl;

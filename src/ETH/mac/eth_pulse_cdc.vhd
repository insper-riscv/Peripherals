-- =============================================================================
-- Travessia de um pulso entre dois domínios de clock
--
-- O pulso de i_pulse (um ciclo de i_src_clk) inverte um flip-flop de toggle no
-- domínio de origem; o toggle atravessa por um sincronizador e cada inversão
-- vira um pulso de um ciclo em o_pulse no domínio de destino. Dois pulsos de
-- origem precisam ficar separados por mais ciclos de i_src_clk do que o
-- destino leva para enxergar o toggle (sync_stages + 1 ciclos de i_dst_clk).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity eth_pulse_cdc is
    generic (
        -- Estágios do sincronizador.
        sync_stages : positive := 2
    );
    port (
        -- Clock do domínio de origem.
        i_src_clk : in    std_logic;
        -- Reset síncrono do domínio de origem.
        i_src_rst : in    std_logic;
        -- Pulso de um ciclo no domínio de origem.
        i_pulse   : in    std_logic;
        -- Clock do domínio de destino.
        i_dst_clk : in    std_logic;
        -- Reset síncrono do domínio de destino.
        i_dst_rst : in    std_logic;
        -- Pulso de um ciclo no domínio de destino.
        o_pulse   : out   std_logic
    );
end entity eth_pulse_cdc;

architecture rtl of eth_pulse_cdc is

    -- Toggle do domínio de origem.
    signal toggle      : std_logic := '0';
    -- Toggle sincronizado no destino, em vetor de um bit.
    signal toggle_sync : std_logic_vector(0 downto 0);
    -- Valor do toggle sincronizado no ciclo anterior.
    signal toggle_prev : std_logic := '0';

begin

    p_toggle : process (i_src_clk) is
    begin

        if rising_edge(i_src_clk) then
            if i_src_rst = '1' then
                toggle <= '0';
            elsif i_pulse = '1' then
                toggle <= not toggle;
            end if;
        end if;

    end process p_toggle;

    u_sync : entity work.synchronizer
        generic map (
            stages     => sync_stages,
            data_width => 1
        )
        port map (
            i_clk => i_dst_clk,
            i_rst => i_dst_rst,
            i_d(0) => toggle,
            o_d   => toggle_sync
        );

    p_edge : process (i_dst_clk) is
    begin

        if rising_edge(i_dst_clk) then
            if i_dst_rst = '1' then
                toggle_prev <= '0';
            else
                toggle_prev <= toggle_sync(0);
            end if;
        end if;

    end process p_edge;

    o_pulse <= toggle_sync(0) xor toggle_prev;

end architecture rtl;

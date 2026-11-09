-- =============================================================================
-- Gateway de uma fonte do PLIC
--
-- Converte a linha de nível de uma fonte em no máximo um pedido pendente por
-- vez. Quando a linha vale '1' e a fonte não está em atendimento, o pedido fica
-- pendente e a fonte passa a ser mascarada. O claim limpa o pendente e a fonte
-- continua mascarada até o complete, mesmo que a linha continue em '1'. Depois
-- do complete, uma linha ainda em '1' gera um novo pedido no ciclo seguinte.
-- O pendente não cai quando a linha cai: só o claim o limpa.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity plic_gateway is
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Linha de interrupção de nível da fonte, ativa em '1'.
        i_source   : in    std_logic;
        -- Pulso de claim desta fonte ('1' = o handler reclamou o pedido).
        i_claim    : in    std_logic;
        -- Pulso de complete desta fonte ('1' = o handler terminou).
        i_complete : in    std_logic;
        -- Pedido pendente da fonte.
        o_pending  : out   std_logic
    );
end entity plic_gateway;

architecture rtl of plic_gateway is

    -- Bit de pendente.
    signal pending  : std_logic := '0';
    -- Fonte em atendimento (mascarada) entre o pedido e o complete.
    signal inflight : std_logic := '0';

begin

    p_gateway : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                pending  <= '0';
                inflight <= '0';
            else
                if i_claim = '1' then
                    pending <= '0';
                end if;
                if i_complete = '1' then
                    inflight <= '0';
                end if;
                if i_source = '1' and inflight = '0' then
                    pending  <= '1';
                    inflight <= '1';
                end if;
            end if;
        end if;

    end process p_gateway;

    o_pending <= pending;

end architecture rtl;

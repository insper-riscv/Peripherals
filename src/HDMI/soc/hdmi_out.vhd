-- =============================================================================
-- Registrador de saída para o transmissor HDMI
--
-- Domínio do clock de pixel. Recebe a cor de 24 bits, os sincronismos já com a
-- polaridade do modo e as marcas de área visível e de imagem acesa, e entrega
-- o barramento de vídeo paralelo RGB 4:4:4 (vermelho nos bits 23:16, verde nos
-- 15:8 e azul nos 7:0), DE, HS e VS em um registrador de saída, sem lógica
-- depois dele. DE vale '1' em toda a área visível do modo; fora da imagem
-- acesa (i_lit = '0') o barramento de cor vale zero (preto).
--
-- Prioridade: i_rst = '1' (síncrono) leva as saídas ao repouso (cor preta, DE
-- baixo e sincronismos fora do pulso, no nível oposto ao da polaridade).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.utils_pkg.all;
use work.hdmi_consts.all;

entity hdmi_out is
    generic (
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive : boolean := false;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive : boolean := false
    );
    port (
        -- Clock de pixel.
        i_clk     : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1'.
        i_rst     : in    std_logic;

        -- Cor de 24 bits do pixel.
        i_color   : in    std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);
        -- A cor deve ser exibida neste pixel ('0' = preto).
        i_lit     : in    std_logic;
        -- O pixel está dentro da área visível do modo.
        i_visible : in    std_logic;
        -- Sincronismo horizontal, já com a polaridade do modo.
        i_hs      : in    std_logic;
        -- Sincronismo vertical, já com a polaridade do modo.
        i_vs      : in    std_logic;

        -- Barramento de vídeo RGB de 24 bits do transmissor.
        o_d       : out   std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);
        -- Habilitação de dados do transmissor, alta em toda a área visível.
        o_de      : out   std_logic;
        -- Sincronismo horizontal do transmissor.
        o_hs      : out   std_logic;
        -- Sincronismo vertical do transmissor.
        o_vs      : out   std_logic
    );
end entity hdmi_out;

architecture rtl of hdmi_out is

    -- Nível de repouso do sincronismo horizontal, o oposto do nível do pulso.
    constant HS_IDLE : std_logic := to_sl(not h_sync_positive);
    -- Nível de repouso do sincronismo vertical, o oposto do nível do pulso.
    constant VS_IDLE : std_logic := to_sl(not v_sync_positive);

    -- Máscara da cor: todos os bits iguais a i_lit.
    signal lit_vec : std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);

begin

    lit_vec <= (others => i_lit);

    p_output : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                o_d  <= (others => '0');
                o_de <= '0';
                o_hs <= HS_IDLE;
                o_vs <= VS_IDLE;
            else
                o_d  <= i_color and lit_vec;
                o_de <= i_visible;
                o_hs <= i_hs;
                o_vs <= i_vs;
            end if;
        end if;

    end process p_output;

end architecture rtl;

-- =============================================================================
-- Backend VGA: registrador de saída para o conversor analógico da placa
--
-- Domínio do clock de pixel. Recebe a cor de 3 x channel_bits bits, os
-- sincronismos já com a polaridade do modo e as marcas de área visível e de
-- imagem acesa, e entrega os três canais, HS e VS em um registrador de saída,
-- sem lógica depois dele. A largura do canal (4 bits nos conversores
-- resistivos da DE0-CV, 8 bits no ADV7123 da DE2-115) é o generic channel_bits;
-- os canais são o vermelho nos bits mais altos da cor, depois o verde e o azul.
--
-- Fora da imagem acesa (i_lit = '0') as três cores saem pretas. Para os
-- conversores com entradas de apagamento e de sincronismo composto (ADV7123),
-- o_blank_n vale '0' fora da área visível e o_sync_n fica em '0', pois o
-- sincronismo vai pelos pinos separados HS e VS. O clock do conversor é o
-- próprio clock de pixel, ligado pelo topo da placa.
--
-- Prioridade: i_rst = '1' (síncrono) leva as saídas ao repouso (cores pretas,
-- apagamento ativo e sincronismos fora do pulso, no nível oposto ao da
-- polaridade).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.utils_pkg.all;

entity video_vga is
    generic (
        -- Bits de cada canal de cor (vermelho, verde e azul).
        channel_bits    : positive := 4;
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive : boolean  := false;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive : boolean  := false
    );
    port (
        -- Clock de pixel.
        i_clk     : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1'.
        i_rst     : in    std_logic;

        -- Cor do pixel, com o vermelho nos bits mais altos e o azul nos mais baixos.
        i_color   : in    std_logic_vector(3 * channel_bits - 1 downto 0);
        -- A cor deve ser exibida neste pixel ('0' = cores pretas).
        i_lit     : in    std_logic;
        -- O pixel está dentro da área visível do modo.
        i_visible : in    std_logic;
        -- Sincronismo horizontal, já com a polaridade do modo.
        i_hs      : in    std_logic;
        -- Sincronismo vertical, já com a polaridade do modo.
        i_vs      : in    std_logic;

        -- Canal vermelho do conversor da placa.
        o_r       : out   std_logic_vector(channel_bits - 1 downto 0);
        -- Canal verde do conversor da placa.
        o_g       : out   std_logic_vector(channel_bits - 1 downto 0);
        -- Canal azul do conversor da placa.
        o_b       : out   std_logic_vector(channel_bits - 1 downto 0);
        -- Sincronismo horizontal da placa.
        o_hs      : out   std_logic;
        -- Sincronismo vertical da placa.
        o_vs      : out   std_logic;
        -- Apagamento do conversor, ativo em nível baixo (baixo fora da área visível).
        o_blank_n : out   std_logic;
        -- Sincronismo composto do conversor, ativo em nível baixo; fica em '0' porque HS e VS são separados.
        o_sync_n  : out   std_logic
    );
end entity video_vga;

architecture rtl of video_vga is

    -- Nível de repouso do sincronismo horizontal, o oposto do nível do pulso.
    constant HS_IDLE : std_logic := to_sl(not h_sync_positive);
    -- Nível de repouso do sincronismo vertical, o oposto do nível do pulso.
    constant VS_IDLE : std_logic := to_sl(not v_sync_positive);

    -- Máscara dos canais de cor: todos os bits iguais a i_lit.
    signal lit_vec : std_logic_vector(3 * channel_bits - 1 downto 0);

begin

    lit_vec  <= (others => i_lit);
    o_sync_n <= '0';

    p_output : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                o_r       <= (others => '0');
                o_g       <= (others => '0');
                o_b       <= (others => '0');
                o_hs      <= HS_IDLE;
                o_vs      <= VS_IDLE;
                o_blank_n <= '0';
            else
                o_r       <= i_color(3 * channel_bits - 1 downto 2 * channel_bits) and
                             lit_vec(3 * channel_bits - 1 downto 2 * channel_bits);
                o_g       <= i_color(2 * channel_bits - 1 downto channel_bits) and
                             lit_vec(2 * channel_bits - 1 downto channel_bits);
                o_b       <= i_color(channel_bits - 1 downto 0) and lit_vec(channel_bits - 1 downto 0);
                o_hs      <= i_hs;
                o_vs      <= i_vs;
                o_blank_n <= i_visible;
            end if;
        end if;

    end process p_output;

end architecture rtl;

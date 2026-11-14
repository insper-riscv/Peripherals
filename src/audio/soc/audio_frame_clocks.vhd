-- =============================================================================
-- Clocks de bit e de amostra do modo mestre
--
-- Deriva o clock de bit (BCLK) e o clock de canal (LRCK) das inversões do clock
-- mestre. O BCLK inverte a cada i_bclk_div inversões do mestre, logo sua
-- frequência é a do mestre dividida por i_bclk_div. O LRCK inverte na borda de
-- descida do BCLK, a cada i_slot_bits ciclos de BCLK, e vale '0' no canal
-- esquerdo e '1' no direito. A taxa de amostragem é
-- f_mestre / (i_bclk_div * 2 * i_slot_bits). Desabilitado, BCLK e LRCK ficam em '0'.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_frame_clocks is
    port (
        -- Clock do sistema.
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst       : in    std_logic;
        -- Habilita a geração; desabilitado, zera contadores e saídas.
        i_enable    : in    std_logic;
        -- Pulso de uma inversão do clock mestre.
        i_xck_edge  : in    std_logic;
        -- Inversões do mestre entre inversões do BCLK (zero vale um).
        i_bclk_div  : in    std_logic_vector(15 downto 0);
        -- Ciclos de BCLK por canal (zero vale um).
        i_slot_bits : in    std_logic_vector(15 downto 0);
        -- Clock de bit gerado.
        o_bclk      : out   std_logic;
        -- Clock de canal gerado.
        o_lrck      : out   std_logic
    );
end entity audio_frame_clocks;

architecture rtl of audio_frame_clocks is

    -- Inversões do mestre contadas desde a última inversão do BCLK.
    signal edge_count : unsigned(15 downto 0);
    -- Ciclos de BCLK contados desde a última inversão do LRCK.
    signal slot_count : unsigned(15 downto 0);
    -- Nível atual do BCLK.
    signal bclk       : std_logic;
    -- Nível atual do LRCK.
    signal lrck       : std_logic;

begin

    o_bclk <= bclk;
    o_lrck <= lrck;

    p_clocks : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' or i_enable = '0' then
                edge_count <= (others => '0');
                slot_count <= (others => '0');
                bclk       <= '0';
                lrck       <= '0';
            elsif i_xck_edge = '1' then
                if edge_count + 1 >= unsigned(i_bclk_div) then
                    edge_count <= (others => '0');
                    bclk       <= not bclk;

                    if bclk = '1' then
                        if slot_count + 1 >= unsigned(i_slot_bits) then
                            slot_count <= (others => '0');
                            lrck       <= not lrck;
                        else
                            slot_count <= slot_count + 1;
                        end if;
                    end if;
                else
                    edge_count <= edge_count + 1;
                end if;
            end if;
        end if;

    end process p_clocks;

end architecture rtl;

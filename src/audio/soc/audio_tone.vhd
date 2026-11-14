-- =============================================================================
-- Gerador de onda quadrada de teste
--
-- Mantém o nível de uma onda quadrada que inverte a cada i_half quadros de
-- áudio. A frequência do tom é a taxa de amostragem dividida por 2 * i_half.
-- O nível avança a cada pulso i_advance (um por quadro), só com i_enable em
-- '1'; desabilitado, o nível volta a '0' (semiciclo positivo).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_tone is
    port (
        -- Clock do sistema.
        i_clk     : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst     : in    std_logic;
        -- Habilita o gerador.
        i_enable  : in    std_logic;
        -- Quadros por semiciclo (zero vale um).
        i_half    : in    std_logic_vector(15 downto 0);
        -- Pulso que fecha um quadro.
        i_advance : in    std_logic;
        -- Nível atual: '0' semiciclo positivo, '1' negativo.
        o_level   : out   std_logic
    );
end entity audio_tone;

architecture rtl of audio_tone is

    -- Quadros contados no semiciclo atual.
    signal count : unsigned(15 downto 0);
    -- Nível atual da onda.
    signal level : std_logic;

begin

    o_level <= level;

    p_tone : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' or i_enable = '0' then
                count <= (others => '0');
                level <= '0';
            elsif i_advance = '1' then
                if count + 1 >= unsigned(i_half) then
                    count <= (others => '0');
                    level <= not level;
                else
                    count <= count + 1;
                end if;
            end if;
        end if;

    end process p_tone;

end architecture rtl;

-- =============================================================================
-- Gerador fracionário do clock mestre do codec
--
-- Produz uma onda quadrada de frequência (i_step / i_mod) * f_clk / 2 a partir
-- de i_clk com um acumulador de fase de erro (Bresenham): a cada ciclo soma
-- i_step e, quando a soma alcança i_mod, desconta i_mod e inverte a saída. A
-- razão é exata em média e a saída varia no máximo um período de i_clk de
-- jitter. Vale i_step <= i_mod (saída no máximo f_clk / 2); com i_step = 0 a
-- saída fica em '0'. Cada inversão gera também o pulso o_edge, que dura o
-- ciclo em que o_xck assume o novo nível.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_xck_gen is
    port (
        -- Clock do sistema.
        i_clk   : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst   : in    std_logic;
        -- Habilita o gerador; desabilitado, a saída fica em '0' e o acumulador zera.
        i_enable : in    std_logic;
        -- Soma do acumulador por ciclo, igual a 2 vezes a frequência desejada.
        i_step  : in    std_logic_vector(31 downto 0);
        -- Módulo do acumulador, igual à frequência de i_clk em Hz.
        i_mod   : in    std_logic_vector(31 downto 0);
        -- Clock mestre gerado.
        o_xck   : out   std_logic;
        -- Pulso de um ciclo em cada inversão de o_xck.
        o_edge  : out   std_logic
    );
end entity audio_xck_gen;

architecture rtl of audio_xck_gen is

    -- Erro acumulado, sempre menor que o módulo.
    signal acc   : unsigned(31 downto 0);
    -- Valor de i_mod menos i_step, saturado em zero; a soma alcança o módulo quando acc >= dec.
    signal dec   : unsigned(31 downto 0);
    -- Indica que dec já reflete os registradores depois do reset.
    signal armed : std_logic;
    -- Nível atual do clock mestre.
    signal xck   : std_logic;
    -- Pulso registrado de inversão.
    signal edge_pulse : std_logic;

begin

    o_xck  <= xck;
    o_edge <= edge_pulse;

    p_xck : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if unsigned(i_mod) > unsigned(i_step) then
                dec <= unsigned(i_mod) - unsigned(i_step);
            else
                dec <= (others => '0');
            end if;

            armed <= not i_rst;
            edge_pulse <= '0';

            if i_rst = '1' or i_enable = '0' or unsigned(i_step) = 0 then
                acc <= (others => '0');
                xck <= '0';
            elsif armed = '1' then
                if acc >= dec then
                    acc  <= acc - dec;
                    xck  <= not xck;
                    edge_pulse <= '1';
                else
                    acc <= acc + unsigned(i_step);
                end if;
            end if;
        end if;

    end process p_xck;

end architecture rtl;

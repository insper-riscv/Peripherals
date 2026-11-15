-- =============================================================================
-- Serializador TMDS de 10 bits em dois bits por ciclo de um clock cinco vezes mais rápido
--
-- Leva um símbolo de 10 bits, estável durante um período do clock de pixel, a
-- uma saída que carrega dois bits por ciclo de i_clk_x5: o_h vale na metade alta
-- do clock e o_l na metade baixa, como o registrador DDR de saída espera. O
-- símbolo sai a partir do bit 0, de modo que o ciclo k de cinco leva os bits 2k
-- (o_h) e 2k+1 (o_l).
--
-- O clock de pixel e o de 5 vezes saem do mesmo PLL, com fase fixa entre si, e
-- i_clk_x5 vale cinco vezes i_clk_pixel. O símbolo muda a cada borda de
-- i_clk_pixel e atravessa para o domínio rápido assim:
--   1. no domínio de pixel, o símbolo é copiado para um registrador e um bit
--      de alternância (toggle) muda de valor na mesma borda;
--   2. no domínio rápido, o toggle passa por um sincronizador de dois estágios
--      e a sua mudança carrega o registrador de deslocamento com o símbolo,
--      que já está parado há ciclos suficientes para ser lido.
-- O registrador de deslocamento anda dois bits por ciclo de i_clk_x5 e entrega
-- o_h e o_l. Não há reset: o estado inicial vem do valor de elaboração e o
-- primeiro toggle carrega o primeiro símbolo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.tmds_consts.all;

entity tmds_serializer is
    port (
        -- Clock de pixel, em que muda i_token.
        i_clk_pixel : in    std_logic;
        -- Clock cinco vezes mais rápido que i_clk_pixel, do mesmo PLL.
        i_clk_x5    : in    std_logic;
        -- Símbolo a transmitir, bit 0 primeiro, estável durante um período de i_clk_pixel.
        i_token     : in    std_logic_vector(TOKEN_BITS - 1 downto 0);
        -- Bit para a metade alta do ciclo de i_clk_x5.
        o_h         : out   std_logic;
        -- Bit para a metade baixa do ciclo de i_clk_x5.
        o_l         : out   std_logic
    );
end entity tmds_serializer;

architecture rtl of tmds_serializer is

    -- Símbolo copiado no domínio de pixel, lido no domínio rápido depois do toggle.
    signal hold      : std_logic_vector(TOKEN_BITS - 1 downto 0) := (others => '0');
    -- Bit que muda de valor a cada período de pixel, no domínio de pixel.
    signal toggle    : std_logic                                 := '0';
    -- Toggle sincronizado no domínio rápido (vetor de um bit do sincronizador).
    signal toggle_sync : std_logic_vector(0 downto 0);
    -- Toggle sincronizado do ciclo anterior.
    signal toggle_prev : std_logic := '0';
    -- Registrador de deslocamento do símbolo, dois bits por ciclo.
    signal shift     : std_logic_vector(TOKEN_BITS - 1 downto 0) := (others => '0');

begin

    p_hold : process (i_clk_pixel) is
    begin

        if rising_edge(i_clk_pixel) then
            hold   <= i_token;
            toggle <= not toggle;
        end if;

    end process p_hold;

    u_toggle_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk  => i_clk_x5,
            i_rst  => '0',
            i_d(0) => toggle,
            o_d    => toggle_sync
        );

    p_shift : process (i_clk_x5) is
    begin

        if rising_edge(i_clk_x5) then
            toggle_prev <= toggle_sync(0);

            if toggle_sync(0) /= toggle_prev then
                shift <= hold;
            else
                shift <= (BITS_PER_CLK - 1 downto 0 => '0') & shift(TOKEN_BITS - 1 downto BITS_PER_CLK);
            end if;
        end if;

    end process p_shift;

    o_h <= shift(0);
    o_l <= shift(1);

end architecture rtl;

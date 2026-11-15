-- =============================================================================
-- Receptor de uma lane do D-PHY em alta velocidade
--
-- Recebe dois bits por ciclo de i_clk (um par amostrado nas duas bordas do
-- clock da câmera por um registrador DDR de entrada), procura o byte de
-- sincronismo do D-PHY (0xB8, bits do menos significativo) precedido por zeros e,
-- achado o byte, entrega um byte alinhado a cada quatro ciclos. A busca olha as
-- duas fases possíveis do byte em relação ao par de bits (o byte termina no fim
-- do par ou um bit antes), de modo que a lane se alinha sozinha em qualquer
-- deslocamento de bit.
--
-- Com i_arm em '1' a lane procura o sincronismo e, depois de achá-lo, mantém o
-- alinhamento e entrega bytes; com i_arm em '0' ela se destrava. O receptor
-- não vê os estados de baixo consumo do D-PHY: quem o usa sabe o tamanho do
-- pacote e destrava a lane no fim dele.
--
-- Latência: o byte sai em o_byte cinco ciclos depois do ciclo em que o byte
-- de sincronismo termina de entrar na janela, com o_valid em '1' por um ciclo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mipi_consts.all;

entity mipi_lane_rx is
    port (
        -- Clock do receptor (clock da câmera, ou seu equivalente depois do registrador DDR).
        i_clk       : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst       : in    std_logic;
        -- Permite a busca de sincronismo e mantém a lane travada; em '0' ela se destrava.
        i_arm       : in    std_logic;
        -- Bit mais antigo do par do ciclo.
        i_bit_early : in    std_logic;
        -- Bit mais novo do par do ciclo.
        i_bit_late  : in    std_logic;
        -- Lane alinhada ao byte de sincronismo.
        o_locked    : out   std_logic;
        -- Pulso de um ciclo que acompanha cada byte entregue.
        o_valid     : out   std_logic;
        -- Byte alinhado da lane.
        o_byte      : out   std_logic_vector(7 downto 0)
    );
end entity mipi_lane_rx;

architecture rtl of mipi_lane_rx is

    -- Preâmbulo de zeros exigido antes do byte de sincronismo.
    constant ZERO_PREAMBLE : std_logic_vector(PREAMBLE_BITS - 1 downto 0) := (others => '0');

    -- Janela dos últimos 24 bits recebidos, o mais antigo no índice zero.
    signal window     : std_logic_vector(23 downto 0) := (others => '0');
    -- Lane alinhada ao byte de sincronismo.
    signal locked     : std_logic                     := '0';
    -- Fase do byte, '1' quando ele termina um bit antes do fim do par.
    signal odd_phase  : std_logic                     := '0';
    -- Ciclos desde o último byte, de 0 a 3.
    signal cycle_cnt  : unsigned(1 downto 0)          := (others => '0');
    -- Byte de sincronismo na fase par, precedido de zeros.
    signal match_even : std_logic;
    -- Byte de sincronismo na fase ímpar, precedido de zeros.
    signal match_odd  : std_logic;

begin

    match_even <= '1' when window(23 downto 16) = SYNC_BYTE and
                           window(15 downto 16 - PREAMBLE_BITS) = ZERO_PREAMBLE else
                  '0';
    match_odd  <= '1' when window(22 downto 15) = SYNC_BYTE and
                           window(14 downto 15 - PREAMBLE_BITS) = ZERO_PREAMBLE else
                  '0';
    o_locked   <= locked;

    p_lane : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            window  <= i_bit_late & i_bit_early & window(23 downto 2);
            o_valid <= '0';

            if i_arm = '0' then
                locked <= '0';
            elsif locked = '1' then
                cycle_cnt <= cycle_cnt + 1;

                if cycle_cnt = 3 then
                    o_valid <= '1';

                    if odd_phase = '1' then
                        o_byte <= window(22 downto 15);
                    else
                        o_byte <= window(23 downto 16);
                    end if;
                end if;
            elsif match_even = '1' or match_odd = '1' then
                locked    <= '1';
                odd_phase <= not match_even;
                cycle_cnt <= (others => '0');
            end if;

            if i_rst = '1' then
                locked  <= '0';
                o_valid <= '0';
            end if;
        end if;

    end process p_lane;

end architecture rtl;

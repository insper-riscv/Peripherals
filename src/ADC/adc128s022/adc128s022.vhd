-- ==========================================================================
-- Controlador do conversor A/D ADC128S022 (DE0-Nano)
-- ==========================================================================
-- O ADC128S022 é um conversor de 12 bits e oito canais com interface SPI de
-- 16 clocks por conversão. O controlador varre os oito canais de modo
-- automático (adc_sweep) e guarda cada resultado num registrador de 12 bits.
-- Cada quadro é uma palavra SPI de 16 bits no modo 3 (SCLK em repouso alto,
-- o chip muda o dado na borda de descida e o controlador amostra na de
-- subida), bit mais significativo primeiro, com a seleção de chip em nível
-- baixo durante o quadro.
--
-- Palavra enviada (ADC_SADDR): bits 15:14 sem efeito, 13:11 endereço do canal
-- (ADD2 a ADD0), bits 10:0 sem efeito. Palavra recebida (ADC_SDAT): bits 15:12
-- zero e bits 11:0 o resultado (DB11 a DB0).
--
-- Suposições, porque a folha de dados do chip não está no repositório e o
-- manual só dá a interface (DE0-Nano, seção 3.6): o modo 3, o formato das
-- palavras, o canal endereçado num quadro valer para a conversão seguinte
-- (channel_latency em 1) e a faixa de SCLK de 0,8 a 3,2 MHz que decorre de
-- 50 a 200 ksps com 16 clocks. Os registradores são os de adc_sweep.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;

entity adc128s022 is
    generic (
        -- Frequência do clock do módulo, em hertz.
        clock_hz        : positive := 50_000_000;
        -- Frequência de SCLK depois do reset, em hertz (o chip aceita até 3,2 MHz).
        sclk_hz         : positive := 3_200_000;
        -- Quadros de atraso entre endereçar um canal e receber o seu resultado.
        channel_latency : natural range 0 to 1 := 1
    );
    port (
        -- Clock do módulo.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst         : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Endereço de palavra do registrador, entre zero e dez.
        i_address     : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq         : out   std_logic;
        -- Seleção de chip do conversor, ativa em nível baixo (ADC_CS_N).
        o_adc_cs_n    : out   std_logic;
        -- Relógio serial do conversor (ADC_SCLK).
        o_adc_sclk    : out   std_logic;
        -- Endereço do canal para o conversor (ADC_SADDR).
        o_adc_saddr   : out   std_logic;
        -- Resultado do conversor para o controlador (ADC_SDAT).
        i_adc_sdat    : in    std_logic
    );
end entity adc128s022;

architecture rtl of adc128s022 is

    -- Divisor do reset, que mantém SCLK em sclk_hz ou abaixo.
    constant RESET_DIVIDER : natural := (clock_hz + 2 * sclk_hz - 1) / (2 * sclk_hz) - 1;

    -- Largura da palavra SPI, em bits, na codificação do mestre.
    constant WORD_BITS : std_logic_vector(5 downto 0) := "010000";

    -- Estados do quadro.
    type state_t is (S_IDLE, S_SEND, S_WAIT);

    -- Estado do quadro.
    signal state       : state_t;
    -- Linha de seleção de chip.
    signal cs_n        : std_logic;
    -- Palavra a transmitir.
    signal tx_word     : std_logic_vector(15 downto 0);
    -- Pulso que inicia a palavra no mestre.
    signal spi_start   : std_logic;
    -- Pulso de fim de palavra do mestre.
    signal spi_done    : std_logic;
    -- Palavra recebida pelo mestre.
    signal spi_rx      : std_logic_vector(15 downto 0);
    -- MISO sincronizada com o clock.
    signal miso_sync   : std_logic_vector(0 downto 0);
    -- Divisor de clock do SCLK.
    signal divider     : std_logic_vector(15 downto 0);
    -- Pulso que pede um quadro.
    signal frame_start : std_logic;
    -- Canal do quadro.
    signal frame_ch    : std_logic_vector(2 downto 0);
    -- Pulso de quadro concluído.
    signal frame_done  : std_logic;

begin

    o_adc_cs_n <= cs_n;

    u_sweep : entity work.adc_sweep
        generic map (
            channel_latency => channel_latency,
            reset_divider   => RESET_DIVIDER
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_data_in       => i_data_in,
            i_address       => i_address,
            i_write         => i_write,
            o_data_out      => o_data_out,
            o_irq           => o_irq,
            o_frame_start   => frame_start,
            o_frame_channel => frame_ch,
            i_frame_done    => frame_done,
            i_frame_data    => spi_rx(11 downto 0),
            o_divider       => divider
        );

    u_miso_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d(0) => i_adc_sdat,
            o_d   => miso_sync
        );

    u_master : entity work.spi_master
        generic map (
            divider_width => 16,
            word_width    => 16
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_cpol      => '1',
            i_cpha      => '1',
            i_lsb_first => '0',
            i_word_bits => WORD_BITS,
            i_divider   => divider,
            i_tx_drive  => '1',
            i_start     => spi_start,
            i_tx_data   => tx_word,
            o_busy      => open,
            o_done      => spi_done,
            o_rx_data   => spi_rx,
            o_sclk      => o_adc_sclk,
            o_mosi      => o_adc_saddr,
            o_mosi_oe   => open,
            i_miso      => miso_sync(0)
        );

    p_frame : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            spi_start  <= '0';
            frame_done <= '0';

            if i_rst = '1' then
                state    <= S_IDLE;
                cs_n     <= '1';
                tx_word  <= (others => '0');
            else
                case state is

                    when S_IDLE =>

                        if frame_start = '1' then
                            cs_n    <= '0';
                            tx_word <= "00" & frame_ch & "00000000000";
                            state   <= S_SEND;
                        end if;

                    when S_SEND =>

                        spi_start <= '1';
                        state     <= S_WAIT;

                    when S_WAIT =>

                        if spi_done = '1' then
                            cs_n       <= '1';
                            frame_done <= '1';
                            state      <= S_IDLE;
                        end if;

                end case;
            end if;
        end if;

    end process p_frame;

end architecture rtl;

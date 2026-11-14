-- ==========================================================================
-- Controlador do conversor A/D LTC2308 (DE10-Nano e DE0-Nano-SoC)
-- ==========================================================================
-- O LTC2308 é um conversor de 12 bits, oito canais e 500 ksps com interface
-- SPI de até 40 MHz. Os manuais das placas (seção 3.6.4 de cada uma) ligam o
-- conversor a pinos do lado do FPGA (ADC_CONVST, ADC_SCK, ADC_SDI e ADC_SDO),
-- então este controlador, no FPGA, é o dono do protocolo. O controlador varre
-- os oito canais de modo automático (adc_sweep) e guarda cada resultado num
-- registrador de 12 bits.
--
-- Cada quadro é: pulso alto em ADC_CONVST, espera da conversão e uma palavra
-- SPI de 12 bits no modo 0 (SCK em repouso baixo, o chip muda o dado na borda
-- de descida e o controlador amostra na de subida), bit mais significativo
-- primeiro. A palavra enviada em ADC_SDI tem na frente os seis bits de
-- configuração S/D, O/S, S1, S0, UNI e SLP e depois seis zeros. A
-- configuração é de entrada única (S/D em 1) e unipolar (UNI em 1), sem
-- repouso (SLP em 0), com O/S, S1 e S0 formando o canal (bit 0, bit 2 e bit 1
-- do índice). A palavra recebida em ADC_SDO é o resultado de 12 bits.
--
-- Suposições, porque a folha de dados do chip não está no repositório e os
-- manuais só dão a interface: o modo 0, o formato dos seis bits de
-- configuração e a codificação do canal, o resultado de um quadro valer
-- para a configuração do quadro anterior (channel_latency em 1) e os tempos
-- de CONVST, de conversão e de aquisição, que são valores conservadores.
-- Os registradores são os de adc_sweep.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;

entity ltc2308 is
    generic (
        -- Frequência do clock do módulo, em hertz.
        clock_hz        : positive := 50_000_000;
        -- Frequência de SCK depois do reset, em hertz (o chip aceita até 40 MHz).
        sclk_hz         : positive := 10_000_000;
        -- Largura do pulso alto de ADC_CONVST, em nanossegundos.
        convst_ns       : positive := 100;
        -- Tempo de conversão esperado depois do pulso, em nanossegundos.
        conversion_ns   : positive := 1600;
        -- Tempo de aquisição esperado depois do quadro, em nanossegundos.
        acquisition_ns  : positive := 300;
        -- Quadros de atraso entre configurar um canal e receber o seu resultado.
        channel_latency : natural range 0 to 1 := 1
    );
    port (
        -- Clock do módulo.
        i_clk          : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst          : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in      : in    word_t;
        -- Endereço de palavra do registrador, entre zero e dez.
        i_address      : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador.
        i_write        : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out     : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq          : out   std_logic;
        -- Início de conversão do conversor (ADC_CONVST).
        o_adc_convst   : out   std_logic;
        -- Relógio serial do conversor (ADC_SCK).
        o_adc_sck      : out   std_logic;
        -- Configuração do canal para o conversor (ADC_SDI).
        o_adc_sdi      : out   std_logic;
        -- Resultado do conversor para o controlador (ADC_SDO).
        i_adc_sdo      : in    std_logic
    );
end entity ltc2308;

architecture rtl of ltc2308 is

    -- Converte um tempo em nanossegundos em ciclos de clock, arredondado para cima.
    function to_cycles (nanoseconds : positive) return positive is
    begin

        return (nanoseconds * (clock_hz / 1000) + 999_999) / 1_000_000;

    end function to_cycles;

    -- Divisor do reset, que mantém SCK em sclk_hz ou abaixo.
    constant RESET_DIVIDER : natural := (clock_hz + 2 * sclk_hz - 1) / (2 * sclk_hz) - 1;

    -- Ciclos do pulso de ADC_CONVST.
    constant CONVST_CYCLES      : positive := to_cycles(convst_ns);
    -- Ciclos de espera da conversão.
    constant CONVERSION_CYCLES  : positive := to_cycles(conversion_ns);
    -- Ciclos de espera da aquisição.
    constant ACQUISITION_CYCLES : positive := to_cycles(acquisition_ns);

    -- Largura da palavra SPI, em bits, na codificação do mestre.
    constant WORD_BITS : std_logic_vector(5 downto 0) := "001100";

    -- Estados do quadro.
    type state_t is (S_IDLE, S_CONVST, S_CONVERT, S_WAIT, S_ACQUIRE);

    -- Estado do quadro.
    signal state       : state_t;
    -- Contagem de ciclos do estado.
    signal wait_cnt    : natural range 0 to 65535;
    -- Linha de início de conversão.
    signal convst      : std_logic;
    -- Palavra a transmitir, com a configuração nos seis bits altos.
    signal tx_word     : std_logic_vector(11 downto 0);
    -- Pulso que inicia a palavra no mestre.
    signal spi_start   : std_logic;
    -- Pulso de fim de palavra do mestre.
    signal spi_done    : std_logic;
    -- Palavra recebida pelo mestre.
    signal spi_rx      : std_logic_vector(11 downto 0);
    -- MISO sincronizada com o clock.
    signal miso_sync   : std_logic_vector(0 downto 0);
    -- Divisor de clock do SCK.
    signal divider     : std_logic_vector(15 downto 0);
    -- Pulso que pede um quadro.
    signal frame_start : std_logic;
    -- Canal do quadro.
    signal frame_ch    : std_logic_vector(2 downto 0);
    -- Pulso de quadro concluído.
    signal frame_done  : std_logic;

begin

    assert CONVERSION_CYCLES < 65535 and ACQUISITION_CYCLES < 65535 and CONVST_CYCLES < 65535
        report "ltc2308: a wait does not fit in the 16-bit counter"
        severity failure;

    o_adc_convst <= convst;

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
            i_frame_data    => spi_rx,
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
            i_d(0) => i_adc_sdo,
            o_d   => miso_sync
        );

    u_master : entity work.spi_master
        generic map (
            divider_width => 16,
            word_width    => 12
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_cpol      => '0',
            i_cpha      => '0',
            i_lsb_first => '0',
            i_word_bits => WORD_BITS,
            i_divider   => divider,
            i_tx_drive  => '1',
            i_start     => spi_start,
            i_tx_data   => tx_word,
            o_busy      => open,
            o_done      => spi_done,
            o_rx_data   => spi_rx,
            o_sclk      => o_adc_sck,
            o_mosi      => o_adc_sdi,
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
                wait_cnt <= 0;
                convst   <= '0';
                tx_word  <= (others => '0');
            else
                case state is

                    when S_IDLE =>

                        if frame_start = '1' then
                            -- Configuração: S/D = 1, O/S, S1, S0, UNI = 1 e SLP = 0, depois seis zeros.
                            tx_word  <= '1' & frame_ch(0) & frame_ch(2) & frame_ch(1) & "10" & "000000";
                            convst   <= '1';
                            wait_cnt <= 1;
                            state    <= S_CONVST;
                        end if;

                    when S_CONVST =>

                        if wait_cnt = CONVST_CYCLES then
                            convst   <= '0';
                            wait_cnt <= 1;
                            state    <= S_CONVERT;
                        else
                            wait_cnt <= wait_cnt + 1;
                        end if;

                    when S_CONVERT =>

                        if wait_cnt = CONVERSION_CYCLES then
                            spi_start <= '1';
                            state     <= S_WAIT;
                        else
                            wait_cnt <= wait_cnt + 1;
                        end if;

                    when S_WAIT =>

                        if spi_done = '1' then
                            wait_cnt <= 1;
                            state    <= S_ACQUIRE;
                        end if;

                    when S_ACQUIRE =>

                        if wait_cnt = ACQUISITION_CYCLES then
                            frame_done <= '1';
                            state      <= S_IDLE;
                        else
                            wait_cnt <= wait_cnt + 1;
                        end if;

                end case;
            end if;
        end if;

    end process p_frame;

end architecture rtl;

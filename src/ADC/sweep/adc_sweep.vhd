-- ==========================================================================
-- Varredura dos oito canais de um conversor A/D e registradores de canal
-- ==========================================================================
-- Máquina de varredura e bloco de registradores comuns aos conversores de
-- oito canais e 12 bits (ADC128S022 e LTC2308). A varredura pede ao chip um
-- quadro por canal, em ordem, e guarda o resultado de cada um no registrador
-- do canal. Com channel_latency em 1 o chip devolve num quadro o resultado do
-- canal endereçado no quadro anterior, então a varredura tem um quadro a mais,
-- que prepara o primeiro canal e cujo resultado é descartado. Com 0 o quadro
-- devolve o canal que ele mesmo endereça.
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 a 7  CH0 a CH7  R      bits 11:0, último resultado do canal
--   8      CONTROL    R/W    bit 0 ENABLE (varredura contínua), 1 IRQ_ENABLE,
--                            2 START (escrita de 1 inicia uma varredura com
--                            ENABLE em 0; lê sempre 0)
--   9      STATUS     R/W1C  bit 0 BUSY, 1 SWEEP_DONE, 2 VALID (uma varredura
--                            inteira já terminou)
--   10     DIVIDER    R/W    bits 15:0, divisor de clock do SCLK do chip
--
-- SWEEP_DONE é marcado a cada varredura que termina e limpo escrevendo 1 em
-- STATUS (um evento novo tem prioridade sobre a limpeza). A saída o_irq é de
-- nível, e vale SWEEP_DONE com IRQ_ENABLE. Desligar ENABLE termina a
-- varredura em andamento e para. A interface de quadro com o chip é um pulso
-- o_frame_start com o canal em o_frame_channel e a resposta i_frame_done com o
-- resultado em i_frame_data.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;

entity adc_sweep is
    generic (
        -- Quadros de atraso entre endereçar um canal e receber o seu resultado (0 ou 1).
        channel_latency : natural range 0 to 1 := 1;
        -- Divisor de clock do SCLK depois do reset.
        reset_divider   : natural := 7
    );
    port (
        -- Clock do módulo.
        i_clk           : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst           : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in       : in    word_t;
        -- Endereço de palavra do registrador, entre zero e dez.
        i_address       : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador.
        i_write         : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out      : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq           : out   std_logic;
        -- Pulso de um ciclo que pede um quadro ao chip.
        o_frame_start   : out   std_logic;
        -- Canal endereçado no quadro.
        o_frame_channel : out   std_logic_vector(2 downto 0);
        -- Pulso de um ciclo com o quadro concluído.
        i_frame_done    : in    std_logic;
        -- Resultado de 12 bits do quadro, válido com i_frame_done.
        i_frame_data    : in    std_logic_vector(11 downto 0);
        -- Divisor de clock do SCLK do chip.
        o_divider       : out   std_logic_vector(15 downto 0)
    );
end entity adc_sweep;

architecture rtl of adc_sweep is

    -- Endereço do registrador de controle.
    constant CONTROL_ADDRESS : std_logic_vector(3 downto 0) := "1000";
    -- Endereço do registrador de estado.
    constant STATUS_ADDRESS  : std_logic_vector(3 downto 0) := "1001";
    -- Endereço do registrador do divisor.
    constant DIVIDER_ADDRESS : std_logic_vector(3 downto 0) := "1010";

    -- Último quadro de uma varredura.
    constant LAST_FRAME : natural := 7 + channel_latency;

    -- Estados da varredura.
    type state_t is (S_IDLE, S_ISSUE, S_WAIT);

    -- Resultados dos oito canais.
    type channels_t is array (0 to 7) of std_logic_vector(11 downto 0);

    -- Estado atual da varredura.
    signal state       : state_t;
    -- Número do quadro dentro da varredura.
    signal frame       : natural range 0 to LAST_FRAME;
    -- Último resultado de cada canal.
    signal channels    : channels_t;
    -- Varredura contínua.
    signal enable      : std_logic;
    -- Habilitação da interrupção de fim de varredura.
    signal irq_enable  : std_logic;
    -- Marca persistente de fim de varredura.
    signal sweep_done  : std_logic;
    -- Uma varredura inteira já terminou.
    signal valid       : std_logic;
    -- Divisor de clock do SCLK do chip.
    signal divider     : std_logic_vector(15 downto 0);

begin

    o_frame_start   <= '1' when state = S_ISSUE else '0';
    o_frame_channel <= std_logic_vector(to_unsigned(frame mod 8, 3));
    o_divider       <= divider;
    o_irq           <= irq_enable and sweep_done;

    p_sweep : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                state      <= S_IDLE;
                frame      <= 0;
                channels   <= (others => (others => '0'));
                enable     <= '0';
                irq_enable <= '0';
                sweep_done <= '0';
                valid      <= '0';
                divider    <= std_logic_vector(to_unsigned(reset_divider, 16));
            else
                if i_write = '1' and i_address = CONTROL_ADDRESS then
                    enable     <= i_data_in(0);
                    irq_enable <= i_data_in(1);
                end if;

                if i_write = '1' and i_address = DIVIDER_ADDRESS then
                    divider <= i_data_in(15 downto 0);
                end if;

                if i_write = '1' and i_address = STATUS_ADDRESS then
                    sweep_done <= sweep_done and not i_data_in(1);
                end if;

                case state is

                    when S_IDLE =>

                        frame <= 0;

                        if enable = '1' or (i_write = '1' and i_address = CONTROL_ADDRESS and i_data_in(2) = '1') then
                            state <= S_ISSUE;
                        end if;

                    when S_ISSUE =>

                        state <= S_WAIT;

                    when S_WAIT =>

                        if i_frame_done = '1' then
                            if frame >= channel_latency then
                                channels(frame - channel_latency) <= i_frame_data;
                            end if;

                            if frame = LAST_FRAME then
                                sweep_done <= '1';
                                valid      <= '1';
                                frame      <= 0;
                                state      <= S_ISSUE when enable = '1' else S_IDLE;
                            else
                                frame <= frame + 1;
                                state <= S_ISSUE;
                            end if;
                        end if;

                end case;
            end if;
        end if;

    end process p_sweep;

    p_readback : process (i_address, channels, enable, irq_enable, state, sweep_done, valid, divider) is

        -- Valor montado para o registrador selecionado.
        variable value : word_t;

    begin

        value := (others => '0');

        if i_address(3) = '0' then
            value(11 downto 0) := channels(to_integer(unsigned(i_address(2 downto 0))));
        elsif i_address = CONTROL_ADDRESS then
            value(0) := enable;
            value(1) := irq_enable;
        elsif i_address = STATUS_ADDRESS then
            value(0) := '1' when state /= S_IDLE else '0';
            value(1) := sweep_done;
            value(2) := valid;
        elsif i_address = DIVIDER_ADDRESS then
            value(15 downto 0) := divider;
        end if;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;

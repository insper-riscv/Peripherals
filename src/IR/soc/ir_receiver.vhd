-- =============================================================================
-- Receptor de infravermelho com decodificador NEC (IRDA_RXD da DE2-115)
--
-- Liga o módulo receptor de infravermelho já demodulado (portadora de 38 kHz)
-- ao barramento do processador. O pino é sincronizado, o medidor de pulsos mede
-- cada pulso e cada espaço em ciclos de clock, o decodificador NEC reconhece
-- quadros e repetições, e os registradores guardam os quadros numa FIFO e a
-- última medida bruta, que o software pode usar para outros protocolos. O topo
-- só instancia e conecta as partes.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.ir_consts.all;

entity ir_receiver is
    generic (
        -- Frequência do clock em Hz (abaixo de 238 MHz).
        clk_freq_hz       : positive := 50000000;
        -- Tolerância das larguras NEC, em por cento (de 0 a 30).
        tolerance_percent : natural  := 25;
        -- Duração mínima, em microssegundos, de uma mudança da linha para valer.
        glitch_us         : positive := 20;
        -- Duração máxima de um nível dentro de um quadro, em microssegundos (maior que 9 ms).
        timeout_us        : positive := 12000;
        -- Profundidade da FIFO de quadros (no máximo 255).
        fifo_depth        : positive := 8;
        -- Guarda as larguras brutas do último pulso e do último espaço.
        raw_enable        : boolean  := true;
        -- Pino ativo em nível baixo, como o módulo demodulador da placa.
        active_low        : boolean  := true
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra vindo do processador.
        i_address  : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita ('1' = escreve).
        i_write    : in    std_logic;
        -- Pulso de leitura ('1' = lê).
        i_read     : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq      : out   std_logic;
        -- Pino do receptor de infravermelho (IRDA_RXD), assíncrono.
        i_irda_rxd : in    std_logic
    );
end entity ir_receiver;

architecture rtl of ir_receiver is

    -- Pino em formato de vetor de 1 bit.
    signal pin_vec     : std_logic_vector(0 downto 0);
    -- Pino sincronizado com i_clk.
    signal line_sync   : std_logic_vector(0 downto 0);
    -- Reset do medidor e do decodificador: reset do sistema ou receptor desligado.
    signal rx_rst      : std_logic;
    -- Receptor habilitado.
    signal enable      : std_logic;
    -- NEC estendido aceito.
    signal ext_en      : std_logic;
    -- Evento do medidor.
    signal event       : std_logic;
    -- Tipo do evento do medidor.
    signal event_mark  : std_logic;
    -- Largura do evento do medidor.
    signal width       : std_logic_vector(31 downto 0);
    -- Timeout do medidor.
    signal timeout     : std_logic;
    -- Nível filtrado da linha.
    signal line_active : std_logic;
    -- Quadro válido do decodificador.
    signal frame_valid : std_logic;
    -- Endereço do quadro.
    signal frame_addr  : std_logic_vector(15 downto 0);
    -- Comando do quadro.
    signal frame_cmd   : std_logic_vector(7 downto 0);
    -- Quadro é repetição.
    signal frame_rep   : std_logic;
    -- Quadro estendido.
    signal frame_ext   : std_logic;
    -- Quadro malformado.
    signal frame_error : std_logic;

begin

    pin_vec <= (0 => i_irda_rxd);
    rx_rst  <= i_rst or not enable;

    u_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => pin_vec,
            o_d   => line_sync
        );

    u_meter : entity work.ir_pulse_meter
        generic map (
            glitch_cycles  => us_to_cycles(clk_freq_hz, glitch_us),
            timeout_cycles => us_to_cycles(clk_freq_hz, timeout_us),
            active_low     => active_low
        )
        port map (
            i_clk        => i_clk,
            i_rst        => rx_rst,
            i_line       => line_sync(0),
            o_event      => event,
            o_event_mark => event_mark,
            o_width      => width,
            o_timeout    => timeout,
            o_active     => line_active
        );

    u_decoder : entity work.ir_nec_decoder
        generic map (
            clk_freq_hz       => clk_freq_hz,
            tolerance_percent => tolerance_percent
        )
        port map (
            i_clk         => i_clk,
            i_rst         => rx_rst,
            i_event       => event,
            i_event_mark  => event_mark,
            i_width       => width,
            i_timeout     => timeout,
            i_ext_en      => ext_en,
            o_frame_valid => frame_valid,
            o_address     => frame_addr,
            o_command     => frame_cmd,
            o_repeat      => frame_rep,
            o_extended    => frame_ext,
            o_error       => frame_error
        );

    u_regs : entity work.ir_regs
        generic map (
            fifo_depth => fifo_depth,
            raw_enable => raw_enable
        )
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_data_in     => i_data_in,
            i_address     => i_address,
            i_write       => i_write,
            i_read        => i_read,
            o_data_out    => o_data_out,
            o_irq         => o_irq,
            o_enable      => enable,
            o_ext_en      => ext_en,
            i_frame_valid => frame_valid,
            i_address_f   => frame_addr,
            i_command_f   => frame_cmd,
            i_repeat_f    => frame_rep,
            i_extended_f  => frame_ext,
            i_error_f     => frame_error,
            i_event       => event,
            i_event_mark  => event_mark,
            i_width       => width,
            i_line_active => line_active
        );

end architecture rtl;

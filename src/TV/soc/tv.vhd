-- =============================================================================
-- Periférico de captura de vídeo do decodificador de TV ADV7180
--
-- Recebe o fluxo ITU-R BT.656 de 8 bits que o ADV7180 da DE2-115 entrega (pinos
-- TD_DATA e TD_CLK27), reconhece os códigos de início e fim de vídeo ativo,
-- extrai Y, Cb e Cr, converte para RGB565 ou luminância, reduz a resolução por
-- fatores inteiros e grava um quadro numa memória de dois clocks que o
-- processador lê pelo barramento. A configuração do chip é feita por I2C pelo
-- software, com outro periférico; este não fala I2C.
--
-- Domínios de clock:
--   - i_clk (sistema): registradores, ponteiro de leitura e interrupção;
--   - i_td_clk27 (decodificador): receptor, controle da captura, conversão
--     de cor e porta de escrita da memória.
-- O pedido de captura, o fim da captura, os erros do receptor e o reset
-- atravessam por toggle ou nível em sincronizadores de dois estágios; o
-- resultado da captura e a configuração de decimação, formato e campo são
-- vetores parados no momento em que o toggle os revela, e o .sdc da placa
-- deve cortá-los com set_false_path. O reset do sistema deve durar pelo menos
-- três ciclos de i_td_clk27. O topo só instancia e conecta as partes.
--
-- Mapa de endereços (palavra, ver tv_consts): 0 controle, 1 estado, 2 contador
-- de quadros, 3 decimação, 4 formato, 5 geometria, 6 ponteiro de leitura,
-- 7 dado de leitura e 8 área de origem.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.utils_pkg.all;
use work.tv_consts.all;

entity tv is
    generic (
        -- Largura da memória do quadro em pixels.
        fb_width         : positive := 160;
        -- Altura da memória do quadro em pixels.
        fb_height        : positive := 120;
        -- Largura em pixels da área de origem capturada (720 no NTSC).
        src_width        : positive := 720;
        -- Altura em linhas da área de origem capturada, dos dois campos (480 no NTSC).
        src_height       : positive := 480;
        -- Confere os bits de proteção dos códigos de temporização.
        check_protection : boolean  := true;
        -- Ciclos de TD_CLK27 sem código válido depois dos quais o vídeo é dado como ausente.
        present_cycles   : positive := 4096
    );
    port (
        -- Clock do sistema.
        i_clk         : in    std_logic;
        -- Reset síncrono do sistema, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de escrita do processador ('1' = escreve).
        i_write       : in    std_logic;
        -- Pulso de leitura do processador ('1' = lê).
        i_read        : in    std_logic;
        -- Endereço de palavra dentro do periférico.
        i_address     : in    std_logic_vector(TV_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq         : out   std_logic;
        -- Clock de 27 MHz do decodificador (TD_CLK27), assíncrono em relação a i_clk.
        i_td_clk27    : in    std_logic;
        -- Dados BT.656 do decodificador (TD_DATA).
        i_td_data     : in    std_logic_vector(7 downto 0);
        -- Reset do decodificador, ativo em '0' (TD_RESET_N).
        o_td_reset_n  : out   std_logic
    );
end entity tv;

architecture rtl of tv is

    -- Largura do índice de pixel.
    constant IDX_BITS  : positive := log2_ceil(fb_width * fb_height);
    -- Largura do endereço de palavra da memória do quadro.
    constant WORD_BITS : positive := IDX_BITS - 1;

    -- Reset do domínio do decodificador.
    signal rst27         : std_logic_vector(0 downto 0);
    -- Pedido de captura sincronizado em i_td_clk27.
    signal start_sync    : std_logic_vector(0 downto 0);
    -- Pedido de captura da borda anterior.
    signal start_prev    : std_logic := '0';
    -- Pulso de início de captura em i_td_clk27.
    signal start_pulse   : std_logic;
    -- Toggle de fim de captura em i_td_clk27.
    signal done_tog      : std_logic := '0';
    -- Toggle de erro do receptor em i_td_clk27.
    signal err_tog       : std_logic := '0';
    -- Vetor de nível e toggles em i_td_clk27 rumo ao sistema (presente, fim, erro).
    signal to_sys        : std_logic_vector(2 downto 0);
    -- Vetor sincronizado em i_clk.
    signal from_td       : std_logic_vector(2 downto 0);

    -- Pulso de início de linha ativa.
    signal line_start    : std_logic;
    -- Pulso de início de campo.
    signal field_start   : std_logic;
    -- Pulso de fim de campo.
    signal field_end     : std_logic;
    -- Pulso de erro do receptor.
    signal rx_error      : std_logic;
    -- Campo do último código.
    signal rx_field      : std_logic;
    -- Vídeo presente em i_td_clk27.
    signal present27     : std_logic;
    -- Pixel do receptor.
    signal rx_pix_valid  : std_logic;
    -- Luminância do receptor.
    signal rx_y          : std_logic_vector(7 downto 0);
    -- Crominância azul do receptor.
    signal rx_cb         : std_logic_vector(7 downto 0);
    -- Crominância vermelha do receptor.
    signal rx_cr         : std_logic_vector(7 downto 0);

    -- Fim de captura.
    signal cap_done      : std_logic;
    -- Resultado da captura.
    signal cap_ok        : std_logic;
    -- Pixel aceito.
    signal cap_we        : std_logic;
    -- Índice do pixel aceito.
    signal cap_index     : std_logic_vector(IDX_BITS - 1 downto 0);
    -- Formato do pixel aceito.
    signal cap_format    : std_logic;
    -- Luminância do pixel aceito.
    signal cap_y         : std_logic_vector(7 downto 0);
    -- Crominância azul do pixel aceito.
    signal cap_cb        : std_logic_vector(7 downto 0);
    -- Crominância vermelha do pixel aceito.
    signal cap_cr        : std_logic_vector(7 downto 0);

    -- Pedido de captura em i_clk.
    signal start_tog     : std_logic;
    -- Fatores e formato vindos dos registradores.
    signal x_div         : std_logic_vector(7 downto 0);
    -- Fator em y.
    signal y_div         : std_logic_vector(7 downto 0);
    -- Seletor de campo.
    signal field_sel     : std_logic_vector(1 downto 0);
    -- Formato do pixel.
    signal format        : std_logic;

    -- Escrita na memória: habilitação por byte.
    signal mem_we        : std_logic_vector(3 downto 0);
    -- Escrita na memória: endereço de palavra.
    signal mem_waddr     : std_logic_vector(WORD_BITS - 1 downto 0);
    -- Escrita na memória: dado.
    signal mem_wdata     : std_logic_vector(31 downto 0);
    -- Leitura da memória: endereço.
    signal mem_raddr     : std_logic_vector(WORD_BITS - 1 downto 0);
    -- Leitura da memória: dado.
    signal mem_rdata     : std_logic_vector(31 downto 0);

begin

    u_rst_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_td_clk27,
            i_rst => '0',
            i_d   => (0 => i_rst),
            o_d   => rst27
        );

    u_start_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_td_clk27,
            i_rst => '0',
            i_d   => (0 => start_tog),
            o_d   => start_sync
        );

    -- Toggles de fim de captura e de erro, e borda do pedido de captura.
    p_td_toggles : process (i_td_clk27) is
    begin

        if rising_edge(i_td_clk27) then
            start_prev <= start_sync(0);
            done_tog   <= done_tog xor cap_done;
            err_tog    <= err_tog xor rx_error;
        end if;

    end process p_td_toggles;

    start_pulse <= start_sync(0) xor start_prev;
    to_sys      <= err_tog & done_tog & present27;

    u_sys_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 3
        )
        port map (
            i_clk => i_clk,
            i_rst => '0',
            i_d   => to_sys,
            o_d   => from_td
        );

    u_rx : entity work.tv_bt656_rx
        generic map (
            check_protection => check_protection,
            present_cycles   => present_cycles
        )
        port map (
            i_clk         => i_td_clk27,
            i_rst         => rst27(0),
            i_data        => i_td_data,
            o_line_start  => line_start,
            o_field_start => field_start,
            o_field_end   => field_end,
            o_error       => rx_error,
            o_field       => rx_field,
            o_present     => present27,
            o_pix_valid   => rx_pix_valid,
            o_y           => rx_y,
            o_cb          => rx_cb,
            o_cr          => rx_cr
        );

    u_capture : entity work.tv_capture
        generic map (
            fb_width   => fb_width,
            fb_height  => fb_height,
            src_width  => src_width,
            src_height => src_height
        )
        port map (
            i_clk         => i_td_clk27,
            i_rst         => rst27(0),
            i_start       => start_pulse,
            i_x_div       => x_div,
            i_y_div       => y_div,
            i_field_sel   => field_sel,
            i_format      => format,
            i_line_start  => line_start,
            i_field_start => field_start,
            i_field_end   => field_end,
            i_field       => rx_field,
            i_present     => present27,
            i_pix_valid   => rx_pix_valid,
            i_y           => rx_y,
            i_cb          => rx_cb,
            i_cr          => rx_cr,
            o_busy        => open,
            o_done        => cap_done,
            o_ok          => cap_ok,
            o_we          => cap_we,
            o_index       => cap_index,
            o_format      => cap_format,
            o_y           => cap_y,
            o_cb          => cap_cb,
            o_cr          => cap_cr
        );

    u_color : entity work.tv_color
        generic map (
            idx_bits => IDX_BITS
        )
        port map (
            i_clk    => i_td_clk27,
            i_we     => cap_we,
            i_index  => cap_index,
            i_format => cap_format,
            i_y      => cap_y,
            i_cb     => cap_cb,
            i_cr     => cap_cr,
            o_we     => mem_we,
            o_waddr  => mem_waddr,
            o_wdata  => mem_wdata
        );

    u_frame : entity work.video_dpram
        generic map (
            lanes      => 4,
            lane_width => 8,
            depth      => frame_words(fb_width, fb_height),
            addr_width => WORD_BITS
        )
        port map (
            i_wclk  => i_td_clk27,
            i_we    => mem_we,
            i_waddr => mem_waddr,
            i_wdata => mem_wdata,
            i_rclk  => i_clk,
            i_raddr => mem_raddr,
            o_rdata => mem_rdata
        );

    u_regs : entity work.tv_regs
        generic map (
            fb_width   => fb_width,
            fb_height  => fb_height,
            src_width  => src_width,
            src_height => src_height
        )
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_write       => i_write,
            i_read        => i_read,
            i_address     => i_address,
            i_data_in     => i_data_in,
            o_data_out    => o_data_out,
            o_irq         => o_irq,
            i_present     => from_td(0),
            i_done_tog    => from_td(1),
            i_cap_ok      => cap_ok,
            i_err_tog     => from_td(2),
            o_start_tog   => start_tog,
            o_x_div       => x_div,
            o_y_div       => y_div,
            o_field_sel   => field_sel,
            o_format      => format,
            o_decoder_run => o_td_reset_n,
            o_rd_addr     => mem_raddr,
            i_rd_data     => mem_rdata
        );

end architecture rtl;

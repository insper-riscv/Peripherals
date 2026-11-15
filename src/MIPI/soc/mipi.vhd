-- =============================================================================
-- Periférico receptor de câmera MIPI CSI-2 com captura de quadro
--
-- Recebe, de uma ou mais lanes do D-PHY em alta velocidade, os pacotes do
-- CSI-2 (início e fim de quadro e linhas), confere o ECC do cabeçalho e o CRC
-- das linhas e grava um recorte do quadro numa memória de dois clocks que o
-- processador lê pelo barramento. O periférico recebe a entrada já amostrada
-- nas duas bordas do clock da câmera (o registrador DDR de entrada da
-- plataforma), dois bits por lane e por ciclo; ele não faz a recepção
-- elétrica do D-PHY nem vê os estados de baixo consumo, e não configura a
-- câmera, que o software programa por I2C com outro periférico. O topo só
-- instancia e conecta as partes.
--
-- Domínios de clock:
--   - i_clk (sistema): registradores, ponteiro de leitura e interrupção;
--   - i_mipi_clk (câmera): lanes, camada de pacotes, controle da captura e
--     porta de escrita da memória.
-- O pedido de captura e a habilitação atravessam por toggle e por nível em
-- sincronizadores de dois estágios; o fim da captura, os erros e o estado
-- atravessam o caminho inverso do mesmo modo, e o resultado da captura e a
-- configuração são vetores parados no momento em que o toggle os revela, e
-- o .sdc da placa deve cortá-los com set_false_path. O clock do sistema deve
-- ser mais rápido que um doze avos de i_mipi_clk, para que dois eventos
-- seguidos de erro não se confundam num toggle só.
--
-- Mapa de endereços (palavra, ver mipi_consts): 0 controle, 1 estado, 2
-- contador de quadros, 3 configuração, 4 geometria, 5 ponteiro de leitura, 6
-- dado de leitura, 7 último quadro, 8 contadores de erro e 9 informação.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.utils_pkg.all;
use work.mipi_consts.all;

entity mipi is
    generic (
        -- Quantidade de lanes de dados, 1, 2 ou 4.
        lanes         : positive range 1 to 4 := 2;
        -- Bytes por linha da memória do quadro, múltiplo de quatro.
        fb_line_bytes : positive              := 256;
        -- Linhas da memória do quadro.
        fb_lines      : positive              := 128;
        -- Tipo de dado das linhas guardadas depois do reset (0x2A, RAW8).
        default_dt    : natural range 0 to 63 := DT_RAW8
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
        i_address     : in    std_logic_vector(MIPI_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção, ativa em '1'.
        o_irq         : out   std_logic;
        -- Clock da câmera (clock do D-PHY), assíncrono em relação a i_clk.
        i_mipi_clk    : in    std_logic;
        -- Primeiro bit do par de cada lane, amostrado pelo registrador DDR em i_mipi_clk.
        i_mipi_early  : in    std_logic_vector(lanes - 1 downto 0);
        -- Segundo bit do par de cada lane, amostrado pelo registrador DDR em i_mipi_clk.
        i_mipi_late   : in    std_logic_vector(lanes - 1 downto 0)
    );
end entity mipi;

architecture rtl of mipi is

    -- Largura do endereço de palavra da memória do quadro.
    constant WORD_BITS : positive := log2_ceil(frame_words(fb_line_bytes, fb_lines));

    -- Reset do domínio da câmera, ativo em '1'.
    signal rst_rx       : std_logic;
    -- Habilitação sincronizada em i_mipi_clk.
    signal enable_sync  : std_logic_vector(0 downto 0);
    -- Pedido de captura sincronizado em i_mipi_clk.
    signal start_sync   : std_logic_vector(0 downto 0);
    -- Pedido de captura da borda anterior.
    signal start_prev   : std_logic := '0';
    -- Pulso de início de captura em i_mipi_clk.
    signal start_pulse  : std_logic;
    -- Pedido de captura entregue ao controle, um ciclo depois do reset do domínio sair.
    signal start_go     : std_logic;
    -- Pedido de captura guardado enquanto o domínio da câmera está em reset.
    signal start_pend   : std_logic := '0';
    -- Toggle de fim de captura em i_mipi_clk.
    signal done_tog     : std_logic := '0';
    -- Toggle de erro de ECC em i_mipi_clk.
    signal ecc_tog      : std_logic := '0';
    -- Toggle de erro de CRC em i_mipi_clk.
    signal crc_tog      : std_logic := '0';
    -- Toggle de descarte em i_mipi_clk.
    signal drop_tog     : std_logic := '0';
    -- Cabeçalho válido visto desde a habilitação, em i_mipi_clk.
    signal seen_rx      : std_logic := '0';
    -- Vetor de nível e toggles em i_mipi_clk rumo ao sistema (visto, fim, ECC, CRC, descarte).
    signal to_sys       : std_logic_vector(4 downto 0);
    -- Vetor sincronizado em i_clk.
    signal from_rx      : std_logic_vector(4 downto 0);

    -- Pedido de captura em i_clk.
    signal start_tog    : std_logic;
    -- Habilitação do receptor em i_clk.
    signal enable       : std_logic;
    -- Tipo de dado das linhas guardadas.
    signal data_type    : std_logic_vector(5 downto 0);
    -- Passo de linhas.
    signal y_step       : std_logic_vector(7 downto 0);

    -- Lanes alinhadas.
    signal lane_locked  : std_logic_vector(lanes - 1 downto 0);
    -- Byte válido de cada lane.
    signal lane_valid   : std_logic_vector(lanes - 1 downto 0);
    -- Bytes das lanes.
    signal lane_data    : std_logic_vector(lanes * 8 - 1 downto 0);
    -- Permissão de busca de sincronismo.
    signal arm          : std_logic;

    -- Cabeçalho com ECC correto.
    signal hdr_valid    : std_logic;
    -- Cabeçalho com ECC errado.
    signal hdr_bad      : std_logic;
    -- Pacote do cabeçalho é longo.
    signal hdr_long     : std_logic;
    -- Tipo de dado do cabeçalho.
    signal hdr_dt       : std_logic_vector(5 downto 0);
    -- Contagem de palavras do cabeçalho.
    signal hdr_wc       : std_logic_vector(15 downto 0);
    -- Grupo de carga útil.
    signal pix_valid    : std_logic;
    -- Bytes do grupo.
    signal pix_data     : std_logic_vector(lanes * 8 - 1 downto 0);
    -- Bytes válidos do grupo.
    signal pix_mask     : std_logic_vector(lanes - 1 downto 0);
    -- Fim de pacote.
    signal pkt_end      : std_logic;
    -- CRC do pacote correto.
    signal crc_ok       : std_logic;

    -- Fim de captura.
    signal cap_done     : std_logic;
    -- Resultado da captura.
    signal cap_ok       : std_logic;
    -- Linhas guardadas.
    signal cap_lines    : std_logic_vector(15 downto 0);
    -- Contagem de palavras da última linha.
    signal cap_wc       : std_logic_vector(15 downto 0);
    -- Evento de CRC errado.
    signal ev_crc       : std_logic;
    -- Evento de descarte.
    signal ev_drop      : std_logic;

    -- Escrita na memória, habilitação por byte.
    signal mem_we       : std_logic_vector(3 downto 0);
    -- Escrita na memória, endereço de palavra.
    signal mem_waddr    : std_logic_vector(WORD_BITS - 1 downto 0);
    -- Escrita na memória, dado.
    signal mem_wdata    : std_logic_vector(31 downto 0);
    -- Leitura da memória, endereço.
    signal mem_raddr    : std_logic_vector(WORD_BITS - 1 downto 0);
    -- Leitura da memória, dado.
    signal mem_rdata    : std_logic_vector(31 downto 0);

begin

    assert lanes /= 3
        report "mipi: lanes deve ser 1, 2 ou 4"
        severity failure;

    assert fb_line_bytes mod 4 = 0
        report "mipi: fb_line_bytes deve ser múltiplo de quatro"
        severity failure;

    u_enable_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_mipi_clk,
            i_rst => '0',
            i_d   => (0 => enable),
            o_d   => enable_sync
        );

    u_start_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_mipi_clk,
            i_rst => '0',
            i_d   => (0 => start_tog),
            o_d   => start_sync
        );

    rst_rx      <= not enable_sync(0);
    start_pulse <= start_sync(0) xor start_prev;
    start_go    <= start_pend and not rst_rx;
    to_sys      <= drop_tog & crc_tog & ecc_tog & done_tog & seen_rx;

    -- Toggles de fim de captura, de erro e de descarte, estado de cabeçalho visto e borda do pedido de captura.
    p_rx_toggles : process (i_mipi_clk) is
    begin

        if rising_edge(i_mipi_clk) then
            start_prev <= start_sync(0);

            if start_pulse = '1' then
                start_pend <= '1';
            elsif rst_rx = '0' then
                start_pend <= '0';
            end if;

            if rst_rx = '0' then
                done_tog <= done_tog xor cap_done;
                ecc_tog  <= ecc_tog xor hdr_bad;
                crc_tog  <= crc_tog xor ev_crc;
                drop_tog <= drop_tog xor ev_drop;

                if hdr_valid = '1' then
                    seen_rx <= '1';
                end if;
            else
                seen_rx <= '0';
            end if;
        end if;

    end process p_rx_toggles;

    u_sys_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 5
        )
        port map (
            i_clk => i_clk,
            i_rst => '0',
            i_d   => to_sys,
            o_d   => from_rx
        );

    gen_lane : for lane in 0 to lanes - 1 generate

        u_lane : entity work.mipi_lane_rx
            port map (
                i_clk       => i_mipi_clk,
                i_rst       => rst_rx,
                i_arm       => arm,
                i_bit_early => i_mipi_early(lane),
                i_bit_late  => i_mipi_late(lane),
                o_locked    => lane_locked(lane),
                o_valid     => lane_valid(lane),
                o_byte      => lane_data(lane * 8 + 7 downto lane * 8)
            );

    end generate gen_lane;

    u_packet : entity work.mipi_packet_rx
        generic map (
            lanes => lanes
        )
        port map (
            i_clk         => i_mipi_clk,
            i_rst         => rst_rx,
            i_lane_locked => lane_locked,
            i_lane_valid  => lane_valid,
            i_lane_data   => lane_data,
            o_arm         => arm,
            o_hdr_valid   => hdr_valid,
            o_hdr_bad     => hdr_bad,
            o_hdr_long    => hdr_long,
            o_hdr_dt      => hdr_dt,
            o_hdr_wc      => hdr_wc,
            o_pix_valid   => pix_valid,
            o_pix_data    => pix_data,
            o_pix_mask    => pix_mask,
            o_pkt_end     => pkt_end,
            o_crc_ok      => crc_ok
        );

    u_capture : entity work.mipi_capture
        generic map (
            lanes         => lanes,
            fb_line_bytes => fb_line_bytes,
            fb_lines      => fb_lines
        )
        port map (
            i_clk       => i_mipi_clk,
            i_rst       => rst_rx,
            i_start     => start_go,
            i_dt        => data_type,
            i_y_step    => y_step,
            i_hdr_valid => hdr_valid,
            i_hdr_long  => hdr_long,
            i_hdr_dt    => hdr_dt,
            i_hdr_wc    => hdr_wc,
            i_pix_valid => pix_valid,
            i_pix_data  => pix_data,
            i_pix_mask  => pix_mask,
            i_pkt_end   => pkt_end,
            i_crc_ok    => crc_ok,
            o_busy      => open,
            o_done      => cap_done,
            o_ok        => cap_ok,
            o_lines     => cap_lines,
            o_last_wc   => cap_wc,
            o_ev_crc    => ev_crc,
            o_ev_drop   => ev_drop,
            o_we        => mem_we,
            o_waddr     => mem_waddr,
            o_wdata     => mem_wdata
        );

    u_frame : entity work.video_dpram
        generic map (
            lanes      => 4,
            lane_width => 8,
            depth      => frame_words(fb_line_bytes, fb_lines),
            addr_width => WORD_BITS
        )
        port map (
            i_wclk  => i_mipi_clk,
            i_we    => mem_we,
            i_waddr => mem_waddr,
            i_wdata => mem_wdata,
            i_rclk  => i_clk,
            i_raddr => mem_raddr,
            o_rdata => mem_rdata
        );

    u_regs : entity work.mipi_regs
        generic map (
            lanes         => lanes,
            fb_line_bytes => fb_line_bytes,
            fb_lines      => fb_lines,
            default_dt    => default_dt
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_write     => i_write,
            i_read      => i_read,
            i_address   => i_address,
            i_data_in   => i_data_in,
            o_data_out  => o_data_out,
            o_irq       => o_irq,
            i_seen      => from_rx(0),
            i_done_tog  => from_rx(1),
            i_cap_ok    => cap_ok,
            i_cap_lines => cap_lines,
            i_cap_wc    => cap_wc,
            i_ecc_tog   => from_rx(2),
            i_crc_tog   => from_rx(3),
            i_drop_tog  => from_rx(4),
            o_start_tog => start_tog,
            o_dt        => data_type,
            o_y_step    => y_step,
            o_enable    => enable,
            o_rd_addr   => mem_raddr,
            i_rd_data   => mem_rdata
        );

end architecture rtl;

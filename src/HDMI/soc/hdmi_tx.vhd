-- =============================================================================
-- Periférico de saída de vídeo HDMI para o transmissor ADV7513
--
-- Liga o processador ao transmissor HDMI de uma placa (ADV7513 da DE10-Nano),
-- que recebe vídeo digital paralelo RGB 4:4:4 de 24 bits com DE, HS e VS e faz
-- a codificação TMDS. É um invólucro fino sobre os blocos do periférico de
-- vídeo (temporização por generics, memória de dois clocks e registradores do
-- framebuffer) e acrescenta o caminho de pixel de 24 bits, o registrador de
-- saída, os registradores do HDMI e, opcionalmente, o sequenciador que
-- inicializa o transmissor pelo I2C sem software.
--
-- Framebuffer: fb_width por fb_height pixels, ampliado scale vezes em x e em y
-- e centrado na área visível do modo. O formato é o generic pixel_format:
--   - "indexed": 8 bits por pixel, o índice de uma paleta de 256 entradas de
--     24 bits escrita pelo barramento;
--   - "direct": 16 bits por pixel em RGB565, expandido para 24 bits.
--
-- Temporização: o modo (área visível, pórticos, sincronismo e polaridade de
-- cada direção) vem dos generics, e o clock de pixel i_pixel_clk vem de um PLL
-- do topo da placa, assíncrono em relação a i_clk. Os modos CEA-861 usados e o
-- clock de cada um estão na documentação. o_tx_clk é o próprio i_pixel_clk, que
-- o topo leva ao pino HDMI_TX_CLK.
--
-- Inicialização: com init_enable, o sequenciador percorre init_table e depois
-- audio_init_table (a tabela de áudio, vazia por padrão) e escreve os pares
-- registrador-valor no transmissor (endereço de 7 bits i2c_dev_addr, a 100 kHz),
-- começando sozinho depois do reset se init_auto_start. Sem init_enable, o
-- barramento I2C fica livre para um controlador de software.
--
-- Domínios de clock:
--   - i_clk (sistema): registradores, janelas de escrita, I2C e interrupções;
--   - i_pixel_clk (pixel): temporização, leitura do framebuffer e saídas.
-- A exibição habilitada e o reset atravessam do sistema para o pixel por
-- sincronizadores de dois estágios; o pulso de sincronismo vertical, o
-- apagamento vertical, o pino de interrupção e o pino SDA atravessam para o
-- sistema pelo mesmo bloco. O reset do sistema deve durar pelo menos três
-- ciclos de i_pixel_clk. Os dados do framebuffer e da paleta nunca cruzam por
-- sincronizador, pois as memórias têm uma porta em cada clock.
--
-- Mapa de endereços (palavra): registradores do vídeo em 0 a 4, os do HDMI em
-- 8 a 14, paleta em 256 a 511 (só no formato indexado) e framebuffer, só de
-- escrita, na metade alta da janela.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.utils_pkg.all;
use work.video_consts.all;
use work.hdmi_consts.all;

entity hdmi_tx is
    generic (
        -- Frequência do clock do sistema em Hz (base do SCL do I2C).
        clk_freq          : positive := 100_000_000;
        -- Largura do framebuffer em pixels (uma linha deve ocupar um número inteiro de palavras de 32 bits).
        fb_width          : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height         : positive := 180;
        -- Formato do pixel do framebuffer: "indexed" (índice de paleta de 8 bits) ou "direct" (RGB565).
        pixel_format      : string   := "indexed";
        -- Fator de ampliação do pixel do framebuffer em x e em y (a imagem deve caber na área visível).
        scale             : positive := 4;
        -- Largura do endereço de palavra da janela do periférico (16 = janela de 256 KiB).
        addr_width        : positive := 16;
        -- Pixels visíveis por linha.
        h_visible         : positive := 1280;
        -- Pixels do pórtico frontal horizontal.
        h_front_porch     : natural  := 110;
        -- Pixels do pulso de sincronismo horizontal.
        h_sync            : positive := 40;
        -- Pixels do pórtico traseiro horizontal.
        h_back_porch      : natural  := 220;
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive   : boolean  := true;
        -- Linhas visíveis por quadro.
        v_visible         : positive := 720;
        -- Linhas do pórtico frontal vertical.
        v_front_porch     : natural  := 5;
        -- Linhas do pulso de sincronismo vertical.
        v_sync            : positive := 5;
        -- Linhas do pórtico traseiro vertical.
        v_back_porch      : natural  := 20;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive   : boolean  := true;
        -- Número do modo CEA-861 (VIC) da instância, ou zero para um modo próprio (só informativo).
        mode_id           : natural  := 4;
        -- Clock de pixel do modo em kHz (só informativo, o clock real vem do PLL do topo).
        pixel_clock_khz   : natural  := 74250;
        -- O sequenciador de inicialização do transmissor existe nesta instância.
        init_enable       : boolean  := false;
        -- A sequência começa sozinha depois do reset.
        init_auto_start   : boolean  := true;
        -- Tabela de inicialização: quatro dígitos hexadecimais por entrada, registrador e depois valor.
        init_table        : string   := "";
        -- Tabela de áudio do transmissor, escrita depois da init_table, no mesmo formato; vazia por padrão.
        audio_init_table  : string   := "";
        -- Endereço de 7 bits do transmissor no barramento I2C.
        i2c_dev_addr      : std_logic_vector(6 downto 0) := "0111001";
        -- Frequência do SCL do I2C em Hz.
        i2c_freq          : positive := 100_000;
        -- O pino de interrupção do transmissor é ativo em nível baixo.
        int_active_low    : boolean  := true
    );
    port (
        -- Clock do sistema.
        i_clk        : in    std_logic;
        -- Clock de pixel do modo, assíncrono em relação a i_clk.
        i_pixel_clk  : in    std_logic;
        -- Reset síncrono do sistema, ativo em '1'.
        i_rst        : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in    : in    std_logic_vector(31 downto 0);
        -- Endereço de palavra dentro do periférico.
        i_address    : in    std_logic_vector(addr_width - 1 downto 0);
        -- Habilitação de bytes da escrita, um bit por byte.
        i_byteena    : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write      : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out   : out   std_logic_vector(31 downto 0);
        -- Interrupção em nível (fim de quadro ou pino de interrupção do transmissor, conforme as máscaras).
        o_irq        : out   std_logic;

        -- Barramento de vídeo RGB de 24 bits (HDMI_TX_D[23:0]), vermelho em 23:16.
        o_tx_d       : out   std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);
        -- Clock de pixel para o transmissor (HDMI_TX_CLK).
        o_tx_clk     : out   std_logic;
        -- Habilitação de dados (HDMI_TX_DE).
        o_tx_de      : out   std_logic;
        -- Sincronismo horizontal (HDMI_TX_HS).
        o_tx_hs      : out   std_logic;
        -- Sincronismo vertical (HDMI_TX_VS).
        o_tx_vs      : out   std_logic;
        -- Pino de interrupção do transmissor (HDMI_TX_INT), assíncrono.
        i_tx_int     : in    std_logic;

        -- Linha SDA do I2C lida do pino (I2C_SDA), assíncrona.
        i_i2c_sda     : in    std_logic;
        -- Valor que o periférico leva a SDA quando a habilita (sempre '0').
        o_i2c_sda_out : out   std_logic;
        -- Habilitação de saída de SDA ('1' = SDA puxada para baixo).
        o_i2c_sda_oe  : out   std_logic;
        -- Valor que o periférico leva a SCL quando a habilita (sempre '0').
        o_i2c_scl_out : out   std_logic;
        -- Habilitação de saída de SCL ('1' = SCL puxada para baixo).
        o_i2c_scl_oe  : out   std_logic
    );
end entity hdmi_tx;

architecture rtl of hdmi_tx is

    -- Largura de canal que dimensiona o framebuffer e a paleta nos blocos do vídeo.
    constant SIZE_BITS    : positive := size_channel_bits(pixel_format);
    -- Bits que cada pixel ocupa no framebuffer.
    constant PIXEL_BITS   : positive := pixel_storage_bits(pixel_format, SIZE_BITS);
    -- Palavras do framebuffer.
    constant FB_DEPTH     : positive := fb_words(fb_width, fb_height, PIXEL_BITS);
    -- Largura do endereço de palavra do framebuffer.
    constant FB_ADDR_BITS : positive := log2_ceil(FB_DEPTH);
    -- Bits de uma cor de 24 bits.
    constant COLOR_BITS   : positive := 3 * OUT_CHANNEL_BITS;
    -- Entradas da tabela de inicialização (zero sem o sequenciador).
    constant INIT_ENTRIES : natural  := pick(init_enable, init_count(init_table) + init_count(audio_init_table), 0);

    -- Reset do sistema levado ao domínio de pixel, em vetor de um bit.
    signal pix_rst_vec    : std_logic_vector(0 downto 0);
    -- Reset no domínio de pixel.
    signal pix_rst        : std_logic;
    -- Exibição habilitada no domínio do sistema, em vetor de um bit.
    signal enable_sys     : std_logic_vector(0 downto 0);
    -- Exibição habilitada no domínio de pixel, em vetor de um bit.
    signal enable_pix_vec : std_logic_vector(0 downto 0);
    -- Estado do quadro no domínio de pixel: bit 1 apagamento vertical, bit 0 sincronismo vertical.
    signal frame_pix      : std_logic_vector(1 downto 0);
    -- Estado do quadro sincronizado no domínio do sistema.
    signal frame_sys      : std_logic_vector(1 downto 0);
    -- Pinos assíncronos do sistema (interrupção do transmissor e SDA), em vetor de dois bits.
    signal pins_async     : std_logic_vector(1 downto 0);
    -- Pinos assíncronos sincronizados em i_clk.
    signal pins_sync      : std_logic_vector(1 downto 0);
    -- Pino de interrupção do transmissor ativo, já sincronizado.
    signal int_active     : std_logic;
    -- SDA sincronizada em i_clk.
    signal sda_sync       : std_logic;

    -- Dado de escrita registrado dos registradores do vídeo.
    signal wdata        : std_logic_vector(31 downto 0);
    -- Habilitação de escrita por faixa do framebuffer.
    signal fb_we        : std_logic_vector(3 downto 0);
    -- Endereço de escrita do framebuffer.
    signal fb_waddr     : std_logic_vector(FB_ADDR_BITS - 1 downto 0);
    -- Habilitação de escrita da paleta.
    signal pal_we       : std_logic;
    -- Índice de escrita da paleta.
    signal pal_waddr    : std_logic_vector(PALETTE_ADDR_BITS - 1 downto 0);
    -- Endereço de leitura do framebuffer, vindo da varredura.
    signal fb_raddr     : std_logic_vector(FB_ADDR_BITS - 1 downto 0);
    -- Palavra lida do framebuffer.
    signal fb_rdata     : std_logic_vector(31 downto 0);
    -- Índice de leitura da paleta, vindo da varredura.
    signal pal_raddr    : std_logic_vector(PALETTE_ADDR_BITS - 1 downto 0);
    -- Cor lida da paleta (zero quando não há paleta).
    signal pal_rdata    : std_logic_vector(COLOR_BITS - 1 downto 0);
    -- Habilitação de escrita da paleta como vetor de uma faixa.
    signal pal_we_vec   : std_logic_vector(0 downto 0);
    -- Dado de escrita da paleta, os bits baixos da palavra escrita.
    signal pal_wdata    : std_logic_vector(COLOR_BITS - 1 downto 0);

    -- Leitura dos registradores do vídeo.
    signal video_dout   : std_logic_vector(31 downto 0);
    -- Leitura dos registradores do HDMI.
    signal hdmi_dout    : std_logic_vector(31 downto 0);

    -- Sincronismo horizontal do gerador de temporização.
    signal hs         : std_logic;
    -- Sincronismo vertical do gerador de temporização.
    signal vs         : std_logic;
    -- Marca de pixel dentro da área visível do modo.
    signal visible    : std_logic;
    -- Marca de pixel dentro do retângulo da imagem.
    signal image      : std_logic;
    -- Coluna do framebuffer do pixel atual.
    signal fb_x       : std_logic_vector(log2_ceil(fb_width + 1) - 1 downto 0);
    -- Linha do framebuffer do pixel atual.
    signal fb_y       : std_logic_vector(log2_ceil(fb_height + 1) - 1 downto 0);
    -- Exibição habilitada no domínio de pixel.
    signal enable_pix : std_logic;

    -- Cor de 24 bits da varredura.
    signal color        : std_logic_vector(COLOR_BITS - 1 downto 0);
    -- A cor deve ser exibida no pixel que sai da varredura.
    signal lit          : std_logic;
    -- Área visível alinhada com a cor.
    signal scan_visible : std_logic;
    -- Sincronismo horizontal alinhado com a cor.
    signal scan_hs      : std_logic;
    -- Sincronismo vertical alinhado com a cor.
    signal scan_vs      : std_logic;

    -- Pedido de reinício do sequenciador, vindo dos registradores.
    signal seq_start    : std_logic;
    -- Pedido de escrita do sequenciador ao escritor I2C.
    signal wr_start     : std_logic;
    -- Registrador a escrever.
    signal wr_reg       : std_logic_vector(7 downto 0);
    -- Valor a escrever.
    signal wr_value     : std_logic_vector(7 downto 0);
    -- Fim da escrita I2C.
    signal wr_done      : std_logic;
    -- A escrita I2C terminada não foi confirmada.
    signal wr_nack      : std_logic;
    -- Estado do sequenciador: ocupado.
    signal seq_busy     : std_logic;
    -- Estado do sequenciador: concluído.
    signal seq_done     : std_logic;
    -- Estado do sequenciador: alguma escrita sem confirmação.
    signal seq_nack     : std_logic;
    -- Entradas concluídas.
    signal seq_sent     : std_logic_vector(7 downto 0);
    -- Escritas sem confirmação.
    signal seq_nacks    : std_logic_vector(7 downto 0);

begin

    assert is_valid_format(pixel_format)
        report "hdmi_tx: pixel_format deve ser indexed ou direct"
        severity failure;
    assert is_valid_table(init_table) and is_valid_table(audio_init_table) and
          init_count(init_table) + init_count(audio_init_table) <= MAX_INIT_ENTRIES
        report "hdmi_tx: init_table e audio_init_table devem ter quatro dígitos hexadecimais por entrada, " &
               "no máximo 255 entradas juntas"
        severity failure;

    o_tx_clk      <= i_pixel_clk;
    o_data_out    <= video_dout or hdmi_dout;
    pins_async(0) <= i_tx_int;
    pins_async(1) <= i_i2c_sda;

    u_rst_sync : entity work.synchronizer
        port map (
            i_clk => i_pixel_clk,
            i_rst => '0',
            i_d   => (0 => i_rst),
            o_d   => pix_rst_vec
        );

    pix_rst <= pix_rst_vec(0);

    u_enable_sync : entity work.synchronizer
        port map (
            i_clk => i_pixel_clk,
            i_rst => pix_rst,
            i_d   => enable_sys,
            o_d   => enable_pix_vec
        );

    enable_pix <= enable_pix_vec(0);

    u_frame_sync : entity work.synchronizer
        generic map (
            data_width => 2
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d   => frame_pix,
            o_d   => frame_sys
        );

    u_pins_sync : entity work.synchronizer
        generic map (
            data_width => 2
        )
        port map (
            i_clk => i_clk,
            i_rst => '0',
            i_d   => pins_async,
            o_d   => pins_sync
        );

    -- O nível ativo do pino é o oposto do repouso: '0' se o pino é ativo em nível baixo, '1' se é em nível alto.
    int_active <= pins_sync(0) xor to_sl(int_active_low);
    sda_sync   <= pins_sync(1);

    u_regs : entity work.video_regs
        generic map (
            fb_width     => fb_width,
            fb_height    => fb_height,
            channel_bits => SIZE_BITS,
            pixel_format => pixel_format,
            scale        => scale,
            addr_width   => addr_width
        )
        port map (
            i_clk      => i_clk,
            i_rst      => i_rst,
            i_data_in  => i_data_in,
            i_address  => i_address,
            i_byteena  => i_byteena,
            i_write    => i_write,
            o_data_out => video_dout,
            i_vsync    => frame_sys(0),
            i_vblank   => frame_sys(1),
            o_enable   => enable_sys(0),
            o_wdata    => wdata,
            o_fb_we    => fb_we,
            o_fb_addr  => fb_waddr,
            o_pal_we   => pal_we,
            o_pal_addr => pal_waddr
        );

    u_hdmi_regs : entity work.hdmi_regs
        generic map (
            addr_width      => addr_width,
            mode_id         => mode_id,
            pixel_clock_khz => pixel_clock_khz,
            h_sync_positive => h_sync_positive,
            v_sync_positive => v_sync_positive,
            init_entries    => INIT_ENTRIES,
            init_enable     => init_enable
        )
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_data_in    => i_data_in,
            i_address    => i_address,
            i_write      => i_write,
            o_data_out   => hdmi_dout,
            i_vblank     => frame_sys(1),
            i_int_active => int_active,
            i_seq_busy   => seq_busy,
            i_seq_done   => seq_done,
            i_seq_nack   => seq_nack,
            i_seq_sent   => seq_sent,
            i_seq_nacks  => seq_nacks,
            o_seq_start  => seq_start,
            o_irq        => o_irq
        );

    u_fb_ram : entity work.video_dpram
        generic map (
            lanes      => 4,
            lane_width => 8,
            depth      => FB_DEPTH,
            addr_width => FB_ADDR_BITS
        )
        port map (
            i_wclk  => i_clk,
            i_we    => fb_we,
            i_waddr => fb_waddr,
            i_wdata => wdata,
            i_rclk  => i_pixel_clk,
            i_raddr => fb_raddr,
            o_rdata => fb_rdata
        );

    gen_palette : if is_indexed(pixel_format) generate
        pal_we_vec(0) <= pal_we;
        pal_wdata     <= wdata(COLOR_BITS - 1 downto 0);

        u_pal_ram : entity work.video_dpram
            generic map (
                lanes      => 1,
                lane_width => COLOR_BITS,
                depth      => PALETTE_ENTRIES,
                addr_width => PALETTE_ADDR_BITS
            )
            port map (
                i_wclk  => i_clk,
                i_we    => pal_we_vec,
                i_waddr => pal_waddr,
                i_wdata => pal_wdata,
                i_rclk  => i_pixel_clk,
                i_raddr => pal_raddr,
                o_rdata => pal_rdata
            );
    end generate gen_palette;

    gen_no_palette : if not is_indexed(pixel_format) generate
        pal_we_vec <= (others => '0');
        pal_wdata  <= (others => '0');
        pal_rdata  <= (others => '0');
    end generate gen_no_palette;

    u_timing : entity work.video_timing
        generic map (
            fb_width        => fb_width,
            fb_height       => fb_height,
            scale           => scale,
            h_visible       => h_visible,
            h_front_porch   => h_front_porch,
            h_sync          => h_sync,
            h_back_porch    => h_back_porch,
            h_sync_positive => h_sync_positive,
            v_visible       => v_visible,
            v_front_porch   => v_front_porch,
            v_sync          => v_sync,
            v_back_porch    => v_back_porch,
            v_sync_positive => v_sync_positive
        )
        port map (
            i_clk     => i_pixel_clk,
            i_rst     => pix_rst,
            o_hs      => hs,
            o_vs      => vs,
            o_vsync   => frame_pix(0),
            o_vblank  => frame_pix(1),
            o_visible => visible,
            o_image   => image,
            o_fb_x    => fb_x,
            o_fb_y    => fb_y
        );

    u_scanout : entity work.hdmi_scanout
        generic map (
            fb_width     => fb_width,
            fb_height    => fb_height,
            pixel_format => pixel_format,
            h_sync_positive => h_sync_positive,
            v_sync_positive => v_sync_positive
        )
        port map (
            i_clk      => i_pixel_clk,
            i_rst      => pix_rst,
            i_enable   => enable_pix,
            i_hs       => hs,
            i_vs       => vs,
            i_visible  => visible,
            i_image    => image,
            i_fb_x     => fb_x,
            i_fb_y     => fb_y,
            o_fb_addr  => fb_raddr,
            i_fb_data  => fb_rdata,
            o_pal_addr => pal_raddr,
            i_pal_data => pal_rdata,
            o_color    => color,
            o_lit      => lit,
            o_visible  => scan_visible,
            o_hs       => scan_hs,
            o_vs       => scan_vs
        );

    u_out : entity work.hdmi_out
        generic map (
            h_sync_positive => h_sync_positive,
            v_sync_positive => v_sync_positive
        )
        port map (
            i_clk     => i_pixel_clk,
            i_rst     => pix_rst,
            i_color   => color,
            i_lit     => lit,
            i_visible => scan_visible,
            i_hs      => scan_hs,
            i_vs      => scan_vs,
            o_d       => o_tx_d,
            o_de      => o_tx_de,
            o_hs      => o_tx_hs,
            o_vs      => o_tx_vs
        );

    gen_init : if init_enable generate
        u_seq : entity work.hdmi_init_seq
            generic map (
                init_table => init_table,
                audio_table => audio_init_table,
                auto_start => init_auto_start
            )
            port map (
                i_clk       => i_clk,
                i_rst       => i_rst,
                i_start     => seq_start,
                o_wr_start  => wr_start,
                o_wr_reg    => wr_reg,
                o_wr_value  => wr_value,
                i_wr_done   => wr_done,
                i_wr_nack   => wr_nack,
                o_busy      => seq_busy,
                o_done      => seq_done,
                o_nack_seen => seq_nack,
                o_sent      => seq_sent,
                o_nacks     => seq_nacks
            );

        u_i2c : entity work.hdmi_i2c_writer
            generic map (
                clk_freq => clk_freq,
                i2c_freq => i2c_freq,
                dev_addr => i2c_dev_addr
            )
            port map (
                i_clk     => i_clk,
                i_rst     => i_rst,
                i_start   => wr_start,
                i_reg     => wr_reg,
                i_value   => wr_value,
                o_busy    => open,
                o_done    => wr_done,
                o_nack    => wr_nack,
                i_sda     => sda_sync,
                o_sda_out => o_i2c_sda_out,
                o_sda_oe  => o_i2c_sda_oe,
                o_scl_out => o_i2c_scl_out,
                o_scl_oe  => o_i2c_scl_oe
            );
    end generate gen_init;

    gen_no_init : if not init_enable generate
        wr_start      <= '0';
        wr_reg        <= (others => '0');
        wr_value      <= (others => '0');
        wr_done       <= '0';
        wr_nack       <= '0';
        seq_busy      <= '0';
        seq_done      <= '0';
        seq_nack      <= '0';
        seq_sent      <= (others => '0');
        seq_nacks     <= (others => '0');
        o_i2c_sda_out <= '0';
        o_i2c_sda_oe  <= '0';
        o_i2c_scl_out <= '0';
        o_i2c_scl_oe  <= '0';
    end generate gen_no_init;

end architecture rtl;

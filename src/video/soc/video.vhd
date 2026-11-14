-- =============================================================================
-- Periférico de vídeo VGA genérico com framebuffer de dois clocks
--
-- Liga o processador a um conversor VGA da placa, sem nada de placa dentro: a
-- temporização do modo (área visível, pórticos, sincronismo e polaridade de
-- cada direção) e a largura do canal de cor (4 bits nos conversores
-- resistivos da DE0-CV, 8 bits no ADV7123 da DE2-115) chegam por generics, e
-- os valores padrão são os do modo 640x480 a 60 Hz com 4 bits por canal. O
-- framebuffer de fb_width por fb_height pixels fica em memória de duas
-- portas: o processador escreve, 32 bits por acesso e com máscara de bytes, no
-- clock do sistema, e a varredura lê no clock de pixel. Cada pixel do
-- framebuffer é ampliado scale vezes em x e em y e a imagem fica centrada na
-- área visível, com faixas pretas nas bordas que sobram.
--
-- O formato do pixel é o generic pixel_format:
--   - "indexed": 8 bits por pixel, o índice de uma paleta de 256 entradas de
--     3 x channel_bits bits, escrita pelo barramento do periférico;
--   - "direct": a cor de 3 x channel_bits bits no próprio pixel, guardada em
--     16 bits (até 5 bits por canal) ou 32 bits.
--
-- Domínios de clock:
--   - i_clk (sistema): registradores, janelas de escrita e contador de quadros;
--   - i_pixel_clk (pixel): temporização, leitura do framebuffer e saídas VGA.
-- A exibição habilitada e o reset atravessam do sistema para o pixel por
-- sincronizadores de dois estágios; o pulso de sincronismo vertical e o
-- apagamento vertical atravessam do pixel para o sistema pelo mesmo bloco. O
-- reset do sistema deve durar pelo menos três ciclos de i_pixel_clk. Os dados
-- do framebuffer e da paleta nunca cruzam por sincronizador, pois as memórias
-- têm uma porta em cada clock. O topo só instancia e conecta as partes.
--
-- Mapa de endereços (palavra, ver video_regs): registradores em 0 a 4, paleta em
-- 256 a 511 (só no formato indexado) e framebuffer, só de escrita, na metade
-- alta da janela.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.utils_pkg.all;
use work.video_consts.all;

entity video is
    generic (
        -- Largura do framebuffer em pixels (uma linha deve ocupar um número inteiro de palavras de 32 bits).
        fb_width        : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height       : positive := 200;
        -- Bits de cada canal de cor do conversor da placa (4 na DE0-CV, 8 na DE2-115).
        channel_bits    : positive := 4;
        -- Formato do pixel do framebuffer: "indexed" (índice de paleta de 8 bits) ou "direct" (cor no pixel).
        pixel_format    : string   := "indexed";
        -- Fator de ampliação do pixel do framebuffer em x e em y (a imagem deve caber na área visível).
        scale           : positive := 2;
        -- Largura do endereço de palavra da janela do periférico (16 = janela de 256 KiB).
        addr_width      : positive := 16;
        -- Pixels visíveis por linha.
        h_visible       : positive := 640;
        -- Pixels do pórtico frontal horizontal.
        h_front_porch   : natural  := 16;
        -- Pixels do pulso de sincronismo horizontal.
        h_sync          : positive := 96;
        -- Pixels do pórtico traseiro horizontal.
        h_back_porch    : natural  := 48;
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive : boolean  := false;
        -- Linhas visíveis por quadro.
        v_visible       : positive := 480;
        -- Linhas do pórtico frontal vertical.
        v_front_porch   : natural  := 10;
        -- Linhas do pulso de sincronismo vertical.
        v_sync          : positive := 2;
        -- Linhas do pórtico traseiro vertical.
        v_back_porch    : natural  := 33;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive : boolean  := false
    );
    port (
        -- Clock do sistema.
        i_clk       : in    std_logic;
        -- Clock de pixel do modo (25 MHz no 640x480 a 60 Hz), assíncrono em relação a i_clk.
        i_pixel_clk : in    std_logic;
        -- Reset síncrono do sistema, ativo em '1'.
        i_rst       : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra dentro do periférico.
        i_address  : in    std_logic_vector(addr_width - 1 downto 0);
        -- Habilitação de bytes da escrita, um bit por byte.
        i_byteena  : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write    : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out : out   word_t;

        -- Canal vermelho do conversor VGA da placa.
        o_vga_r       : out   std_logic_vector(channel_bits - 1 downto 0);
        -- Canal verde do conversor VGA da placa.
        o_vga_g       : out   std_logic_vector(channel_bits - 1 downto 0);
        -- Canal azul do conversor VGA da placa.
        o_vga_b       : out   std_logic_vector(channel_bits - 1 downto 0);
        -- Sincronismo horizontal VGA, com a polaridade do modo.
        o_vga_hs      : out   std_logic;
        -- Sincronismo vertical VGA, com a polaridade do modo.
        o_vga_vs      : out   std_logic;
        -- Apagamento do conversor (BLANK_N do ADV7123), baixo fora da área visível.
        o_vga_blank_n : out   std_logic;
        -- Sincronismo composto do conversor (SYNC_N do ADV7123), sempre em '0'.
        o_vga_sync_n  : out   std_logic
    );
end entity video;

architecture rtl of video is

    -- Bits que cada pixel ocupa no framebuffer.
    constant PIXEL_BITS   : positive := pixel_storage_bits(pixel_format, channel_bits);
    -- Palavras do framebuffer.
    constant FB_DEPTH     : positive := fb_words(fb_width, fb_height, PIXEL_BITS);
    -- Largura do endereço de palavra do framebuffer.
    constant FB_ADDR_BITS : positive := log2_ceil(FB_DEPTH);
    -- Bits de uma cor (três canais).
    constant COLOR_BITS   : positive := 3 * channel_bits;

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

    -- Dado de escrita registrado dos registradores.
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

    -- Cor decodificada pela varredura.
    signal color        : std_logic_vector(COLOR_BITS - 1 downto 0);
    -- A cor deve ser exibida no pixel que sai da varredura.
    signal lit          : std_logic;
    -- Área visível alinhada com a cor.
    signal scan_visible : std_logic;
    -- Sincronismo horizontal alinhado com a cor.
    signal scan_hs      : std_logic;
    -- Sincronismo vertical alinhado com a cor.
    signal scan_vs      : std_logic;

begin

    assert is_valid_format(pixel_format)
        report "video: pixel_format deve ser indexed ou direct"
        severity failure;
    assert channel_bits <= MAX_CHANNEL_BITS
        report "video: três canais devem caber em 32 bits"
        severity failure;

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

    u_regs : entity work.video_regs
        generic map (
            fb_width     => fb_width,
            fb_height    => fb_height,
            channel_bits => channel_bits,
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
            o_data_out => o_data_out,
            i_vsync    => frame_sys(0),
            i_vblank   => frame_sys(1),
            o_enable   => enable_sys(0),
            o_wdata    => wdata,
            o_fb_we    => fb_we,
            o_fb_addr  => fb_waddr,
            o_pal_we   => pal_we,
            o_pal_addr => pal_waddr
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

    u_scanout : entity work.video_scanout
        generic map (
            fb_width     => fb_width,
            fb_height    => fb_height,
            channel_bits => channel_bits,
            pixel_format => pixel_format
        )
        port map (
            i_clk      => i_pixel_clk,
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

    u_vga : entity work.video_vga
        generic map (
            channel_bits    => channel_bits,
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
            o_r       => o_vga_r,
            o_g       => o_vga_g,
            o_b       => o_vga_b,
            o_hs      => o_vga_hs,
            o_vs      => o_vga_vs,
            o_blank_n => o_vga_blank_n,
            o_sync_n  => o_vga_sync_n
        );

end architecture rtl;

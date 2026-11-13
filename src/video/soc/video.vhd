-- =============================================================================
-- Periférico de vídeo VGA 640x480 a 60 Hz com framebuffer de dois clocks
--
-- Liga o processador a um conversor VGA resistivo de 4 bits por canal. O
-- framebuffer de fb_width por fb_height pixels fica em memória de duas portas:
-- o processador escreve, 32 bits por acesso e com máscara de bytes, no clock do
-- sistema, e a varredura lê no clock de pixel. Cada pixel do framebuffer é
-- ampliado scale vezes em x e em y e a imagem fica centrada no quadro VGA, com
-- faixas pretas nas bordas que sobram.
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
-- 256 a 511 (só com pixel_bits = 8) e framebuffer, só de escrita, na metade
-- alta da janela.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.utils_pkg.all;
use work.video_consts.all;

entity video is
    generic (
        -- Largura do framebuffer em pixels (múltiplo de 32 / pixel_bits).
        fb_width   : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height  : positive := 200;
        -- Bits por pixel do framebuffer: 16 guarda RGB444 e 8 guarda o índice de uma paleta de 256 cores.
        pixel_bits : positive := 16;
        -- Fator de ampliação do pixel do framebuffer em x e em y (a imagem deve caber em 640x480).
        scale      : positive := 2;
        -- Largura do endereço de palavra da janela do periférico (16 = janela de 256 KiB).
        addr_width : positive := 16
    );
    port (
        -- Clock do sistema.
        i_clk       : in    std_logic;
        -- Clock de pixel (25 MHz para 60 Hz), assíncrono em relação a i_clk.
        i_pixel_clk : in    std_logic;
        -- Reset síncrono do sistema, ativo em '1'.
        i_rst       : in    std_logic;

        -- Dado de escrita vindo do processador.
        i_data_in  : in    std_logic_vector(31 downto 0);
        -- Endereço de palavra dentro do periférico.
        i_address  : in    std_logic_vector(addr_width - 1 downto 0);
        -- Habilitação de bytes da escrita, um bit por byte.
        i_byteena  : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write    : in    std_logic;
        -- Dado de leitura para o processador.
        o_data_out : out   std_logic_vector(31 downto 0);

        -- Canal vermelho do conversor VGA da placa.
        o_vga_r  : out   std_logic_vector(CHANNEL_BITS - 1 downto 0);
        -- Canal verde do conversor VGA da placa.
        o_vga_g  : out   std_logic_vector(CHANNEL_BITS - 1 downto 0);
        -- Canal azul do conversor VGA da placa.
        o_vga_b  : out   std_logic_vector(CHANNEL_BITS - 1 downto 0);
        -- Sincronismo horizontal VGA, ativo em nível baixo.
        o_vga_hs : out   std_logic;
        -- Sincronismo vertical VGA, ativo em nível baixo.
        o_vga_vs : out   std_logic
    );
end entity video;

architecture rtl of video is

    -- Palavras do framebuffer.
    constant FB_DEPTH     : positive := fb_words(fb_width, fb_height, pixel_bits);
    -- Largura do endereço de palavra do framebuffer.
    constant FB_ADDR_BITS : positive := log2_ceil(FB_DEPTH);

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
    -- Dado de escrita da paleta, os 12 bits baixos da palavra escrita.
    signal pal_wdata    : std_logic_vector(COLOR_BITS - 1 downto 0);

    -- Sincronismo horizontal do gerador de temporização.
    signal hs        : std_logic;
    -- Sincronismo vertical do gerador de temporização.
    signal vs        : std_logic;
    -- Marca de pixel dentro do retângulo da imagem.
    signal image     : std_logic;
    -- Coluna do framebuffer do pixel atual.
    signal fb_x      : std_logic_vector(log2_ceil(fb_width + 1) - 1 downto 0);
    -- Linha do framebuffer do pixel atual.
    signal fb_y      : std_logic_vector(log2_ceil(fb_height + 1) - 1 downto 0);
    -- Exibição habilitada no domínio de pixel.
    signal enable_pix : std_logic;

begin

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
            fb_width   => fb_width,
            fb_height  => fb_height,
            pixel_bits => pixel_bits,
            scale      => scale,
            addr_width => addr_width
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

    gen_palette : if pixel_bits = 8 generate
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

    gen_no_palette : if pixel_bits /= 8 generate
        pal_we_vec <= (others => '0');
        pal_wdata  <= (others => '0');
        pal_rdata  <= (others => '0');
    end generate gen_no_palette;

    u_timing : entity work.video_timing
        generic map (
            fb_width  => fb_width,
            fb_height => fb_height,
            scale     => scale
        )
        port map (
            i_clk    => i_pixel_clk,
            i_rst    => pix_rst,
            o_hs     => hs,
            o_vs     => vs,
            o_vsync  => frame_pix(0),
            o_vblank => frame_pix(1),
            o_image  => image,
            o_fb_x   => fb_x,
            o_fb_y   => fb_y
        );

    u_scanout : entity work.video_scanout
        generic map (
            fb_width   => fb_width,
            fb_height  => fb_height,
            pixel_bits => pixel_bits
        )
        port map (
            i_clk      => i_pixel_clk,
            i_rst      => pix_rst,
            i_enable   => enable_pix,
            i_hs       => hs,
            i_vs       => vs,
            i_image    => image,
            i_fb_x     => fb_x,
            i_fb_y     => fb_y,
            o_fb_addr  => fb_raddr,
            i_fb_data  => fb_rdata,
            o_pal_addr => pal_raddr,
            i_pal_data => pal_rdata,
            o_vga_r    => o_vga_r,
            o_vga_g    => o_vga_g,
            o_vga_b    => o_vga_b,
            o_vga_hs   => o_vga_hs,
            o_vga_vs   => o_vga_vs
        );

end architecture rtl;

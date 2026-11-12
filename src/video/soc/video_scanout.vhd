-- =============================================================================
-- Caminho de pixel do VGA: endereço, decodificação de cor e saída registrada
--
-- Domínio do clock de pixel. Converte as coordenadas do framebuffer em
-- endereço de palavra da memória (o_fb_addr), escolhe o pixel dentro da
-- palavra lida e o converte em três canais de CHANNEL_BITS bits:
--   - pixel_bits = 16: RGB444 nos 12 bits menos significativos do pixel
--     (vermelho 11:8, verde 7:4, azul 3:0); os 4 bits altos são ignorados;
--   - pixel_bits = 8: o byte é o índice de uma paleta de 256 entradas RGB444,
--     lida pela porta o_pal_addr e i_pal_data.
-- Os pixels de uma palavra seguem a ordem do barramento: o pixel de menor
-- índice ocupa os bits menos significativos.
--
-- Latência: as memórias leem em um ciclo, a escolha do pixel leva outro e a
-- saída registrada um terceiro. Os sinais i_hs, i_vs e i_image atravessam o
-- mesmo número de estágios, de modo que as cores e os sincronismos saem
-- alinhados, três ciclos depois das coordenadas. Com i_enable = '0' ou fora do
-- retângulo da imagem as três cores saem pretas.
--
-- Prioridade: i_rst = '1' (síncrono) leva as saídas registradas ao nível de
-- repouso (cores pretas, sincronismos em '1').
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.video_consts.all;

entity video_scanout is
    generic (
        -- Largura do framebuffer em pixels.
        fb_width   : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height  : positive := 200;
        -- Bits por pixel do framebuffer (16 = RGB444, 8 = índice de paleta).
        pixel_bits : positive := 16
    );
    port (
        -- Clock de pixel.
        i_clk : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1'.
        i_rst : in    std_logic;

        -- Exibição habilitada, já sincronizada em i_clk ('0' = cores pretas).
        i_enable : in    std_logic;
        -- Sincronismo horizontal vindo do gerador de temporização (nível baixo ativo).
        i_hs     : in    std_logic;
        -- Sincronismo vertical vindo do gerador de temporização (nível baixo ativo).
        i_vs     : in    std_logic;
        -- O pixel atual está dentro do retângulo da imagem ('1').
        i_image  : in    std_logic;
        -- Coluna do framebuffer que cobre o pixel atual.
        i_fb_x   : in    std_logic_vector(log2_ceil(fb_width + 1) - 1 downto 0);
        -- Linha do framebuffer que cobre o pixel atual.
        i_fb_y   : in    std_logic_vector(log2_ceil(fb_height + 1) - 1 downto 0);

        -- Endereço de palavra a ler na memória do framebuffer.
        o_fb_addr : out   std_logic_vector(log2_ceil(fb_words(fb_width, fb_height, pixel_bits)) - 1 downto 0);
        -- Palavra lida da memória do framebuffer (registrada, um ciclo depois de o_fb_addr).
        i_fb_data : in    std_logic_vector(31 downto 0);
        -- Índice a ler na paleta (só tem efeito com pixel_bits = 8).
        o_pal_addr : out   std_logic_vector(PALETTE_ADDR_BITS - 1 downto 0);
        -- Cor RGB444 lida da paleta (registrada, um ciclo depois de o_pal_addr).
        i_pal_data : in    std_logic_vector(COLOR_BITS - 1 downto 0);

        -- Canal vermelho do conversor da placa.
        o_vga_r  : out   std_logic_vector(CHANNEL_BITS - 1 downto 0);
        -- Canal verde do conversor da placa.
        o_vga_g  : out   std_logic_vector(CHANNEL_BITS - 1 downto 0);
        -- Canal azul do conversor da placa.
        o_vga_b  : out   std_logic_vector(CHANNEL_BITS - 1 downto 0);
        -- Sincronismo horizontal da placa, ativo em nível baixo.
        o_vga_hs : out   std_logic;
        -- Sincronismo vertical da placa, ativo em nível baixo.
        o_vga_vs : out   std_logic
    );
end entity video_scanout;

architecture rtl of video_scanout is

    -- Pixels por palavra de 32 bits.
    constant PPW         : positive := pixels_per_word(pixel_bits);
    -- Palavras por linha do framebuffer.
    constant ROW_STRIDE   : positive := row_words(fb_width, pixel_bits);
    -- Largura do endereço de palavra do framebuffer.
    constant ADDR_BITS   : positive := log2_ceil(fb_words(fb_width, fb_height, pixel_bits));
    -- Bits do vetor de controle que acompanha o pixel: sincronismo horizontal, vertical e marca de imagem.
    constant CTRL_BITS   : positive := 3;
    -- Posição do sincronismo horizontal no vetor de controle.
    constant CTRL_HS     : natural  := 0;
    -- Posição do sincronismo vertical no vetor de controle.
    constant CTRL_VS     : natural  := 1;
    -- Posição da marca de imagem no vetor de controle.
    constant CTRL_IMAGE  : natural  := 2;

    -- Posição do pixel dentro da palavra lida, registrada junto com a leitura da memória.
    signal sel_q   : natural range 0 to PPW - 1 := 0;
    -- Vetor de controle atrasado de um estágio (acompanha a palavra lida).
    signal ctrl_s1 : std_logic_vector(CTRL_BITS - 1 downto 0) := (others => '0');
    -- Vetor de controle atrasado de dois estágios (acompanha a cor decodificada).
    signal ctrl_s2 : std_logic_vector(CTRL_BITS - 1 downto 0) := (others => '0');
    -- Pixel escolhido na palavra lida, de pixel_bits bits.
    signal pixel   : std_logic_vector(pixel_bits - 1 downto 0);
    -- Cor RGB444 decodificada, alinhada com ctrl_s2.
    signal color   : std_logic_vector(COLOR_BITS - 1 downto 0);
    -- A imagem é exibida neste pixel (dentro do retângulo e com a exibição habilitada).
    signal lit     : std_logic;
    -- Máscara dos canais de cor: todos os bits iguais a lit.
    signal lit_vec : std_logic_vector(CHANNEL_BITS - 1 downto 0);

begin

    assert 32 mod pixel_bits = 0 and (pixel_bits = 8 or pixel_bits = 16)
        report "video_scanout: pixel_bits deve ser 8 ou 16"
        severity failure;
    assert (fb_width * pixel_bits) mod 32 = 0
        report "video_scanout: uma linha do framebuffer deve ocupar um número inteiro de palavras"
        severity failure;

    -- Endereço de palavra do pixel: linha vezes palavras por linha mais a palavra dentro da linha.
    o_fb_addr <= std_logic_vector(to_unsigned(
        to_integer(unsigned(i_fb_y)) * ROW_STRIDE + to_integer(unsigned(i_fb_x)) / PPW, ADDR_BITS));

    p_stage1 : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            sel_q                <= to_integer(unsigned(i_fb_x)) mod PPW;
            ctrl_s1(CTRL_HS)     <= i_hs;
            ctrl_s1(CTRL_VS)     <= i_vs;
            ctrl_s1(CTRL_IMAGE)  <= i_image;
            ctrl_s2              <= ctrl_s1;
        end if;

    end process p_stage1;

    -- Pixel da palavra lida: percorre as posições possíveis e fica com a que sel_q aponta.
    p_pick : process (i_fb_data, sel_q) is
    begin

        pixel <= (others => '0');

        for i in 0 to PPW - 1 loop

            if sel_q = i then
                pixel <= i_fb_data(i * pixel_bits + pixel_bits - 1 downto i * pixel_bits);
            end if;

        end loop;

    end process p_pick;

    gen_direct : if pixel_bits = 16 generate
        -- Os 12 bits baixos do pixel são o RGB444, registrados para alinhar com ctrl_s2.
        p_color : process (i_clk) is
        begin

            if rising_edge(i_clk) then
                color <= pixel(COLOR_BITS - 1 downto 0);
            end if;

        end process p_color;

        o_pal_addr <= (others => '0');
    end generate gen_direct;

    gen_palette : if pixel_bits = 8 generate
        -- O pixel indexa a paleta; a saída registrada da memória da paleta já é a cor alinhada com ctrl_s2.
        o_pal_addr <= pixel(PALETTE_ADDR_BITS - 1 downto 0);
        color      <= i_pal_data;
    end generate gen_palette;

    lit     <= ctrl_s2(CTRL_IMAGE) and i_enable;
    lit_vec <= (others => lit);

    p_output : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                o_vga_r  <= (others => '0');
                o_vga_g  <= (others => '0');
                o_vga_b  <= (others => '0');
                o_vga_hs <= '1';
                o_vga_vs <= '1';
            else
                o_vga_r  <= color(3 * CHANNEL_BITS - 1 downto 2 * CHANNEL_BITS) and lit_vec;
                o_vga_g  <= color(2 * CHANNEL_BITS - 1 downto CHANNEL_BITS) and lit_vec;
                o_vga_b  <= color(CHANNEL_BITS - 1 downto 0) and lit_vec;
                o_vga_hs <= ctrl_s2(CTRL_HS);
                o_vga_vs <= ctrl_s2(CTRL_VS);
            end if;
        end if;

    end process p_output;

end architecture rtl;

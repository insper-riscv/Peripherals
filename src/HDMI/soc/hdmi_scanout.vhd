-- =============================================================================
-- Caminho de pixel do HDMI: endereço, escolha do pixel e cor de 24 bits
--
-- Domínio do clock de pixel. Converte as coordenadas do framebuffer em
-- endereço de palavra da memória (o_fb_addr), escolhe o pixel dentro da
-- palavra lida e o converte em uma cor de 24 bits (vermelho nos bits 23:16,
-- verde nos 15:8 e azul nos 7:0), conforme o formato:
--   - "indexed": o byte do pixel é o índice de uma paleta de 256 entradas de
--     24 bits, lida pela porta o_pal_addr e i_pal_data;
--   - "direct": o pixel tem 16 bits em RGB565 (vermelho nos bits 15:11, verde
--     nos 10:5 e azul nos 4:0), expandido para 24 bits repetindo os bits mais
--     altos de cada canal nos bits que faltam (o branco vira 0xFFFFFF).
-- Os pixels de uma palavra seguem a ordem do barramento: o pixel de menor
-- índice ocupa os bits menos significativos.
--
-- Latência: a memória lê em um ciclo e a escolha do pixel leva outro, de modo
-- que a cor e os sinais de controle (sincronismos, área visível, marca de
-- imagem acesa) saem alinhados, dois ciclos depois das coordenadas, e o
-- registrador de saída do bloco seguinte os registra em um terceiro. O reset
-- leva o vetor de controle ao repouso, de modo que a primeira linha depois dele tenha o
-- mesmo atraso das demais.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils_pkg.all;
use work.video_consts.all;
use work.hdmi_consts.all;

entity hdmi_scanout is
    generic (
        -- Largura do framebuffer em pixels.
        fb_width     : positive := 320;
        -- Altura do framebuffer em pixels.
        fb_height    : positive := 180;
        -- Formato do pixel do framebuffer: "indexed" (índice de paleta) ou "direct" (RGB565).
        pixel_format : string   := "indexed";
        -- Polaridade do sincronismo horizontal: verdadeiro = nível alto durante o pulso.
        h_sync_positive : boolean := false;
        -- Polaridade do sincronismo vertical: verdadeiro = nível alto durante o pulso.
        v_sync_positive : boolean := false
    );
    port (
        -- Clock de pixel.
        i_clk      : in    std_logic;
        -- Reset síncrono em i_clk, ativo em '1' (leva o vetor de controle ao repouso, para a primeira linha ter o mesmo atraso).
        i_rst      : in    std_logic;

        -- Exibição habilitada, já sincronizada em i_clk ('0' = cores pretas).
        i_enable   : in    std_logic;
        -- Sincronismo horizontal vindo do gerador de temporização.
        i_hs       : in    std_logic;
        -- Sincronismo vertical vindo do gerador de temporização.
        i_vs       : in    std_logic;
        -- O pixel atual está dentro da área visível do modo ('1').
        i_visible  : in    std_logic;
        -- O pixel atual está dentro do retângulo da imagem ('1').
        i_image    : in    std_logic;
        -- Coluna do framebuffer que cobre o pixel atual.
        i_fb_x     : in    std_logic_vector(log2_ceil(fb_width + 1) - 1 downto 0);
        -- Linha do framebuffer que cobre o pixel atual.
        i_fb_y     : in    std_logic_vector(log2_ceil(fb_height + 1) - 1 downto 0);

        -- Endereço de palavra a ler na memória do framebuffer.
        o_fb_addr  : out   std_logic_vector(
            log2_ceil(fb_words(fb_width, fb_height, pixel_storage_bits(pixel_format, size_channel_bits(pixel_format)))) - 1
            downto 0);
        -- Palavra lida da memória do framebuffer (registrada, um ciclo depois de o_fb_addr).
        i_fb_data  : in    std_logic_vector(31 downto 0);
        -- Índice a ler na paleta (só tem efeito no formato indexado).
        o_pal_addr : out   std_logic_vector(PALETTE_ADDR_BITS - 1 downto 0);
        -- Cor lida da paleta (registrada, um ciclo depois de o_pal_addr).
        i_pal_data : in    std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);

        -- Cor de 24 bits do pixel, sem o apagamento fora da imagem.
        o_color    : out   std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);
        -- A cor deve ser exibida neste pixel (dentro da imagem e com a exibição habilitada).
        o_lit      : out   std_logic;
        -- Área visível alinhada com a cor.
        o_visible  : out   std_logic;
        -- Sincronismo horizontal alinhado com a cor.
        o_hs       : out   std_logic;
        -- Sincronismo vertical alinhado com a cor.
        o_vs       : out   std_logic
    );
end entity hdmi_scanout;

architecture rtl of hdmi_scanout is

    -- Bits que cada pixel ocupa no framebuffer.
    constant PIXEL_BITS   : positive := pixel_storage_bits(pixel_format, size_channel_bits(pixel_format));
    -- Pixels por palavra de 32 bits.
    constant PPW          : positive := pixels_per_word(PIXEL_BITS);
    -- Palavras por linha do framebuffer.
    constant ROW_STRIDE   : positive := row_words(fb_width, PIXEL_BITS);
    -- Largura do endereço de palavra do framebuffer.
    constant ADDR_BITS    : positive := log2_ceil(fb_words(fb_width, fb_height, PIXEL_BITS));
    -- Bits do vetor de controle que acompanha o pixel: sincronismos, área visível e marca de imagem.
    constant CTRL_BITS    : positive := 4;
    -- Posição do sincronismo horizontal no vetor de controle.
    constant CTRL_HS      : natural  := 0;
    -- Posição do sincronismo vertical no vetor de controle.
    constant CTRL_VS      : natural  := 1;
    -- Posição da marca de imagem no vetor de controle.
    constant CTRL_IMAGE   : natural  := 2;
    -- Posição da marca de área visível no vetor de controle.
    constant CTRL_VISIBLE : natural  := 3;

    -- Vetor de controle de repouso: sincronismos fora do pulso, sem imagem e fora da área visível.
    constant CTRL_IDLE : std_logic_vector(CTRL_BITS - 1 downto 0) :=
        "00" & to_sl(not v_sync_positive) & to_sl(not h_sync_positive);

    -- Posição do pixel dentro da palavra lida, registrada junto com a leitura da memória.
    signal sel_q   : natural range 0 to PPW - 1 := 0;
    -- Vetor de controle atrasado de um estágio (acompanha a palavra lida).
    signal ctrl_s1 : std_logic_vector(CTRL_BITS - 1 downto 0) := (others => '0');
    -- Vetor de controle atrasado de dois estágios (acompanha a cor decodificada).
    signal ctrl_s2 : std_logic_vector(CTRL_BITS - 1 downto 0) := (others => '0');
    -- Pixel escolhido na palavra lida, de PIXEL_BITS bits.
    signal pixel   : std_logic_vector(PIXEL_BITS - 1 downto 0);
    -- Cor de 24 bits, alinhada com ctrl_s2.
    signal color   : std_logic_vector(3 * OUT_CHANNEL_BITS - 1 downto 0);

    -- Expande um pixel RGB565 para 24 bits repetindo os bits altos de cada canal nos bits baixos que faltam.
    function expand_565 (p : std_logic_vector(15 downto 0)) return std_logic_vector is

    begin

        return p(15 downto 11) & p(15 downto 13) & p(10 downto 5) & p(10 downto 9) & p(4 downto 0) & p(4 downto 2);

    end function expand_565;

begin

    assert is_valid_format(pixel_format)
        report "hdmi_scanout: pixel_format deve ser indexed ou direct"
        severity failure;
    assert (fb_width * PIXEL_BITS) mod 32 = 0
        report "hdmi_scanout: uma linha do framebuffer deve ocupar um número inteiro de palavras"
        severity failure;

    -- Endereço de palavra do pixel: linha vezes palavras por linha mais a palavra dentro da linha.
    o_fb_addr <= std_logic_vector(to_unsigned(
        to_integer(unsigned(i_fb_y)) * ROW_STRIDE + to_integer(unsigned(i_fb_x)) / PPW, ADDR_BITS));

    p_stage1 : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            sel_q                 <= to_integer(unsigned(i_fb_x)) mod PPW;
            ctrl_s1(CTRL_HS)      <= i_hs;
            ctrl_s1(CTRL_VS)      <= i_vs;
            ctrl_s1(CTRL_IMAGE)   <= i_image;
            ctrl_s1(CTRL_VISIBLE) <= i_visible;
            ctrl_s2               <= ctrl_s1;

            if i_rst = '1' then
                ctrl_s1 <= CTRL_IDLE;
                ctrl_s2 <= CTRL_IDLE;
            end if;
        end if;

    end process p_stage1;

    -- Pixel da palavra lida: percorre as posições possíveis e fica com a que sel_q aponta.
    p_pick : process (i_fb_data, sel_q) is
    begin

        pixel <= (others => '0');

        for i in 0 to PPW - 1 loop

            if sel_q = i then
                pixel <= i_fb_data(i * PIXEL_BITS + PIXEL_BITS - 1 downto i * PIXEL_BITS);
            end if;

        end loop;

    end process p_pick;

    gen_direct : if not is_indexed(pixel_format) generate
        -- O pixel RGB565 é expandido e registrado para alinhar com ctrl_s2.
        p_color : process (i_clk) is
        begin

            if rising_edge(i_clk) then
                color <= expand_565(pixel);
            end if;

        end process p_color;

        o_pal_addr <= (others => '0');
    end generate gen_direct;

    gen_indexed : if is_indexed(pixel_format) generate
        -- O pixel indexa a paleta; a saída registrada da memória da paleta já é a cor alinhada com ctrl_s2.
        o_pal_addr <= pixel(PALETTE_ADDR_BITS - 1 downto 0);
        color      <= i_pal_data;
    end generate gen_indexed;

    o_color   <= color;
    o_lit     <= ctrl_s2(CTRL_IMAGE) and i_enable;
    o_visible <= ctrl_s2(CTRL_VISIBLE);
    o_hs      <= ctrl_s2(CTRL_HS);
    o_vs      <= ctrl_s2(CTRL_VS);

end architecture rtl;

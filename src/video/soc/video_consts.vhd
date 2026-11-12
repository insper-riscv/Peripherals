-- =============================================================================
-- Constantes do periférico de vídeo VGA
--
-- Temporização padrão do modo VGA 640x480 a 60 Hz (800x525 pixels totais, pixel
-- de 25 MHz, sincronismos horizontal e vertical em nível baixo), largura de
-- cada canal de cor do conversor resistivo da placa, endereços de palavra dos
-- registradores e funções que dimensionam o framebuffer em tempo de elaboração.
-- =============================================================================

package video_consts is

    -- Pixels visíveis por linha.
    constant H_VISIBLE : natural := 640;
    -- Pixels do pórtico frontal horizontal, entre o fim da área visível e o pulso de sincronismo.
    constant H_FRONT   : natural := 16;
    -- Pixels do pulso de sincronismo horizontal (nível baixo).
    constant H_SYNC    : natural := 96;
    -- Pixels do pórtico traseiro horizontal, entre o pulso de sincronismo e a área visível.
    constant H_BACK    : natural := 48;
    -- Pixels totais por linha.
    constant H_TOTAL   : natural := H_VISIBLE + H_FRONT + H_SYNC + H_BACK;

    -- Linhas visíveis por quadro.
    constant V_VISIBLE : natural := 480;
    -- Linhas do pórtico frontal vertical, entre o fim da área visível e o pulso de sincronismo.
    constant V_FRONT   : natural := 10;
    -- Linhas do pulso de sincronismo vertical (nível baixo).
    constant V_SYNC    : natural := 2;
    -- Linhas do pórtico traseiro vertical, entre o pulso de sincronismo e a área visível.
    constant V_BACK    : natural := 33;
    -- Linhas totais por quadro.
    constant V_TOTAL   : natural := V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

    -- Bits de cada canal de cor (vermelho, verde e azul) do conversor da placa.
    constant CHANNEL_BITS : natural := 4;
    -- Bits de um pixel RGB444 após a decodificação (três canais de CHANNEL_BITS).
    constant COLOR_BITS   : natural := 3 * CHANNEL_BITS;

    -- Menor largura em bits do endereço de palavra (janela de 8 KiB: registradores, paleta e framebuffer).
    constant VIDEO_MIN_ADDR_WIDTH : natural := 11;
    -- Endereço de palavra do registrador de controle (bit 0 liga a exibição do framebuffer).
    constant ADDR_CTRL            : natural := 0;
    -- Endereço de palavra do registrador de estado (bit 0 sincronismo vertical, bit 1 apagamento vertical).
    constant ADDR_STATUS          : natural := 1;
    -- Endereço de palavra do contador de quadros (quadros completos desde o reset).
    constant ADDR_FRAME_COUNT     : natural := 2;
    -- Endereço de palavra da geometria do framebuffer (largura nos bits 15:0, altura nos bits 31:16).
    constant ADDR_GEOMETRY        : natural := 3;
    -- Endereço de palavra do formato (bits por pixel nos bits 7:0, fator de ampliação nos bits 15:8).
    constant ADDR_FORMAT          : natural := 4;
    -- Endereço de palavra da primeira entrada da paleta, relativo ao início do espaço de registradores.
    constant ADDR_PALETTE         : natural := 256;
    -- Número de entradas da paleta de 8 bits por pixel.
    constant PALETTE_ENTRIES      : natural := 256;
    -- Bits de endereço da paleta.
    constant PALETTE_ADDR_BITS    : natural := 8;
    -- Bits de endereço do espaço de registradores e da paleta (512 palavras), abaixo da janela do framebuffer.
    constant REG_SPACE_BITS         : natural := 9;

    -- Pixels de um framebuffer guardados em cada palavra de 32 bits.

    function pixels_per_word (pixel_bits : positive) return positive;

    -- Palavras de 32 bits que ocupa uma linha do framebuffer.

    function row_words (fb_width : positive; pixel_bits : positive) return positive;

    -- Palavras de 32 bits que ocupa o framebuffer inteiro.

    function fb_words (fb_width : positive; fb_height : positive; pixel_bits : positive) return positive;

end package video_consts;

package body video_consts is

    function pixels_per_word (pixel_bits : positive) return positive is

    begin

        return 32 / pixel_bits;

    end function pixels_per_word;

    function row_words (fb_width : positive; pixel_bits : positive) return positive is

    begin

        return (fb_width * pixel_bits + 31) / 32;

    end function row_words;

    function fb_words (fb_width : positive; fb_height : positive; pixel_bits : positive) return positive is

    begin

        return row_words(fb_width, pixel_bits) * fb_height;

    end function fb_words;

end package body video_consts;

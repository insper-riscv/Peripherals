-- =============================================================================
-- Constantes do periférico de vídeo
--
-- Endereços de palavra dos registradores, dimensões da paleta e funções que
-- dimensionam o framebuffer e escolhem o formato de pixel em tempo de
-- elaboração. A temporização do modo de vídeo e a largura do canal de cor não
-- moram aqui: chegam ao periférico por generics, para que cada placa e cada
-- plataforma escolham os seus.
-- =============================================================================

package video_consts is

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
    -- Endereço de palavra do formato (bits por pixel 7:0, ampliação 15:8, bits por canal 23:16, bit 24 indexado).
    constant ADDR_FORMAT          : natural := 4;
    -- Endereço de palavra da primeira entrada da paleta, relativo ao início do espaço de registradores.
    constant ADDR_PALETTE         : natural := 256;
    -- Número de entradas da paleta do formato indexado.
    constant PALETTE_ENTRIES      : natural := 256;
    -- Bits de endereço da paleta.
    constant PALETTE_ADDR_BITS    : natural := 8;
    -- Bits por pixel do formato indexado (o índice de uma entrada da paleta).
    constant INDEXED_PIXEL_BITS   : natural := 8;
    -- Bits de endereço do espaço de registradores e da paleta (512 palavras), abaixo da janela do framebuffer.
    constant REG_SPACE_BITS       : natural := 9;
    -- Maior largura de canal aceita (três canais devem caber em uma palavra de 32 bits).
    constant MAX_CHANNEL_BITS     : natural := 10;

    -- Indica se o nome do formato de pixel é o indexado; o outro valor aceito é "direct".

    function is_indexed (pixel_format : string) return boolean;

    -- Indica se o nome do formato de pixel é um dos dois aceitos ("indexed" ou "direct").

    function is_valid_format (pixel_format : string) return boolean;

    -- Bits que cada pixel ocupa no framebuffer: 8 no indexado; no direto, 16 ou 32, o menor que guarda três canais.

    function pixel_storage_bits (pixel_format : string; channel_bits : positive) return positive;

    -- Pixels de um framebuffer guardados em cada palavra de 32 bits.

    function pixels_per_word (pixel_bits : positive) return positive;

    -- Palavras de 32 bits que ocupa uma linha do framebuffer.

    function row_words (fb_width : positive; pixel_bits : positive) return positive;

    -- Palavras de 32 bits que ocupa o framebuffer inteiro.

    function fb_words (fb_width : positive; fb_height : positive; pixel_bits : positive) return positive;

end package video_consts;

package body video_consts is

    function is_indexed (pixel_format : string) return boolean is

    begin

        return pixel_format = "indexed";

    end function is_indexed;

    function is_valid_format (pixel_format : string) return boolean is

    begin

        return pixel_format = "indexed" or pixel_format = "direct";

    end function is_valid_format;

    function pixel_storage_bits (pixel_format : string; channel_bits : positive) return positive is

    begin

        if is_indexed(pixel_format) then
            return INDEXED_PIXEL_BITS;
        elsif 3 * channel_bits <= 16 then
            return 16;
        else
            return 32;
        end if;

    end function pixel_storage_bits;

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

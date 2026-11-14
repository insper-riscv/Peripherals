-- =============================================================================
-- Constantes do periférico de captura do decodificador de TV
--
-- Códigos do fluxo ITU-R BT.656 (prefixo de referência de temporização e bits
-- da palavra XY), endereços de palavra e campos dos registradores, valores
-- dos seletores de formato e de campo, coeficientes inteiros da conversão
-- YCbCr para RGB e funções que dimensionam a memória do quadro em tempo de
-- elaboração.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package tv_consts is

    -- Primeiro byte do prefixo de referência de temporização.
    constant BT656_PREFIX_0 : std_logic_vector(7 downto 0) := x"FF";
    -- Segundo e terceiro bytes do prefixo de referência de temporização.
    constant BT656_PREFIX_1 : std_logic_vector(7 downto 0) := x"00";
    -- Índice do bit fixo em '1' da palavra XY.
    constant XY_FIXED_BIT   : natural                      := 7;
    -- Índice do bit de campo da palavra XY ('0' campo 1, '1' campo 2).
    constant XY_FIELD_BIT   : natural                      := 6;
    -- Índice do bit de apagamento vertical da palavra XY ('1' fora do vídeo ativo).
    constant XY_VBLANK_BIT  : natural                      := 5;
    -- Índice do bit EAV/SAV da palavra XY ('1' fim do vídeo ativo, '0' início).
    constant XY_EAV_BIT     : natural                      := 4;

    -- Largura em bits de i_address.
    constant TV_ADDR_WIDTH     : natural := 4;
    -- Endereço de palavra do controle (bit 0 inicia, bit 1 e 2 máscaras de interrupção, bit 3 libera o decodificador).
    constant ADDR_CTRL         : natural := 0;
    -- Endereço de palavra do estado (bit 0 ocupado, bit 1 quadro pronto, bit 2 erro de sincronismo, bit 3 vídeo presente).
    constant ADDR_STATUS       : natural := 1;
    -- Endereço de palavra do contador de quadros capturados.
    constant ADDR_FRAME_COUNT  : natural := 2;
    -- Endereço de palavra da decimação (fator em x nos bits 7:0, fator em y nos bits 15:8).
    constant ADDR_DECIMATION   : natural := 3;
    -- Endereço de palavra do formato (bit 0 formato do pixel, bits 2:1 campo capturado).
    constant ADDR_FORMAT       : natural := 4;
    -- Endereço de palavra da geometria da memória do quadro (largura nos bits 15:0, altura nos 31:16).
    constant ADDR_GEOMETRY     : natural := 5;
    -- Endereço de palavra do ponteiro de leitura da memória do quadro.
    constant ADDR_RD_ADDR      : natural := 6;
    -- Endereço de palavra do dado da memória do quadro, lido com incremento automático do ponteiro.
    constant ADDR_RD_DATA      : natural := 7;
    -- Endereço de palavra da área de origem (largura nos bits 15:0, altura nos 31:16).
    constant ADDR_SOURCE       : natural := 8;

    -- Bit de CTRL que inicia a captura de um quadro (só escrita).
    constant CTRL_START_BIT    : natural := 0;
    -- Bit de CTRL que habilita a interrupção de quadro pronto.
    constant CTRL_FRAME_IRQ    : natural := 1;
    -- Bit de CTRL que habilita a interrupção de erro de sincronismo.
    constant CTRL_ERROR_IRQ    : natural := 2;
    -- Bit de CTRL que solta o reset do decodificador (TD_RESET_N em nível alto).
    constant CTRL_DECODER_RUN  : natural := 3;
    -- Bit de STATUS que indica captura em andamento.
    constant STATUS_BUSY_BIT   : natural := 0;
    -- Bit de STATUS que indica quadro pronto (escreva 1 para limpar).
    constant STATUS_READY_BIT  : natural := 1;
    -- Bit de STATUS que indica erro de sincronismo (escreva 1 para limpar).
    constant STATUS_ERROR_BIT  : natural := 2;
    -- Bit de STATUS que indica códigos de temporização chegando.
    constant STATUS_PRESENT_BIT : natural := 3;

    -- Valor do bit de formato para pixels RGB565 de 16 bits.
    constant FORMAT_RGB565 : std_logic := '0';
    -- Valor do bit de formato para pixels de luminância de 8 bits.
    constant FORMAT_LUMA   : std_logic := '1';
    -- Seletor de campo que captura os dois campos entrelaçados num quadro.
    constant FIELD_BOTH    : std_logic_vector(1 downto 0) := "00";
    -- Seletor de campo que captura só o primeiro campo (F = 0).
    constant FIELD_FIRST   : std_logic_vector(1 downto 0) := "01";
    -- Seletor de campo que captura só o segundo campo (F = 1).
    constant FIELD_SECOND  : std_logic_vector(1 downto 0) := "10";

    -- Coeficiente da luminância na conversão YCbCr para RGB, 1,164 em ponto fixo com 8 bits fracionários.
    constant COEF_Y     : natural := 298;
    -- Coeficiente de Cr no vermelho, 1,596 em ponto fixo.
    constant COEF_CR_R  : natural := 409;
    -- Coeficiente de Cb no verde, 0,392 em ponto fixo.
    constant COEF_CB_G  : natural := 100;
    -- Coeficiente de Cr no verde, 0,813 em ponto fixo.
    constant COEF_CR_G  : natural := 208;
    -- Coeficiente de Cb no azul, 2,018 em ponto fixo.
    constant COEF_CB_B  : natural := 516;
    -- Nível de preto da luminância ITU-R BT.601.
    constant LUMA_BLACK : natural := 16;
    -- Ponto neutro das crominâncias.
    constant CHROMA_MID : natural := 128;
    -- Bits fracionários dos coeficientes.
    constant COEF_SHIFT : natural := 8;

    -- Palavras de 32 bits da memória do quadro, com dois pixels de 16 bits por palavra.

    function frame_words (fb_width : positive; fb_height : positive) return positive;

end package tv_consts;

package body tv_consts is

    function frame_words (fb_width : positive; fb_height : positive) return positive is

    begin

        return (fb_width * fb_height + 1) / 2;

    end function frame_words;

end package body tv_consts;

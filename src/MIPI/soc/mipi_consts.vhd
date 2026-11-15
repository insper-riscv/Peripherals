-- =============================================================================
-- Constantes do periférico receptor de câmera MIPI CSI-2
--
-- Códigos do protocolo CSI-2 (byte de sincronismo do D-PHY, tipos de dado dos
-- pacotes curtos e longos), endereços de palavra e campos dos registradores,
-- funções puras do protocolo (ECC do cabeçalho e CRC-16 da carga útil) e a
-- função que dimensiona a memória do quadro em tempo de elaboração.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package mipi_consts is

    -- Byte de sincronismo que abre uma rajada em alta velocidade do D-PHY (bits 00011101 enviados do menos significativo).
    constant SYNC_BYTE      : std_logic_vector(7 downto 0) := x"B8";
    -- Quantidade de bits em zero que precisam preceder o byte de sincronismo (zero de alta velocidade do transmissor).
    constant PREAMBLE_BITS  : natural                      := 8;
    -- Quantidade de bytes do cabeçalho de um pacote.
    constant HEADER_BYTES   : natural                      := 4;
    -- Quantidade de bytes do CRC que fecha um pacote longo.
    constant CRC_BYTES      : natural                      := 2;
    -- Valor inicial do CRC-16 do CSI-2.
    constant CRC_INIT       : std_logic_vector(15 downto 0) := x"FFFF";
    -- Maior tipo de dado de um pacote curto (os tipos 0x00 a 0x0F são curtos, 0x10 em diante são longos).
    constant SHORT_MAX      : natural                      := 15;

    -- Tipo de dado do início de quadro (pacote curto).
    constant DT_FRAME_START : std_logic_vector(5 downto 0) := "000000";
    -- Tipo de dado do fim de quadro (pacote curto).
    constant DT_FRAME_END   : std_logic_vector(5 downto 0) := "000001";
    -- Tipo de dado de imagem RAW8 (pacote longo).
    constant DT_RAW8        : natural                      := 16#2A#;

    -- Largura em bits de i_address.
    constant MIPI_ADDR_WIDTH   : natural := 4;
    -- Endereço de palavra do controle (bit 0 inicia, bits 1 e 2 máscaras de interrupção, bit 3 habilita o receptor).
    constant ADDR_CTRL         : natural := 0;
    -- Endereço de palavra do estado (bit 0 ocupado, bit 1 quadro pronto, bit 2 erro, bit 3 cabeçalho válido visto).
    constant ADDR_STATUS       : natural := 1;
    -- Endereço de palavra do contador de quadros capturados.
    constant ADDR_FRAME_COUNT  : natural := 2;
    -- Endereço de palavra da configuração (tipo de dado nos bits 5:0, passo de linhas nos bits 15:8).
    constant ADDR_CONFIG       : natural := 3;
    -- Endereço de palavra da geometria da memória do quadro (bytes por linha nos bits 15:0, linhas nos bits 31:16).
    constant ADDR_GEOMETRY     : natural := 4;
    -- Endereço de palavra do ponteiro de leitura da memória do quadro.
    constant ADDR_RD_ADDR      : natural := 5;
    -- Endereço de palavra do dado da memória do quadro, lido com incremento automático do ponteiro.
    constant ADDR_RD_DATA      : natural := 6;
    -- Endereço de palavra do resultado do último quadro (linhas guardadas nos bits 15:0, contagem de palavra da última linha nos 31:16).
    constant ADDR_LAST_FRAME   : natural := 7;
    -- Endereço de palavra dos contadores de erro (ECC nos bits 7:0, CRC nos 15:8, linhas ou bytes descartados nos 23:16).
    constant ADDR_ERRORS       : natural := 8;
    -- Endereço de palavra da informação do receptor (quantidade de lanes nos bits 3:0).
    constant ADDR_INFO         : natural := 9;

    -- Bit de CTRL que inicia a captura de um quadro (só escrita).
    constant CTRL_START_BIT    : natural := 0;
    -- Bit de CTRL que habilita a interrupção de quadro pronto.
    constant CTRL_FRAME_IRQ    : natural := 1;
    -- Bit de CTRL que habilita a interrupção de erro.
    constant CTRL_ERROR_IRQ    : natural := 2;
    -- Bit de CTRL que habilita o receptor (zero mantém o domínio do clock da câmera em reset).
    constant CTRL_ENABLE       : natural := 3;
    -- Bit de STATUS que indica captura em andamento.
    constant STATUS_BUSY_BIT   : natural := 0;
    -- Bit de STATUS que indica quadro pronto (escreva 1 para limpar).
    constant STATUS_READY_BIT  : natural := 1;
    -- Bit de STATUS que indica erro de ECC, de CRC ou quadro abortado (escreva 1 para limpar).
    constant STATUS_ERROR_BIT  : natural := 2;
    -- Bit de STATUS que indica ao menos um cabeçalho com ECC correto desde que o receptor foi habilitado.
    constant STATUS_SEEN_BIT   : natural := 3;

    -- Calcula o ECC de 6 bits do cabeçalho de um pacote (identificador de dado, contagem de palavras baixa e alta).

    function csi2_ecc (header : std_logic_vector(23 downto 0)) return std_logic_vector;

    -- Avança o CRC-16 do CSI-2 (polinômio x^16 + x^12 + x^5 + 1, bits do menos significativo) de um byte.

    function csi2_crc_next (crc : std_logic_vector(15 downto 0); data : std_logic_vector(7 downto 0)) return std_logic_vector;

    -- Palavras de 32 bits da memória do quadro, com quatro bytes por palavra.

    function frame_words (line_bytes : positive; lines : positive) return positive;

end package mipi_consts;

package body mipi_consts is

    function csi2_ecc (header : std_logic_vector(23 downto 0)) return std_logic_vector is

        -- Bit de dado do cabeçalho pelo índice, para escrever cada paridade como a lista de bits que ela cobre.
        alias d : std_logic_vector(23 downto 0) is header;

        -- Bits de paridade do ECC, o bit i cobrindo os bits de dado da sua lista.
        variable ecc : std_logic_vector(5 downto 0);

    begin

        ecc(0) := d(0) xor d(1) xor d(2) xor d(4) xor d(5) xor d(7) xor d(10) xor d(11) xor d(13) xor d(16) xor
                  d(20) xor d(21) xor d(22) xor d(23);
        ecc(1) := d(0) xor d(1) xor d(3) xor d(4) xor d(6) xor d(8) xor d(10) xor d(12) xor d(14) xor d(17) xor
                  d(20) xor d(21) xor d(22) xor d(23);
        ecc(2) := d(0) xor d(2) xor d(3) xor d(5) xor d(6) xor d(9) xor d(11) xor d(12) xor d(15) xor d(18) xor
                  d(20) xor d(21) xor d(22);
        ecc(3) := d(1) xor d(2) xor d(3) xor d(7) xor d(8) xor d(9) xor d(13) xor d(14) xor d(15) xor d(19) xor
                  d(20) xor d(21) xor d(23);
        ecc(4) := d(4) xor d(5) xor d(6) xor d(7) xor d(8) xor d(9) xor d(16) xor d(17) xor d(18) xor d(19) xor
                  d(20) xor d(22) xor d(23);
        ecc(5) := d(10) xor d(11) xor d(12) xor d(13) xor d(14) xor d(15) xor d(16) xor d(17) xor d(18) xor
                  d(19) xor d(21) xor d(22) xor d(23);

        return ecc;

    end function csi2_ecc;

    function csi2_crc_next (crc : std_logic_vector(15 downto 0); data : std_logic_vector(7 downto 0)) return std_logic_vector is

        -- Polinômio refletido (0x1021 com os bits invertidos), usado porque os bits entram do menos significativo.
        constant POLY : std_logic_vector(15 downto 0) := x"8408";

        -- Estado corrente do CRC durante os oito bits do byte.
        variable state : std_logic_vector(15 downto 0);

    begin

        state := crc;

        for bit_idx in 0 to 7 loop

            if (state(0) xor data(bit_idx)) = '1' then
                state := ('0' & state(15 downto 1)) xor POLY;
            else
                state := '0' & state(15 downto 1);
            end if;

        end loop;

        return state;

    end function csi2_crc_next;

    function frame_words (line_bytes : positive; lines : positive) return positive is

    begin

        return (line_bytes * lines + 3) / 4;

    end function frame_words;

end package body mipi_consts;

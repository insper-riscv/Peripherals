-- ==========================================================================
-- Constantes do controlador de cartão SD no modo nativo
-- ==========================================================================
-- Reúne os códigos de resposta, as posições dos bits dos quadros de comando
-- e de resposta, as esperas da especificação do cartão (em ciclos de SD_CLK)
-- e os endereços de palavra dos registradores, para que nenhum literal fique
-- espalhado pela lógica. Os valores das esperas são os da especificação SD
-- Physical Layer, que não está no repositório; a origem de cada um está em
-- docs/pt-br/SD/sd_native.md.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

package sd_native_pkg is

    -- Resposta ausente (CMD0, CMD4, CMD15).
    constant RSP_NONE         : std_logic_vector(1 downto 0) := "00";
    -- Resposta curta de 48 bits com CRC7 e índice conferidos (R1, R1b, R6, R7).
    constant RSP_SHORT        : std_logic_vector(1 downto 0) := "01";
    -- Resposta curta de 48 bits sem conferência de CRC7 nem de índice (R3).
    constant RSP_SHORT_NO_CRC : std_logic_vector(1 downto 0) := "10";
    -- Resposta longa de 136 bits com CRC7 conferido (R2).
    constant RSP_LONG         : std_logic_vector(1 downto 0) := "11";

    -- Bits do comando antes do CRC7 (início, transmissão, índice e argumento).
    constant CMD_HEADER_BITS : natural := 40;
    -- Posição do último bit do quadro de comando (o bit de fim).
    constant CMD_LAST_POS    : natural := 47;
    -- Posição do último bit de uma resposta curta (o bit de fim).
    constant SHORT_LAST_POS  : natural := 47;
    -- Posição do último bit do cabeçalho de uma resposta curta (CRC7 cobre os bits 0 a 39).
    constant SHORT_HEAD_LAST : natural := 39;
    -- Posição do último bit do CRC7 de uma resposta curta.
    constant SHORT_CRC_LAST  : natural := 46;
    -- Posição do primeiro bit do corpo de uma resposta curta (depois do início e da transmissão).
    constant SHORT_FIRST_POS : natural := 2;
    -- Posição do último bit de uma resposta longa (o bit de fim).
    constant LONG_LAST_POS   : natural := 135;
    -- Posição do primeiro bit do CID ou CSD de uma resposta longa (depois dos seis bits reservados).
    constant LONG_FIRST_POS  : natural := 8;
    -- Posição do último bit do CID ou CSD de uma resposta longa.
    constant LONG_HEAD_LAST  : natural := 127;
    -- Posição do último bit do CRC7 de uma resposta longa.
    constant LONG_CRC_LAST   : natural := 134;

    -- Largura do contador de espera por ocupado e por dado, em bits.
    constant TIMEOUT_WIDTH  : positive := 24;
    -- Máximo de clocks entre o comando e o bit de início da resposta (NCR).
    constant NCR_CLOCKS     : natural := 64;
    -- Clocks que seguem o fim de um comando, antes do próximo (NCC é no mínimo 8).
    constant GAP_CLOCKS     : natural := 8;
    -- Clocks entre o fim da resposta e o bit de início de um bloco escrito (NWR é no mínimo 2).
    constant NWR_CLOCKS     : natural := 4;
    -- Máximo de clocks entre o fim do bloco escrito e o bit de início do estado de CRC.
    constant TOKEN_WAIT_CLOCKS : natural := 16;
    -- Clocks que o mestre espera depois do estado de CRC antes de olhar o ocupado em DAT0.
    constant BUSY_GUARD_CLOCKS : natural := 2;
    -- Palavras de 32 bits de um bloco de dados.
    constant BLOCK_WORDS    : natural := 128;
    -- Clocks de dados por linha de um bloco com quatro linhas (um nibble por clock).
    constant WIDE_UNITS     : natural := 1024;
    -- Clocks de dados de um bloco com uma linha (um bit por clock).
    constant NARROW_UNITS   : natural := 4096;
    -- Bits de CRC16 de cada linha de dados.
    constant DATA_CRC_BITS  : natural := 16;

    -- Estado de CRC aceito (010).
    constant TOKEN_ACCEPTED  : std_logic_vector(2 downto 0) := "010";
    -- Estado de CRC de erro de CRC nos dados (101).
    constant TOKEN_CRC_ERROR : std_logic_vector(2 downto 0) := "101";

    -- Palavra de endereço do registrador de argumento.
    constant ARG_ADDRESS     : std_logic_vector(3 downto 0) := "0000";
    -- Palavra de endereço do registrador de comando.
    constant CMD_ADDRESS     : std_logic_vector(3 downto 0) := "0001";
    -- Palavra de endereço da primeira palavra da resposta.
    constant RESP0_ADDRESS   : std_logic_vector(3 downto 0) := "0010";
    -- Palavra de endereço da segunda palavra da resposta.
    constant RESP1_ADDRESS   : std_logic_vector(3 downto 0) := "0011";
    -- Palavra de endereço da terceira palavra da resposta.
    constant RESP2_ADDRESS   : std_logic_vector(3 downto 0) := "0100";
    -- Palavra de endereço da quarta palavra da resposta.
    constant RESP3_ADDRESS   : std_logic_vector(3 downto 0) := "0101";
    -- Palavra de endereço do registrador de estado.
    constant STATUS_ADDRESS  : std_logic_vector(3 downto 0) := "0110";
    -- Palavra de endereço do registrador de erros.
    constant ERROR_ADDRESS   : std_logic_vector(3 downto 0) := "0111";
    -- Palavra de endereço do registrador de controle.
    constant CONTROL_ADDRESS : std_logic_vector(3 downto 0) := "1000";
    -- Palavra de endereço do registrador do divisor.
    constant DIVIDER_ADDRESS : std_logic_vector(3 downto 0) := "1001";
    -- Palavra de endereço do registrador de tempo limite.
    constant TIMEOUT_ADDRESS : std_logic_vector(3 downto 0) := "1010";
    -- Palavra de endereço da janela do buffer de bloco.
    constant DATA_ADDRESS    : std_logic_vector(3 downto 0) := "1011";
    -- Palavra de endereço do ponteiro da janela do buffer.
    constant PTR_ADDRESS     : std_logic_vector(3 downto 0) := "1100";

end package sd_native_pkg;

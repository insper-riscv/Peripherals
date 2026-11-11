-- =============================================================================
-- Constantes do mouse PS/2
--
-- Bytes de comando e de resposta do protocolo do mouse, endereços de palavra
-- dos registradores do periférico, posições dos bits de status e larguras dos
-- acumuladores de deslocamento.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package ps2_mouse_consts is

    -- Comando de reset do mouse (provoca o autoteste).
    constant CMD_RESET            : std_logic_vector(7 downto 0) := x"FF";
    -- Comando que habilita o envio contínuo de pacotes (modo streaming).
    constant CMD_ENABLE_STREAMING : std_logic_vector(7 downto 0) := x"F4";
    -- Resposta de reconhecimento (ACK) do mouse a um comando.
    constant RSP_ACK              : std_logic_vector(7 downto 0) := x"FA";
    -- Resposta de autoteste concluído com sucesso.
    constant RSP_SELF_TEST_OK     : std_logic_vector(7 downto 0) := x"AA";
    -- Identificador do mouse padrão de três botões, enviado após o autoteste.
    constant RSP_DEVICE_ID        : std_logic_vector(7 downto 0) := x"00";

    -- Posição do bit sempre em '1' no primeiro byte de um pacote.
    constant SYNC_BIT          : natural := 3;
    -- Posição do botão esquerdo no primeiro byte.
    constant PKT_LEFT_BIT      : natural := 0;
    -- Posição do botão direito no primeiro byte.
    constant PKT_RIGHT_BIT     : natural := 1;
    -- Posição do botão do meio no primeiro byte.
    constant PKT_MIDDLE_BIT    : natural := 2;
    -- Posição do sinal de X (nono bit do deslocamento) no primeiro byte.
    constant PKT_X_SIGN_BIT    : natural := 4;
    -- Posição do sinal de Y (nono bit do deslocamento) no primeiro byte.
    constant PKT_Y_SIGN_BIT    : natural := 5;
    -- Posição do estouro de X no primeiro byte.
    constant PKT_X_OVERFLOW_BIT : natural := 6;
    -- Posição do estouro de Y no primeiro byte.
    constant PKT_Y_OVERFLOW_BIT : natural := 7;

    -- Largura do deslocamento de um pacote em bits (complemento de dois).
    constant DELTA_WIDTH : positive := 9;
    -- Largura dos acumuladores de deslocamento em bits (complemento de dois).
    constant ACC_WIDTH   : positive := 16;

    -- Endereço de palavra do registrador de status.
    constant ADDR_STATUS  : std_logic_vector(2 downto 0) := "000";
    -- Endereço de palavra do deslocamento acumulado em X.
    constant ADDR_DX      : std_logic_vector(2 downto 0) := "001";
    -- Endereço de palavra do deslocamento acumulado em Y.
    constant ADDR_DY      : std_logic_vector(2 downto 0) := "010";
    -- Endereço de palavra do estado dos botões.
    constant ADDR_BUTTONS : std_logic_vector(2 downto 0) := "011";
    -- Endereço de palavra do registrador de controle.
    constant ADDR_CONTROL : std_logic_vector(2 downto 0) := "100";

    -- Posição do bit de pacote novo no status.
    constant STATUS_NEW_BIT       : natural := 0;
    -- Posição do bit de estouro no status.
    constant STATUS_OVERFLOW_BIT  : natural := 1;
    -- Posição do bit de erro no status.
    constant STATUS_ERROR_BIT     : natural := 2;
    -- Posição do bit de mouse em streaming no status.
    constant STATUS_STREAMING_BIT : natural := 3;

    -- Posição do bit de habilitação da interrupção no controle.
    constant CTRL_IRQ_EN_BIT  : natural := 0;
    -- Posição do bit de reinicialização do mouse no controle (somente escrita).
    constant CTRL_REINIT_BIT  : natural := 1;

end package ps2_mouse_consts;

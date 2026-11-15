-- =============================================================================
-- Constantes da ponte do módulo Wi-Fi NINA
--
-- Endereços de palavra da janela do periférico, que reúne o bloco de controle
-- do módulo, o mestre SPI e a UART, e endereços e bits dos registradores do
-- bloco de controle (reset do módulo, seleção de boot, entrada ACK e
-- interrupção).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package wifi_consts is

    -- Largura em bits de i_address da janela inteira.
    constant WIFI_ADDR_WIDTH   : natural := 5;
    -- Largura em bits do endereço dentro do bloco de controle.
    constant CTRL_ADDR_WIDTH   : natural := 3;
    -- Seletor do bloco de controle, nos bits 4:3 do endereço.
    constant BLOCK_CONTROL     : std_logic_vector(1 downto 0) := "00";
    -- Seletor do mestre SPI, nos bits 4:3 do endereço.
    constant BLOCK_SPI         : std_logic_vector(1 downto 0) := "01";
    -- Seletor da UART, nos bits 4:3 do endereço.
    constant BLOCK_UART        : std_logic_vector(1 downto 0) := "10";
    -- Maior endereço de registrador do mestre SPI dentro do seu bloco.
    constant SPI_LAST_ADDRESS  : natural := 5;
    -- Maior endereço de registrador da UART dentro do seu bloco.
    constant UART_LAST_ADDRESS : natural := 3;

    -- Endereço de palavra do controle (bit 0 libera o módulo, bit 1 força GPIO0 em baixo, bits 2 e 3 máscaras do ACK).
    constant ADDR_CTRL         : natural := 0;
    -- Endereço de palavra do estado (bit 0 nível de ACK, bits 1 e 2 bordas de ACK, bit 3 pulso de reset em curso).
    constant ADDR_STATUS       : natural := 1;
    -- Endereço de palavra do pulso de reset (escrever 1 no bit 0 reinicia o módulo por um tempo fixo).
    constant ADDR_RESET_PULSE  : natural := 2;

    -- Bit de CTRL que solta o reset do módulo (zero o mantém em reset).
    constant CTRL_RUN_BIT      : natural := 0;
    -- Bit de CTRL que força o pino GPIO0 do módulo em nível baixo (modo de gravação do firmware).
    constant CTRL_BOOT_LOW_BIT : natural := 1;
    -- Bit de CTRL que habilita a interrupção da borda de subida de ACK.
    constant CTRL_RISE_IRQ_BIT : natural := 2;
    -- Bit de CTRL que habilita a interrupção da borda de descida de ACK.
    constant CTRL_FALL_IRQ_BIT : natural := 3;
    -- Bit de STATUS com o nível do pino ACK.
    constant STATUS_ACK_BIT    : natural := 0;
    -- Bit de STATUS que indica borda de subida de ACK (escreva 1 para limpar).
    constant STATUS_RISE_BIT   : natural := 1;
    -- Bit de STATUS que indica borda de descida de ACK (escreva 1 para limpar).
    constant STATUS_FALL_BIT   : natural := 2;
    -- Bit de STATUS que indica pulso de reset em curso.
    constant STATUS_PULSE_BIT  : natural := 3;
    -- Bit de RESET_PULSE que dispara o pulso.
    constant PULSE_START_BIT   : natural := 0;

end package wifi_consts;

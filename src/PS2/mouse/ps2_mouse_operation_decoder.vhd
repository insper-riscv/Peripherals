-- =============================================================================
-- Decodificador de operações do mouse PS/2 mapeado em memória
--
-- Traduz o endereço de palavra e os pulsos de leitura e escrita em: o seletor
-- do multiplexador de leitura, os pulsos de limpeza na leitura (status e
-- acumuladores) e a escrita do registrador de controle. Endereços fora do mapa
-- leem zero e ignoram a escrita.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.ps2_mouse_consts.all;

entity ps2_mouse_operation_decoder is
    port (
        -- Endereço de palavra de 3 bits vindo do processador.
        i_address      : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita ('1' = escreve).
        i_write        : in    std_logic;
        -- Pulso de leitura ('1' = lê).
        i_read         : in    std_logic;
        -- Seletor do multiplexador de leitura.
        o_rd_sel       : out   std_logic_vector(2 downto 0);
        -- Pulso de leitura do status (limpa os bits de evento).
        o_status_read  : out   std_logic;
        -- Pulso de leitura do deslocamento em X (zera o acumulador).
        o_dx_read      : out   std_logic;
        -- Pulso de leitura do deslocamento em Y (zera o acumulador).
        o_dy_read      : out   std_logic;
        -- Pulso de escrita do registrador de controle.
        o_control_write : out   std_logic
    );
end entity ps2_mouse_operation_decoder;

architecture rtl of ps2_mouse_operation_decoder is

begin

    o_status_read   <= i_read when i_address = ADDR_STATUS else '0';
    o_dx_read       <= i_read when i_address = ADDR_DX else '0';
    o_dy_read       <= i_read when i_address = ADDR_DY else '0';
    o_control_write <= i_write when i_address = ADDR_CONTROL else '0';

    -- Posições do multiplexador: 0 status, 1 dx, 2 dy, 3 botões, 4 controle e
    -- 5 a 7 zero.
    with i_address select o_rd_sel <=
        "000" when ADDR_STATUS,
        "001" when ADDR_DX,
        "010" when ADDR_DY,
        "011" when ADDR_BUTTONS,
        "100" when ADDR_CONTROL,
        "111" when others;

end architecture rtl;

-- =============================================================================
-- Constantes do mestre I2C
--
-- Endereços de palavra dos registradores, posições dos bits e limites do
-- divisor de clock. O mapa completo está em docs/pt-br/I2C/i2c_master.md.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package i2c_consts is

    -- Largura do endereço local de palavra (oito registradores).
    constant I2C_ADDR_BITS : natural := 3;

    -- Endereço do registrador de controle.
    constant ADDR_CTRL    : std_logic_vector(I2C_ADDR_BITS - 1 downto 0) := "000";
    -- Endereço do divisor de clock.
    constant ADDR_DIVIDER : std_logic_vector(I2C_ADDR_BITS - 1 downto 0) := "001";
    -- Endereço do registrador de comando (só escrita).
    constant ADDR_CMD     : std_logic_vector(I2C_ADDR_BITS - 1 downto 0) := "010";
    -- Endereço do byte a transmitir.
    constant ADDR_TX      : std_logic_vector(I2C_ADDR_BITS - 1 downto 0) := "011";
    -- Endereço do último byte recebido (só leitura).
    constant ADDR_RX      : std_logic_vector(I2C_ADDR_BITS - 1 downto 0) := "100";
    -- Endereço do registrador de estado.
    constant ADDR_STATUS  : std_logic_vector(I2C_ADDR_BITS - 1 downto 0) := "101";

    -- Bit de CTRL que liga o mestre.
    constant CTRL_ENABLE_BIT   : natural := 0;
    -- Bit de CTRL que habilita a interrupção de fim de comando.
    constant CTRL_IRQ_DONE_BIT : natural := 1;
    -- Bit de CTRL que habilita a interrupção de erro.
    constant CTRL_IRQ_ERR_BIT  : natural := 2;
    -- Bit de CTRL que aborta o comando em curso (pulso, lê como zero).
    constant CTRL_ABORT_BIT    : natural := 3;

    -- Bit de CMD que gera a condição de início (ou de repetição de início).
    constant CMD_START_BIT : natural := 0;
    -- Bit de CMD que gera a condição de parada ao fim do comando.
    constant CMD_STOP_BIT  : natural := 1;
    -- Bit de CMD que recebe um byte.
    constant CMD_READ_BIT  : natural := 2;
    -- Bit de CMD que envia o byte de TX.
    constant CMD_WRITE_BIT : natural := 3;
    -- Bit de CMD que responde NACK ao byte recebido (zero responde ACK).
    constant CMD_NACK_BIT  : natural := 4;

    -- Bit de STATUS: comando em execução.
    constant ST_BUSY_BIT       : natural := 0;
    -- Bit de STATUS: o mestre gerou um início e ainda não gerou a parada.
    constant ST_BUS_ACTIVE_BIT : natural := 1;
    -- Bit de STATUS: comando terminado (sticky, escreve 1 para limpar).
    constant ST_DONE_BIT       : natural := 2;
    -- Bit de STATUS: byte enviado recebeu NACK (sticky, escreve 1 para limpar).
    constant ST_NACK_BIT       : natural := 3;
    -- Bit de STATUS: arbitragem perdida (sticky, escreve 1 para limpar).
    constant ST_ARB_LOST_BIT   : natural := 4;
    -- Bit de STATUS: comando recusado (sticky, escreve 1 para limpar).
    constant ST_REJECTED_BIT   : natural := 5;

    -- Menor divisor aceito, que dá três ciclos por passo e deixa a amostra do pino atravessar o sincronizador.
    constant MIN_DIVIDER : natural := 2;

end package i2c_consts;

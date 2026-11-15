-- =============================================================================
-- Constantes do ADXL345 no barramento I2C
--
-- Endereços de registrador do chip, valores de configuração e endereços de 7
-- bits do escravo. Os valores vêm da folha de dados do ADXL345, que não está no
-- repositório (os manuais das placas só dão a interface), então são suposições
-- a conferir contra ela. O endereço do escravo depende do nível do pino SDO
-- (ALT ADDRESS), como dizem os manuais da DE10-Lite e da DE0-Nano.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package adxl345_consts is

    -- Endereço de 7 bits com SDO em nível alto.
    constant I2C_ADDR_SDO_HIGH : std_logic_vector(6 downto 0) := "0011101";
    -- Endereço de 7 bits com SDO em nível baixo.
    constant I2C_ADDR_SDO_LOW  : std_logic_vector(6 downto 0) := "1010011";

    -- Registrador DEVID (identificação, lê 0xE5).
    constant REG_DEVID       : std_logic_vector(7 downto 0) := x"00";
    -- Registrador BW_RATE (taxa de saída de dados).
    constant REG_BW_RATE     : std_logic_vector(7 downto 0) := x"2C";
    -- Registrador POWER_CTL (modo de medição).
    constant REG_POWER_CTL   : std_logic_vector(7 downto 0) := x"2D";
    -- Registrador INT_ENABLE (habilitação das interrupções do chip).
    constant REG_INT_ENABLE  : std_logic_vector(7 downto 0) := x"2E";
    -- Registrador INT_MAP (pino INT1 ou INT2 de cada interrupção).
    constant REG_INT_MAP     : std_logic_vector(7 downto 0) := x"2F";
    -- Registrador DATA_FORMAT (escala e resolução).
    constant REG_DATA_FORMAT : std_logic_vector(7 downto 0) := x"31";
    -- Primeiro registrador de dados (DATAX0), início da leitura em rajada.
    constant REG_DATAX0      : std_logic_vector(7 downto 0) := x"32";

    -- Valor de INT_ENABLE com só o dado pronto habilitado.
    constant INT_DATA_READY : std_logic_vector(7 downto 0) := x"80";
    -- Valor de POWER_CTL com a medição ligada.
    constant POWER_MEASURE  : std_logic_vector(7 downto 0) := x"08";

end package adxl345_consts;

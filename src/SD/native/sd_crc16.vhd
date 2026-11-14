-- ==========================================================================
-- CRC16 serial dos blocos de dados do cartão SD
-- ==========================================================================
-- Registrador de deslocamento de realimentação linear que calcula o CRC16
-- de polinômio x^16 + x^12 + x^5 + 1 (CRC-CCITT), com valor inicial zero, um
-- bit por ciclo em que i_enable vale 1, o bit mais significativo primeiro. O
-- cartão usa um CRC16 por linha de dados, e cada linha recebe os bits que
-- passam por ela. Depois de todos os bits, o_crc é o CRC16 a transmitir (do
-- bit 15 ao bit 0). Alimentar a mensagem seguida do seu próprio CRC16 deixa
-- o_crc em zero. i_clear zera o registrador e tem prioridade sobre i_enable.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity sd_crc16 is
    port (
        -- Clock do módulo.
        i_clk    : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst    : in    std_logic;
        -- Zera o registrador no próximo ciclo, com prioridade sobre i_enable.
        i_clear  : in    std_logic;
        -- Incorpora o bit i_bit no próximo ciclo.
        i_enable : in    std_logic;
        -- Bit da mensagem, o mais significativo primeiro.
        i_bit    : in    std_logic;
        -- CRC16 dos bits incorporados até agora.
        o_crc    : out   std_logic_vector(15 downto 0)
    );
end entity sd_crc16;

architecture rtl of sd_crc16 is

    -- Termos do polinômio abaixo de x^16, ou seja, x^12 + x^5 + 1 (0x1021).
    constant POLYNOMIAL : std_logic_vector(15 downto 0) := "0001000000100001";

    -- Valor atual do registrador.
    signal crc : std_logic_vector(15 downto 0);

begin

    o_crc <= crc;

    p_crc : process (i_clk) is

        -- Bit que realimenta o registrador.
        variable feedback : std_logic;

    begin

        if rising_edge(i_clk) then
            if i_rst = '1' or i_clear = '1' then
                crc <= (others => '0');
            elsif i_enable = '1' then
                feedback := crc(15) xor i_bit;

                if feedback = '1' then
                    crc <= (crc(14 downto 0) & '0') xor POLYNOMIAL;
                else
                    crc <= crc(14 downto 0) & '0';
                end if;
            end if;
        end if;

    end process p_crc;

end architecture rtl;

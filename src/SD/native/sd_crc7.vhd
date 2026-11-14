-- ==========================================================================
-- CRC7 serial dos comandos e respostas do cartão SD
-- ==========================================================================
-- Registrador de deslocamento de realimentação linear que calcula o CRC7 de
-- polinômio x^7 + x^3 + 1, com valor inicial zero, um bit por ciclo em que
-- i_enable vale 1, o bit mais significativo da mensagem primeiro. Depois de
-- toda a mensagem, o_crc é o CRC7 a transmitir (do bit 6 ao bit 0). Alimentar
-- a mensagem seguida do seu próprio CRC7 deixa o_crc em zero. i_clear zera o
-- registrador e tem prioridade sobre i_enable.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity sd_crc7 is
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
        -- CRC7 da mensagem incorporada até agora.
        o_crc    : out   std_logic_vector(6 downto 0)
    );
end entity sd_crc7;

architecture rtl of sd_crc7 is

    -- Termos do polinômio abaixo de x^7, ou seja, x^3 + 1.
    constant POLYNOMIAL : std_logic_vector(6 downto 0) := "0001001";

    -- Valor atual do registrador.
    signal crc : std_logic_vector(6 downto 0);

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
                feedback := crc(6) xor i_bit;

                if feedback = '1' then
                    crc <= (crc(5 downto 0) & '0') xor POLYNOMIAL;
                else
                    crc <= crc(5 downto 0) & '0';
                end if;
            end if;
        end if;

    end process p_crc;

end architecture rtl;

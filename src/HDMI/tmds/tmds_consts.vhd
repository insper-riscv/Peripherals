-- =============================================================================
-- Constantes e funções do codificador TMDS
--
-- Reúne os valores fixos da codificação TMDS de 8 bits para 10 bits do DVI 1.0
-- (e do vídeo do HDMI sem ilhas de dados): a largura do símbolo, os quatro
-- símbolos de controle do período de apagamento, o símbolo do canal de clock e
-- a função que conta os bits em nível alto de um vetor, base do cálculo de
-- disparidade. Um símbolo é transmitido a partir do bit menos significativo.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package tmds_consts is

    -- Largura de um símbolo TMDS, em bits.
    constant TOKEN_BITS   : positive := 10;
    -- Largura de um byte de pixel de um canal, em bits.
    constant PIXEL_BITS   : positive := 8;
    -- Número de canais de dados (azul, verde e vermelho).
    constant DATA_LANES   : positive := 3;
    -- Bits do símbolo transmitidos por ciclo do clock de 5 vezes (dois, um por borda).
    constant BITS_PER_CLK : positive := 2;

    -- Símbolo de controle para os bits de controle C1 C0 = 00.
    constant TOKEN_CTRL_00 : std_logic_vector(TOKEN_BITS - 1 downto 0) := "1101010100";
    -- Símbolo de controle para os bits de controle C1 C0 = 01.
    constant TOKEN_CTRL_01 : std_logic_vector(TOKEN_BITS - 1 downto 0) := "0010101011";
    -- Símbolo de controle para os bits de controle C1 C0 = 10.
    constant TOKEN_CTRL_10 : std_logic_vector(TOKEN_BITS - 1 downto 0) := "0101010100";
    -- Símbolo de controle para os bits de controle C1 C0 = 11.
    constant TOKEN_CTRL_11 : std_logic_vector(TOKEN_BITS - 1 downto 0) := "1010101011";
    -- Símbolo do canal de clock: cinco bits em 0 e depois cinco em 1, um período do clock de pixel.
    constant TOKEN_CLOCK   : std_logic_vector(TOKEN_BITS - 1 downto 0) := "1111100000";

    -- Número de bits em '1' de um vetor.
    function count_ones (v : std_logic_vector) return natural;

end package tmds_consts;

package body tmds_consts is

    function count_ones (v : std_logic_vector) return natural is
        -- Contagem em construção.
        variable ones : natural := 0;
    begin

        for i in v'range loop
            if v(i) = '1' then
                ones := ones + 1;
            end if;
        end loop;

        return ones;

    end function count_ones;

end package body tmds_consts;

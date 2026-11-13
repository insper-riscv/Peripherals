-- =============================================================================
-- Constantes e funções do controlador do LCD 16x2
-- =============================================================================
-- Endereços dos registradores, posição dos bits de status e de controle, largura
-- dos contadores de atraso e conversão de tempos físicos (nanossegundos e
-- microssegundos) em ciclos de clock. Os tempos dos comandos e da
-- inicialização do HD44780 vêm daqui para que as entidades do periférico não
-- carreguem números soltos.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

package lcd_consts is

    -- Endereço de palavra do registrador de comando (escrita enfileira RS = 0).
    constant COMMAND_ADDRESS    : std_logic_vector(2 downto 0) := "000";
    -- Endereço de palavra do registrador de dado (escrita enfileira RS = 1).
    constant DATA_ADDRESS       : std_logic_vector(2 downto 0) := "001";
    -- Endereço de palavra do registrador de estado.
    constant STATUS_ADDRESS     : std_logic_vector(2 downto 0) := "010";
    -- Endereço de palavra do registrador de controle.
    constant CONTROL_ADDRESS    : std_logic_vector(2 downto 0) := "011";
    -- Endereço de palavra do atraso dos comandos comuns.
    constant DELAY_ADDRESS      : std_logic_vector(2 downto 0) := "100";
    -- Endereço de palavra do atraso dos comandos lentos (limpar e início).
    constant DELAY_LONG_ADDRESS : std_logic_vector(2 downto 0) := "101";

    -- Posição do bit BUSY do registrador de estado.
    constant STATUS_BUSY       : natural := 0;
    -- Posição do bit FIFO_FULL do registrador de estado.
    constant STATUS_FIFO_FULL  : natural := 1;
    -- Posição do bit FIFO_EMPTY do registrador de estado.
    constant STATUS_FIFO_EMPTY : natural := 2;
    -- Posição do bit INIT_BUSY do registrador de estado.
    constant STATUS_INIT_BUSY  : natural := 3;
    -- Posição do bit DROPPED do registrador de estado.
    constant STATUS_DROPPED    : natural := 4;
    -- Posição do bit TIMEOUT do registrador de estado.
    constant STATUS_TIMEOUT    : natural := 5;
    -- Posição do bit menos significativo do nível da fila no registrador de estado.
    constant STATUS_LEVEL_LOW  : natural := 8;

    -- Posição do bit EMPTY_IRQ_ENABLE do registrador de controle.
    constant CONTROL_IRQ_ENABLE  : natural := 0;
    -- Posição do bit POLL_ENABLE do registrador de controle.
    constant CONTROL_POLL_ENABLE : natural := 1;
    -- Posição do bit LCD_ON do registrador de controle.
    constant CONTROL_LCD_ON      : natural := 2;
    -- Posição do bit BACKLIGHT_ON do registrador de controle.
    constant CONTROL_BACKLIGHT   : natural := 3;

    -- Largura em bits dos contadores de atraso, em ciclos de clock.
    constant DELAY_BITS : positive := 24;
    -- Largura em bits do campo de nível da fila no registrador de estado.
    constant LEVEL_BITS : positive := 8;

    -- Quantidade de passos da sequência de inicialização.
    constant INIT_STEPS : positive := 7;

    -- Converte um tempo em nanossegundos no número de ciclos de clock que o cobre, no mínimo um.
    function ns_to_cycles (
        ns   : natural;
        freq : positive
    ) return positive;

    -- Converte um tempo em microssegundos no número de ciclos de clock que o cobre, no mínimo um.
    function us_to_cycles (
        us   : natural;
        freq : positive
    ) return positive;

    -- Indica os comandos de limpar a tela e de levar o cursor ao início, que o chip executa devagar.
    function is_slow_command (
        rs   : std_logic;
        data : std_logic_vector(7 downto 0)
    ) return boolean;

    -- Byte do passo da sequência de inicialização (0 a INIT_STEPS - 1).
    function init_command (
        step : natural
    ) return std_logic_vector;

end package lcd_consts;

package body lcd_consts is

    -- Arredonda para cima o produto de um tempo pela frequência dividido por um fator de escala.
    function ceil_cycles (
        amount : natural;
        freq   : positive;
        scale  : real
    ) return positive is

        -- Valor exato em ciclos, como número real.
        constant EXACT   : real    := real(amount) * real(freq) / scale;
        -- Valor arredondado ao inteiro mais próximo.
        variable rounded : integer := integer(EXACT);

    begin

        if real(rounded) < EXACT then
            rounded := rounded + 1;
        end if;

        if rounded < 1 then
            return 1;
        end if;

        return rounded;

    end function ceil_cycles;

    function ns_to_cycles (
        ns   : natural;
        freq : positive
    ) return positive is
    begin

        return ceil_cycles(ns, freq, 1.0e9);

    end function ns_to_cycles;

    function us_to_cycles (
        us   : natural;
        freq : positive
    ) return positive is
    begin

        return ceil_cycles(us, freq, 1.0e6);

    end function us_to_cycles;

    function is_slow_command (
        rs   : std_logic;
        data : std_logic_vector(7 downto 0)
    ) return boolean is
    begin

        return rs = '0' and data(7 downto 2) = "000000";

    end function is_slow_command;

    function init_command (
        step : natural
    ) return std_logic_vector is
    begin

        case step is

            when 0 | 1 | 2 =>

                -- Function set de 8 bits, repetido três vezes para acordar o chip.
                return x"30";

            when 3 =>

                -- Function set: interface de 8 bits, duas linhas, fonte 5x8.
                return x"38";

            when 4 =>

                -- Display ligado, cursor e piscar desligados.
                return x"0C";

            when 5 =>

                -- Limpa a tela e leva o cursor ao início.
                return x"01";

            when others =>

                -- Entry mode: cursor avança para a direita, sem deslocar a tela.
                return x"06";

        end case;

    end function init_command;

end package body lcd_consts;

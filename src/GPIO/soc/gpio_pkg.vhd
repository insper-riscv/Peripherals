-- =============================================================================
-- Pacote da partição do GPIO e do display
--
-- Funções de elaboração que leem as listas codificadas nos generics do bloco gpio
-- e do seg_display. Uma lista de números é um std_logic_vector com um campo de 8
-- bits por elemento: o elemento k ocupa os bits 8k+7 a 8k. Uma lista de direções
-- usa 2 bits por pino: o pino p ocupa os bits 2p+1 a 2p. Só há vetores e
-- inteiros, sem tipo da VHDL-2008, para o Quartus Prime Lite aceitar o pacote.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gpio_pkg is

    -- Largura, em bits, do campo de cada elemento de uma lista de números.
    constant FIELD_BITS : natural := 8;
    -- Palavras de um grupo: o arquivo de registradores ocupa 64 bytes.
    constant GROUP_WORDS : natural := 16;
    -- Bits do endereço de palavra dentro de um grupo.
    constant GROUP_WORD_BITS : natural := 4;

    -- Direção fixa de um pino: livre, só entrada ou só saída.
    -- Código de um pino de direção livre (o registrador DIR manda).
    constant DIR_FREE   : natural := 0;
    -- Código de um pino fixo em entrada.
    constant DIR_INPUT  : natural := 1;
    -- Código de um pino fixo em saída.
    constant DIR_OUTPUT : natural := 2;

    -- Modo de direção de um pino, a partir dos 2 bits do código (o código 3 é recusado).
    function to_mode (code : in std_logic_vector(1 downto 0)) return natural;

    -- Elemento k de uma lista de campos de 8 bits.
    function field_value (v : in std_logic_vector; k : in natural) return natural;

    -- Soma dos elementos de índice menor que n de uma lista de campos de 8 bits.
    function field_sum (v : in std_logic_vector; n : in natural) return natural;

    -- Bits do índice de grupo no endereço de palavra de um bloco com a quantidade de grupos dada.
    function group_index_bits (groups : in positive) return natural;

    -- Largura do endereço de palavra de um bloco com a quantidade de grupos dada.
    function block_addr_width (groups : in positive) return natural;

    -- Verdadeiro quando o pino p aparece na lista de membros (campos de 8 bits, count elementos).
    function is_member (members : in std_logic_vector; count : in natural; p : in natural) return boolean;

    -- Códigos de direção dos pinos membros de um grupo, 2 bits por membro, na ordem da lista.
    function member_dirs (
        dirs : in std_logic_vector; members : in std_logic_vector; first : in natural; size : in positive
    ) return std_logic_vector;

    -- Polaridades dos pinos membros de um grupo, 1 bit por membro, na ordem da lista.
    function member_lows (
        lows : in std_logic_vector; members : in std_logic_vector; first : in natural; size : in positive
    ) return std_logic_vector;

end package gpio_pkg;

package body gpio_pkg is

    function to_mode (code : in std_logic_vector(1 downto 0)) return natural is

    begin

        assert code /= "11" report "gpio_pkg: o código de direção 3 não existe" severity failure;

        return to_integer(unsigned(code));

    end function to_mode;

    function field_value (v : in std_logic_vector; k : in natural) return natural is

        -- Cópia com a faixa normalizada em v'length - 1 downto 0.
        variable n : std_logic_vector(v'length - 1 downto 0) := v;

    begin

        return to_integer(unsigned(n(FIELD_BITS * k + FIELD_BITS - 1 downto FIELD_BITS * k)));

    end function field_value;

    function field_sum (v : in std_logic_vector; n : in natural) return natural is

        -- Acumulador da soma.
        variable total : natural := 0;

    begin

        for k in 0 to n - 1 loop

            total := total + field_value(v, k);

        end loop;

        return total;

    end function field_sum;

    function group_index_bits (groups : in positive) return natural is

        -- Expoente, o primeiro n tal que 2^n >= groups.
        variable result : natural := 0;

    begin

        while (2 ** result) < groups loop

            result := result + 1;

        end loop;

        return result;

    end function group_index_bits;

    function block_addr_width (groups : in positive) return natural is

    begin

        return GROUP_WORD_BITS + group_index_bits(groups);

    end function block_addr_width;

    function is_member (members : in std_logic_vector; count : in natural; p : in natural) return boolean is

    begin

        for k in 0 to count - 1 loop

            if field_value(members, k) = p then
                return true;
            end if;

        end loop;

        return false;

    end function is_member;

    function member_dirs (
        dirs : in std_logic_vector; members : in std_logic_vector; first : in natural; size : in positive
    ) return std_logic_vector is

        -- Cópia com a faixa normalizada.
        variable d      : std_logic_vector(dirs'length - 1 downto 0) := dirs;
        -- Resultado, 2 bits por membro.
        variable result : std_logic_vector(2 * size - 1 downto 0);
        -- Índice do pino do membro.
        variable p      : natural;

    begin

        for k in 0 to size - 1 loop

            p                          := field_value(members, first + k);
            result(2 * k + 1 downto 2 * k) := d(2 * p + 1 downto 2 * p);

        end loop;

        return result;

    end function member_dirs;

    function member_lows (
        lows : in std_logic_vector; members : in std_logic_vector; first : in natural; size : in positive
    ) return std_logic_vector is

        -- Cópia com a faixa normalizada.
        variable l      : std_logic_vector(lows'length - 1 downto 0) := lows;
        -- Resultado, 1 bit por membro.
        variable result : std_logic_vector(size - 1 downto 0);

    begin

        for k in 0 to size - 1 loop

            result(k) := l(field_value(members, first + k));

        end loop;

        return result;

    end function member_lows;

end package body gpio_pkg;

-- =============================================================================
-- Pacote de teste: partição do GPIO e do display escrita em texto
--
-- Os testes descrevem a partição em texto legível e este pacote a converte nas
-- listas codificadas que os generics do gpio e do seg_display esperam. O texto
-- "0,1,2,3/5,6" é um grupo com os pinos 0 a 3 e outro com os pinos 5 e 6. Só a
-- simulação usa este pacote; o topo da placa recebe as listas já codificadas.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gpio_partition_pkg is

    -- Quantidade de grupos do texto, um mais o número de barras.
    function count_groups (s : in string) return positive;

    -- Quantidade de índices de pino do texto.
    function count_members (s : in string) return positive;

    -- Lista de tamanhos dos grupos, um campo de 8 bits por grupo.
    function encode_sizes (s : in string) return std_logic_vector;

    -- Lista de índices de pino, um campo de 8 bits por membro, na ordem escrita.
    function encode_members (s : in string) return std_logic_vector;

    -- Códigos de direção por pino: 'f' livre, 'i' só entrada, 'o' só saída.
    function encode_dirs (s : in string) return std_logic_vector;

    -- Polaridade por pino: 'h' ativo em nível alto, 'l' ativo em nível baixo.
    function encode_lows (s : in string) return std_logic_vector;

end package gpio_partition_pkg;

package body gpio_partition_pkg is

    function count_groups (s : in string) return positive is

        -- Contagem de barras.
        variable n : natural := 1;

    begin

        for i in s'range loop

            if s(i) = '/' then
                n := n + 1;
            end if;

        end loop;

        return n;

    end function count_groups;

    function count_members (s : in string) return positive is

        -- Contagem de separadores mais um.
        variable n : natural := 1;

    begin

        for i in s'range loop

            if s(i) = ',' or s(i) = '/' then
                n := n + 1;
            end if;

        end loop;

        return n;

    end function count_members;

    function encode_sizes (s : in string) return std_logic_vector is

        -- Resultado, um campo por grupo.
        variable result : std_logic_vector(8 * count_groups(s) - 1 downto 0) := (others => '0');
        -- Grupo atual.
        variable g      : natural                                            := 0;
        -- Tamanho acumulado do grupo atual.
        variable size   : natural                                            := 1;

    begin

        for i in s'range loop

            if s(i) = ',' then
                size := size + 1;
            elsif s(i) = '/' then
                result(8 * g + 7 downto 8 * g) := std_logic_vector(to_unsigned(size, 8));
                g                              := g + 1;
                size                           := 1;
            end if;

        end loop;

        result(8 * g + 7 downto 8 * g) := std_logic_vector(to_unsigned(size, 8));

        return result;

    end function encode_sizes;

    function encode_members (s : in string) return std_logic_vector is

        -- Resultado, um campo por membro.
        variable result : std_logic_vector(8 * count_members(s) - 1 downto 0) := (others => '0');
        -- Membro atual.
        variable m      : natural                                              := 0;
        -- Valor decimal em leitura.
        variable value  : natural                                              := 0;

    begin

        for i in s'range loop

            if s(i) = ',' or s(i) = '/' then
                result(8 * m + 7 downto 8 * m) := std_logic_vector(to_unsigned(value, 8));
                m                              := m + 1;
                value                          := 0;
            else
                value := value * 10 + (character'pos(s(i)) - character'pos('0'));
            end if;

        end loop;

        result(8 * m + 7 downto 8 * m) := std_logic_vector(to_unsigned(value, 8));

        return result;

    end function encode_members;

    function encode_dirs (s : in string) return std_logic_vector is

        -- Resultado, 2 bits por pino.
        variable result : std_logic_vector(2 * s'length - 1 downto 0) := (others => '0');
        -- Pino atual.
        variable p      : natural                                      := 0;

    begin

        for i in s'range loop

            if s(i) = 'i' then
                result(2 * p + 1 downto 2 * p) := "01";
            elsif s(i) = 'o' then
                result(2 * p + 1 downto 2 * p) := "10";
            end if;

            p := p + 1;

        end loop;

        return result;

    end function encode_dirs;

    function encode_lows (s : in string) return std_logic_vector is

        -- Resultado, 1 bit por pino.
        variable result : std_logic_vector(s'length - 1 downto 0) := (others => '0');
        -- Pino atual.
        variable p      : natural                                  := 0;

    begin

        for i in s'range loop

            if s(i) = 'l' then
                result(p) := '1';
            end if;

            p := p + 1;

        end loop;

        return result;

    end function encode_lows;

end package body gpio_partition_pkg;

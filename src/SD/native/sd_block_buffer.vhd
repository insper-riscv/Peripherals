-- ==========================================================================
-- Buffer de bloco de 512 bytes do cartão SD
-- ==========================================================================
-- Memória de 128 palavras de 32 bits com uma porta de escrita e uma porta de
-- leitura síncrona, que o Quartus implementa em memória de bloco. A leitura
-- devolve, uma borda depois do endereço, a palavra do endereço; ao ler e
-- escrever o mesmo endereço no mesmo ciclo, a leitura devolve o valor antigo.
-- O primeiro byte do bloco do cartão ocupa os bits 7 a 0 da palavra 0.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sd_native_pkg.all;

entity sd_block_buffer is
    port (
        -- Clock do módulo.
        i_clk           : in    std_logic;
        -- Escrita de uma palavra na próxima borda.
        i_write_enable  : in    std_logic;
        -- Endereço da palavra escrita.
        i_write_address : in    std_logic_vector(6 downto 0);
        -- Palavra escrita.
        i_write_data    : in    std_logic_vector(31 downto 0);
        -- Endereço da palavra lida.
        i_read_address  : in    std_logic_vector(6 downto 0);
        -- Palavra lida, válida uma borda depois do endereço.
        o_read_data     : out   std_logic_vector(31 downto 0)
    );
end entity sd_block_buffer;

architecture rtl of sd_block_buffer is

    -- Tipo da memória do bloco.
    type memory_t is array (0 to BLOCK_WORDS - 1) of std_logic_vector(31 downto 0);

    -- Conteúdo do bloco.
    signal memory : memory_t := (others => (others => '0'));

begin

    p_memory : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_write_enable = '1' then
                memory(to_integer(unsigned(i_write_address))) <= i_write_data;
            end if;

            o_read_data <= memory(to_integer(unsigned(i_read_address)));
        end if;

    end process p_memory;

end architecture rtl;

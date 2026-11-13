-- =============================================================================
-- Memória de duas portas com clocks independentes
--
-- Porta de escrita em i_wclk e porta de leitura em i_rclk com saída registrada
-- (o_rdata vale o dado do endereço i_raddr da borda anterior). O Quartus a
-- mapeia em blocos M10K. Ler e escrever o mesmo endereço em clocks diferentes
-- devolve o dado antigo ou o novo; quem a usa só lê o que já terminou de
-- escrever.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_dpram is
    generic (
        -- Largura da palavra em bits.
        data_width : positive := 32;
        -- Largura do endereço em bits.
        addr_width : positive := 9
    );
    port (
        -- Clock da porta de escrita.
        i_wclk  : in    std_logic;
        -- Habilitação de escrita.
        i_we    : in    std_logic;
        -- Endereço de escrita.
        i_waddr : in    std_logic_vector(addr_width - 1 downto 0);
        -- Dado de escrita.
        i_wdata : in    std_logic_vector(data_width - 1 downto 0);
        -- Clock da porta de leitura.
        i_rclk  : in    std_logic;
        -- Endereço de leitura.
        i_raddr : in    std_logic_vector(addr_width - 1 downto 0);
        -- Dado lido, registrado em i_rclk.
        o_rdata : out   std_logic_vector(data_width - 1 downto 0)
    );
end entity eth_dpram;

architecture rtl of eth_dpram is

    -- Matriz de palavras.
    type mem_t is array(0 to 2 ** addr_width - 1) of std_logic_vector(data_width - 1 downto 0);

    -- Conteúdo da memória, zerado ao energizar.
    signal mem : mem_t := (others => (others => '0'));

    -- Pede ao Quartus blocos M10K sem lógica de bypass entre as portas.
    attribute ramstyle : string;
    attribute ramstyle of mem : signal is "M10K, no_rw_check";

begin

    p_write : process (i_wclk) is
    begin

        if rising_edge(i_wclk) then
            if i_we = '1' then
                mem(to_integer(unsigned(i_waddr))) <= i_wdata;
            end if;
        end if;

    end process p_write;

    p_read : process (i_rclk) is
    begin

        if rising_edge(i_rclk) then
            o_rdata <= mem(to_integer(unsigned(i_raddr)));
        end if;

    end process p_read;

end architecture rtl;

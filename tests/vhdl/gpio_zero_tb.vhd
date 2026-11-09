-- =============================================================================
-- Testbench do gpio sem pino (largura zero)
--
-- O cocotb não enxerga portas de largura zero, de modo que este testbench liga
-- o gpio com data_width zero a vetores internos vazios e mostra por portas de
-- um bit o que o módulo faz: a interrupção, o comprimento do dado lido e o
-- comprimento dos pinos.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity gpio_zero_tb is
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset, ativo em '1'.
        i_rst      : in    std_logic;
        -- Endereço de palavra acessado pelo processador.
        i_address  : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador ('1' = escreve).
        i_write    : in    std_logic;
        -- Pulso de leitura do processador ('1' = lê).
        i_read     : in    std_logic;
        -- Requisição de interrupção, ativa em '1'.
        o_irq      : out   std_logic;
        -- Comprimento do dado lido, que deve ser zero.
        o_data_len : out   natural;
        -- Comprimento do vetor de pinos, que deve ser zero.
        o_pins_len : out   natural
    );
end entity gpio_zero_tb;

architecture rtl of gpio_zero_tb is

    -- Dado de escrita sem bits.
    signal data_in  : std_logic_vector(-1 downto 0);
    -- Dado lido sem bits.
    signal data_out : std_logic_vector(-1 downto 0);
    -- Pinos sem bits.
    signal pins     : std_logic_vector(-1 downto 0);

begin

    u_dut : entity work.gpio
        generic map (
            data_width => 0
        )
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_data_in    => data_in,
            i_address    => i_address,
            i_write      => i_write,
            i_read       => i_read,
            o_data_out   => data_out,
            o_irq        => o_irq,
            io_gpio_pins => pins
        );

    o_data_len <= data_out'length;
    o_pins_len <= pins'length;

end architecture rtl;

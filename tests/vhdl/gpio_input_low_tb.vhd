-- =============================================================================
-- Testbench do gpio_input com os pinos 0 e 2 ativos em nível baixo
--
-- Fixa o generic active_low do gpio_input, que o simulador não aceita como
-- parâmetro de linha de comando por ter a largura de outro generic. Repassa
-- todas as portas do bloco ao cocotb.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;

entity gpio_input_low_tb is
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra dentro do bloco.
        i_address  : in    std_logic_vector(3 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Dado de leitura.
        o_data_out : out   word_t;
        -- Interrupção de nível.
        o_irq      : out   std_logic;
        -- Nível dos pinos físicos.
        i_pins     : in    std_logic_vector(31 downto 0)
    );
end entity gpio_input_low_tb;

architecture rtl of gpio_input_low_tb is

begin

    u_dut : entity work.gpio_input
        generic map (
            width      => 32,
            active_low => x"00000005"
        )
        port map (
            i_clk      => i_clk,
            i_rst      => i_rst,
            i_data_in  => i_data_in,
            i_address  => i_address,
            i_write    => i_write,
            i_read     => i_read,
            o_data_out => o_data_out,
            o_irq      => o_irq,
            i_pins     => i_pins
        );

end architecture rtl;

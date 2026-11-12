-- =============================================================================
-- Testbench do ps2_keyboard com as linhas PS/2 acessíveis ao cocotb
-- =============================================================================
-- As linhas do conector são portas inout, que o cocotb não conduz. O
-- dispositivo simulado segura uma linha em '0' com i_dev_clk_low e
-- i_dev_dat_low (solta em 'Z' caso contrário), as duas linhas têm pull-up, e
-- o_clk e o_dat mostram o nível resolvido de cada uma.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ps2_keyboard_tb is
    generic (
        -- Largura do barramento de dados em bits.
        data_width    : natural  := 32;
        -- Quantidade de bytes na fila de recepção.
        rx_fifo_depth : positive := 4
    );
    port (
        -- Clock do módulo.
        i_clk          : in    std_logic;
        -- Reset, ativo em nível alto.
        i_rst          : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in      : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra do registrador.
        i_address      : in    std_logic_vector(1 downto 0);
        -- Pulso de escrita do processador.
        i_write        : in    std_logic;
        -- Pulso de leitura do processador.
        i_read         : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out     : out   std_logic_vector(data_width - 1 downto 0);
        -- Requisição de interrupção de nível.
        o_irq          : out   std_logic;
        -- O dispositivo segura o clock em '0'.
        i_dev_clk_low0 : in    std_logic;
        -- O dispositivo segura os dados em '0'.
        i_dev_dat_low0 : in    std_logic;
        -- Nível resolvido do clock.
        o_clk0         : out   std_logic;
        -- Nível resolvido dos dados.
        o_dat0         : out   std_logic
    );
end entity ps2_keyboard_tb;

architecture rtl of ps2_keyboard_tb is

    -- Linha de clock do conector.
    signal clk : std_logic;
    -- Linha de dados do conector.
    signal dat : std_logic;

begin

    clk <= '0' when i_dev_clk_low0 = '1' else 'Z';
    dat <= '0' when i_dev_dat_low0 = '1' else 'Z';
    clk <= 'H';
    dat <= 'H';

    o_clk0 <= to_x01(clk);
    o_dat0 <= to_x01(dat);

    u_dut : entity work.ps2_keyboard
        generic map (
            data_width     => data_width,
            rx_fifo_depth  => rx_fifo_depth,
            filter_cycles  => 4,
            inhibit_cycles => 30,
            timeout_cycles => 600
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
            io_ps2_clk => clk,
            io_ps2_dat => dat
        );

end architecture rtl;

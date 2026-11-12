-- =============================================================================
-- Testbench do ps2_mouse_top com as linhas PS/2 acessíveis ao cocotb
-- =============================================================================
-- As linhas do conector são portas inout, que o cocotb não conduz. O
-- dispositivo simulado segura uma linha em '0' com i_ms_dev_clk_low e
-- i_ms_dev_dat_low (solta em 'Z' caso contrário), as duas linhas têm pull-up,
-- e o_ms_clk e o_ms_dat mostram o nível resolvido de cada uma. Os tempos do
-- ps2_host são curtos para a simulação.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ps2_mouse_top_tb is
    generic (
        -- Largura do barramento de dados em bits.
        data_width            : natural  := 32;
        -- Ciclos sem resposta aceitos durante a inicialização.
        init_timeout_cycles   : positive := 2500;
        -- Ciclos sem byte aceitos no meio de um pacote.
        packet_timeout_cycles : positive := 1500
    );
    port (
        -- Clock do módulo.
        i_clk            : in    std_logic;
        -- Reset, ativo em nível alto.
        i_rst            : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_ms_data_in     : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra do registrador.
        i_ms_address     : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_ms_write       : in    std_logic;
        -- Pulso de leitura do processador.
        i_ms_read        : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_ms_data_out    : out   std_logic_vector(data_width - 1 downto 0);
        -- Requisição de interrupção.
        o_ms_irq         : out   std_logic;
        -- O mouse simulado segura o clock em '0'.
        i_ms_dev_clk_low : in    std_logic;
        -- O mouse simulado segura os dados em '0'.
        i_ms_dev_dat_low : in    std_logic;
        -- Nível resolvido do clock.
        o_ms_clk         : out   std_logic;
        -- Nível resolvido dos dados.
        o_ms_dat         : out   std_logic
    );
end entity ps2_mouse_top_tb;

architecture rtl of ps2_mouse_top_tb is

    -- Linha de clock do conector.
    signal clk : std_logic;
    -- Linha de dados do conector.
    signal dat : std_logic;

begin

    clk <= '0' when i_ms_dev_clk_low = '1' else 'Z';
    dat <= '0' when i_ms_dev_dat_low = '1' else 'Z';
    clk <= 'H';
    dat <= 'H';

    o_ms_clk <= to_x01(clk);
    o_ms_dat <= to_x01(dat);

    u_dut : entity work.ps2_mouse_top
        generic map (
            data_width            => data_width,
            filter_cycles         => 4,
            inhibit_cycles        => 30,
            timeout_cycles        => 600,
            init_timeout_cycles   => init_timeout_cycles,
            packet_timeout_cycles => packet_timeout_cycles
        )
        port map (
            i_clk      => i_clk,
            i_rst      => i_rst,
            i_data_in  => i_ms_data_in,
            i_address  => i_ms_address,
            i_write    => i_ms_write,
            i_read     => i_ms_read,
            o_data_out => o_ms_data_out,
            o_irq      => o_ms_irq,
            io_ps2_clk => clk,
            io_ps2_dat => dat
        );

end architecture rtl;

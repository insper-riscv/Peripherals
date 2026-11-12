-- =============================================================================
-- Testbench do cabo Y: teclado no canal 0 e mouse no canal 1
-- =============================================================================
-- Reproduz a placa com os dois periféricos PS/2 ativos ao mesmo tempo, cada
-- um com o seu ps2_host e as suas duas linhas puxadas a '1' por resistores. Os
-- dispositivos simulados pelo cocotb seguram uma linha em '0' com
-- i_dev_clk_low e i_dev_dat_low (solta em 'Z' caso contrário), e o_clk e o_dat
-- mostram o nível resolvido de cada linha. Os dois barramentos são
-- independentes e usam prefixos kb (teclado) e ms (mouse).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ps2_cable_tb is
    generic (
        -- Largura do barramento de dados em bits.
        data_width            : natural  := 32;
        -- Quantidade de bytes na fila de recepção do teclado.
        rx_fifo_depth         : positive := 8;
        -- Ciclos sem resposta aceitos pelo mouse durante a inicialização.
        init_timeout_cycles   : positive := 2500;
        -- Ciclos sem byte aceitos pelo mouse no meio de um pacote.
        packet_timeout_cycles : positive := 1500
    );
    port (
        -- Clock do módulo.
        i_clk            : in    std_logic;
        -- Reset, ativo em nível alto.
        i_rst            : in    std_logic;
        -- Dado de escrita do barramento do teclado.
        i_kb_data_in     : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra do teclado.
        i_kb_address     : in    std_logic_vector(1 downto 0);
        -- Pulso de escrita do teclado.
        i_kb_write       : in    std_logic;
        -- Pulso de leitura do teclado.
        i_kb_read        : in    std_logic;
        -- Dado de leitura do teclado.
        o_kb_data_out    : out   std_logic_vector(data_width - 1 downto 0);
        -- Interrupção do teclado.
        o_kb_irq         : out   std_logic;
        -- O teclado simulado segura o clock em '0'.
        i_kb_dev_clk_low : in    std_logic;
        -- O teclado simulado segura os dados em '0'.
        i_kb_dev_dat_low : in    std_logic;
        -- Nível resolvido do clock do teclado.
        o_kb_clk         : out   std_logic;
        -- Nível resolvido dos dados do teclado.
        o_kb_dat         : out   std_logic;
        -- Dado de escrita do barramento do mouse.
        i_ms_data_in     : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra do mouse.
        i_ms_address     : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do mouse.
        i_ms_write       : in    std_logic;
        -- Pulso de leitura do mouse.
        i_ms_read        : in    std_logic;
        -- Dado de leitura do mouse.
        o_ms_data_out    : out   std_logic_vector(data_width - 1 downto 0);
        -- Interrupção do mouse.
        o_ms_irq         : out   std_logic;
        -- O mouse simulado segura o clock em '0'.
        i_ms_dev_clk_low : in    std_logic;
        -- O mouse simulado segura os dados em '0'.
        i_ms_dev_dat_low : in    std_logic;
        -- Nível resolvido do clock do mouse.
        o_ms_clk         : out   std_logic;
        -- Nível resolvido dos dados do mouse.
        o_ms_dat         : out   std_logic
    );
end entity ps2_cable_tb;

architecture rtl of ps2_cable_tb is

    -- Linha de clock do teclado.
    signal kb_clk : std_logic;
    -- Linha de dados do teclado.
    signal kb_dat : std_logic;
    -- Linha de clock do mouse.
    signal ms_clk : std_logic;
    -- Linha de dados do mouse.
    signal ms_dat : std_logic;

begin

    kb_clk <= '0' when i_kb_dev_clk_low = '1' else 'Z';
    kb_dat <= '0' when i_kb_dev_dat_low = '1' else 'Z';
    ms_clk <= '0' when i_ms_dev_clk_low = '1' else 'Z';
    ms_dat <= '0' when i_ms_dev_dat_low = '1' else 'Z';

    kb_clk <= 'H';
    kb_dat <= 'H';
    ms_clk <= 'H';
    ms_dat <= 'H';

    o_kb_clk <= to_x01(kb_clk);
    o_kb_dat <= to_x01(kb_dat);
    o_ms_clk <= to_x01(ms_clk);
    o_ms_dat <= to_x01(ms_dat);

    u_keyboard : entity work.ps2_keyboard
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
            i_data_in  => i_kb_data_in,
            i_address  => i_kb_address,
            i_write    => i_kb_write,
            i_read     => i_kb_read,
            o_data_out => o_kb_data_out,
            o_irq      => o_kb_irq,
            io_ps2_clk => kb_clk,
            io_ps2_dat => kb_dat
        );

    u_mouse : entity work.ps2_mouse_top
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
            io_ps2_clk => ms_clk,
            io_ps2_dat => ms_dat
        );

end architecture rtl;

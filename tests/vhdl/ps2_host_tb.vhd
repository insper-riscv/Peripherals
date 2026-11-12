-- =============================================================================
-- Testbench de dois canais ps2_host lado a lado
-- =============================================================================
-- Reproduz o cabo Y da placa: duas instâncias independentes de ps2_host, uma
-- por canal, cada uma com as suas duas linhas puxadas a '1' por resistores. O
-- dispositivo simulado pelo cocotb segura uma linha em '0' com i_dev_clk_low e
-- i_dev_dat_low; o_clk e o_dat mostram o nível resolvido de cada linha.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ps2_host_tb is
    generic (
        -- Ciclos de clock que um nível das linhas precisa durar para passar no filtro.
        filter_cycles  : positive := 4;
        -- Ciclos com o clock segurado em '0' antes de uma transmissão.
        inhibit_cycles : positive := 30;
        -- Ciclos sem borda de clock que abortam um quadro.
        timeout_cycles : positive := 600
    );
    port (
        -- Clock do sistema.
        i_clk          : in    std_logic;
        -- Reset, ativo em nível baixo.
        i_rst_n        : in    std_logic;
        -- O dispositivo do canal 0 segura o clock em '0'.
        i_dev_clk_low0 : in    std_logic;
        -- O dispositivo do canal 0 segura os dados em '0'.
        i_dev_dat_low0 : in    std_logic;
        -- Byte a enviar pelo canal 0.
        i_tx_data0     : in    std_logic_vector(7 downto 0);
        -- Pedido de envio pelo canal 0.
        i_tx_valid0    : in    std_logic;
        -- Último byte recebido pelo canal 0.
        o_rx_data0     : out   std_logic_vector(7 downto 0);
        -- Pulso de byte recebido no canal 0.
        o_rx_valid0    : out   std_logic;
        -- Pulso de erro no canal 0.
        o_rx_error0    : out   std_logic;
        -- O canal 0 aceita um novo byte.
        o_tx_ready0    : out   std_logic;
        -- Nível resolvido do clock do canal 0.
        o_clk0         : out   std_logic;
        -- Nível resolvido dos dados do canal 0.
        o_dat0         : out   std_logic;
        -- O dispositivo do canal 1 segura o clock em '0'.
        i_dev_clk_low1 : in    std_logic;
        -- O dispositivo do canal 1 segura os dados em '0'.
        i_dev_dat_low1 : in    std_logic;
        -- Byte a enviar pelo canal 1.
        i_tx_data1     : in    std_logic_vector(7 downto 0);
        -- Pedido de envio pelo canal 1.
        i_tx_valid1    : in    std_logic;
        -- Último byte recebido pelo canal 1.
        o_rx_data1     : out   std_logic_vector(7 downto 0);
        -- Pulso de byte recebido no canal 1.
        o_rx_valid1    : out   std_logic;
        -- Pulso de erro no canal 1.
        o_rx_error1    : out   std_logic;
        -- O canal 1 aceita um novo byte.
        o_tx_ready1    : out   std_logic;
        -- Nível resolvido do clock do canal 1.
        o_clk1         : out   std_logic;
        -- Nível resolvido dos dados do canal 1.
        o_dat1         : out   std_logic
    );
end entity ps2_host_tb;

architecture rtl of ps2_host_tb is

    -- Linha de clock do canal 0.
    signal clk0 : std_logic;
    -- Linha de dados do canal 0.
    signal dat0 : std_logic;
    -- Linha de clock do canal 1.
    signal clk1 : std_logic;
    -- Linha de dados do canal 1.
    signal dat1 : std_logic;

begin

    clk0 <= '0' when i_dev_clk_low0 = '1' else 'Z';
    dat0 <= '0' when i_dev_dat_low0 = '1' else 'Z';
    clk1 <= '0' when i_dev_clk_low1 = '1' else 'Z';
    dat1 <= '0' when i_dev_dat_low1 = '1' else 'Z';

    clk0 <= 'H';
    dat0 <= 'H';
    clk1 <= 'H';
    dat1 <= 'H';

    o_clk0 <= to_x01(clk0);
    o_dat0 <= to_x01(dat0);
    o_clk1 <= to_x01(clk1);
    o_dat1 <= to_x01(dat1);

    u_channel0 : entity work.ps2_host
        generic map (
            filter_cycles  => filter_cycles,
            inhibit_cycles => inhibit_cycles,
            timeout_cycles => timeout_cycles
        )
        port map (
            i_clk      => i_clk,
            i_rst_n    => i_rst_n,
            io_ps2_clk => clk0,
            io_ps2_dat => dat0,
            o_rx_data  => o_rx_data0,
            o_rx_valid => o_rx_valid0,
            o_rx_error => o_rx_error0,
            i_tx_data  => i_tx_data0,
            i_tx_valid => i_tx_valid0,
            o_tx_ready => o_tx_ready0
        );

    u_channel1 : entity work.ps2_host
        generic map (
            filter_cycles  => filter_cycles,
            inhibit_cycles => inhibit_cycles,
            timeout_cycles => timeout_cycles
        )
        port map (
            i_clk      => i_clk,
            i_rst_n    => i_rst_n,
            io_ps2_clk => clk1,
            io_ps2_dat => dat1,
            o_rx_data  => o_rx_data1,
            o_rx_valid => o_rx_valid1,
            o_rx_error => o_rx_error1,
            i_tx_data  => i_tx_data1,
            i_tx_valid => i_tx_valid1,
            o_tx_ready => o_tx_ready1
        );

end architecture rtl;

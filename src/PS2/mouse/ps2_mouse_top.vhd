-- ==========================================================================
-- Mouse PS/2 completo: camada física e registradores de um canal
-- ==========================================================================
-- Topo estrutural que liga a camada física (ps2_host) ao mouse mapeado em
-- memória (ps2_mouse) e expõe o mesmo conjunto de portas do ps2_keyboard:
-- as portas do barramento do núcleo e as duas linhas open-drain do conector.
-- Cada instância atende um canal, então o mouse (canal 1) e o teclado
-- (canal 0) coexistem num cabo Y sem compartilhar estado. A única lógica do
-- topo é a inversão do reset, ativo em nível alto no barramento e em nível
-- baixo na camada física.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;

entity ps2_mouse_top is
    generic (
        -- Largura do barramento de dados em bits.
        data_width            : integer  := 32;
        -- Ciclos que um nível das linhas precisa durar para passar no filtro de glitch.
        filter_cycles         : positive := 8;
        -- Ciclos com o clock em '0' antes de um comando (padrão de 120 us a 50 MHz).
        inhibit_cycles        : positive := 6000;
        -- Ciclos sem borda de clock que abortam um quadro (padrão de 20 ms a 50 MHz).
        timeout_cycles        : positive := 1000000;
        -- Ciclos de clock sem resposta aceitos durante a inicialização.
        init_timeout_cycles   : positive := 100_000_000;
        -- Ciclos de clock sem byte aceitos no meio de um pacote.
        packet_timeout_cycles : positive := 5_000_000
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra de 3 bits vindo do processador.
        i_address  : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out : out   std_logic_vector(data_width - 1 downto 0);
        -- Requisição de interrupção, ativa em '1'.
        o_irq      : out   std_logic;
        -- Linha de clock do conector PS/2, open-drain.
        io_ps2_clk : inout std_logic;
        -- Linha de dados do conector PS/2, open-drain.
        io_ps2_dat : inout std_logic
    );
end entity ps2_mouse_top;

architecture rtl of ps2_mouse_top is

    -- Reset da camada física, ativo em nível baixo.
    signal rst_n : std_logic;

    -- Byte entregue pela camada física ao mouse.
    signal phy_rx_data  : std_logic_vector(7 downto 0);
    -- Pulso de byte recebido.
    signal phy_rx_valid : std_logic;
    -- Pulso de erro da camada física.
    signal phy_rx_error : std_logic;
    -- Byte que o mouse manda à camada física.
    signal phy_tx_data  : std_logic_vector(7 downto 0);
    -- Pulso de pedido de envio.
    signal phy_tx_valid : std_logic;
    -- A camada física aceita um byte.
    signal phy_tx_ready : std_logic;

begin

    rst_n <= not i_rst;

    u_host : entity work.ps2_host
        generic map (
            filter_cycles  => filter_cycles,
            inhibit_cycles => inhibit_cycles,
            timeout_cycles => timeout_cycles
        )
        port map (
            i_clk      => i_clk,
            i_rst_n    => rst_n,
            io_ps2_clk => io_ps2_clk,
            io_ps2_dat => io_ps2_dat,
            o_rx_data  => phy_rx_data,
            o_rx_valid => phy_rx_valid,
            o_rx_error => phy_rx_error,
            i_tx_data  => phy_tx_data,
            i_tx_valid => phy_tx_valid,
            o_tx_ready => phy_tx_ready
        );

    u_mouse : entity work.ps2_mouse
        generic map (
            data_width            => data_width,
            init_timeout_cycles   => init_timeout_cycles,
            packet_timeout_cycles => packet_timeout_cycles
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
            i_rx_data  => phy_rx_data,
            i_rx_valid => phy_rx_valid,
            i_rx_error => phy_rx_error,
            o_tx_data  => phy_tx_data,
            o_tx_valid => phy_tx_valid,
            i_tx_ready => phy_tx_ready
        );

end architecture rtl;

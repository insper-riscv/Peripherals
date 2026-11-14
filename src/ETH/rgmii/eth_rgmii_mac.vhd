-- =============================================================================
-- MAC Ethernet de 10, 100 e 1000 Mbit/s em RGMII
--
-- Topo estrutural que liga o MAC com GMII (eth, com gigabit em true) à camada
-- RGMII (eth_rgmii), de modo que os pinos do PHY são os do RGMII e o barramento
-- e os registradores são os do eth, mais o registrador SPEED. Uma instância
-- atende um PHY: as duas portas da placa são duas instâncias. i_tx_clk é o clock
-- livre de 125 MHz do envio, que a plataforma gera por PLL; i_tx_clk_dly é o
-- mesmo clock deslocado de 90 graus, ou i_tx_clk quando o PHY atrasa TXC. Os
-- registradores DDR dos pinos são as entidades eth_ddr_in e eth_ddr_out, que a
-- plataforma escolhe entre o modelo da simulação e o do fabricante.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.config_pkg.all;
use work.eth_consts.all;

entity eth_rgmii_mac is
    generic (
        -- Frequência do clock do sistema em hertz.
        clk_freq_hz         : positive := 50_000_000;
        -- Frequência de MDC em hertz.
        mdc_freq_hz         : positive := 2_500_000;
        -- Largura do endereço de palavra do buffer de envio (2**n palavras).
        tx_buffer_addr_bits : positive := 9;
        -- Largura do endereço de palavra do buffer de recepção (2**n palavras).
        rx_buffer_addr_bits : positive := 9;
        -- Largura do endereço da FIFO de recepção (2**n bytes); 11 comporta um quadro máximo sem esvaziar.
        rx_fifo_addr_bits   : positive := 11;
        -- Estágios dos sincronizadores entre domínios.
        sync_stages         : positive := 2;
        -- Ciclos do clock do sistema em que os domínios do PHY ficam em reset.
        reset_cycles        : positive := 64;
        -- Endereço MDIO do PHY (PHYADDR do chip).
        phy_addr            : natural range 0 to 31 := 16;
        -- Ciclos do sistema entre duas consultas de velocidade ao PHY.
        poll_cycles         : positive := 50_000;
        -- Verdadeiro quando i_tx_clk_dly é i_tx_clk deslocado de 90 graus, falso quando é o próprio i_tx_clk.
        shifted_txc         : boolean := true
    );
    port (
        -- Clock do sistema.
        i_clk          : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst          : in    std_logic;
        -- Pulso de escrita do núcleo.
        i_write        : in    std_logic;
        -- Pulso de leitura do núcleo.
        i_read         : in    std_logic;
        -- Endereço de palavra.
        i_address      : in    std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita.
        i_data_in      : in    word_t;
        -- Dado de leitura.
        o_data_out     : out   word_t;
        -- Interrupção, ativa em '1'.
        o_irq          : out   std_logic;

        -- Clock livre de 125 MHz do envio.
        i_tx_clk       : in    std_logic;
        -- Clock de TXC, i_tx_clk ou o mesmo clock deslocado de 90 graus.
        i_tx_clk_dly   : in    std_logic;
        -- TXC para o PHY (ENETn_GTX_CLK).
        o_rgmii_txc    : out   std_logic;
        -- TXD para o PHY (ENETn_TX_DATA).
        o_rgmii_txd    : out   std_logic_vector(3 downto 0);
        -- TX_CTL para o PHY (ENETn_TX_EN).
        o_rgmii_tx_ctl : out   std_logic;
        -- RXC do PHY (ENETn_RX_CLK).
        i_rgmii_rxc    : in    std_logic;
        -- RXD do PHY (ENETn_RX_DATA).
        i_rgmii_rxd    : in    std_logic_vector(3 downto 0);
        -- RX_CTL do PHY (ENETn_RX_DV).
        i_rgmii_rx_ctl : in    std_logic;

        -- MDC para o PHY (ENETn_MDC).
        o_mdc          : out   std_logic;
        -- Entrada do pino MDIO (ENETn_MDIO).
        i_mdio         : in    std_logic;
        -- Saída do pino MDIO.
        o_mdio_out     : out   std_logic;
        -- Habilitação do driver do pino MDIO.
        o_mdio_oe      : out   std_logic;
        -- INT_N do PHY, ativo em '0' (ENETn_INT_N).
        i_phy_int_n    : in    std_logic;
        -- RESET_N para o PHY, ativo em '0' (ENETn_RST_N).
        o_phy_rst_n    : out   std_logic
    );
end entity eth_rgmii_mac;

architecture rtl of eth_rgmii_mac is

    -- Velocidade em uso, no domínio do envio.
    signal tx_speed    : std_logic_vector(1 downto 0);
    -- Habilitação de avanço do MAC de envio.
    signal tx_ce       : std_logic;
    -- Dados do GMII do MAC para a camada RGMII.
    signal gmii_txd    : std_logic_vector(7 downto 0);
    -- TX_EN do GMII.
    signal gmii_tx_en  : std_logic;
    -- TX_ER do GMII.
    signal gmii_tx_er  : std_logic;
    -- Dados do GMII da camada RGMII para o MAC.
    signal gmii_rxd    : std_logic_vector(7 downto 0);
    -- RX_DV do GMII.
    signal gmii_rx_dv  : std_logic;
    -- RX_ER do GMII.
    signal gmii_rx_er  : std_logic;

begin

    u_mac : entity work.eth
        generic map (
            gigabit             => true,
            clk_freq_hz         => clk_freq_hz,
            mdc_freq_hz         => mdc_freq_hz,
            tx_buffer_addr_bits => tx_buffer_addr_bits,
            rx_buffer_addr_bits => rx_buffer_addr_bits,
            rx_fifo_addr_bits   => rx_fifo_addr_bits,
            sync_stages         => sync_stages,
            reset_cycles        => reset_cycles,
            phy_addr            => phy_addr,
            poll_cycles         => poll_cycles
        )
        port map (
            i_clk        => i_clk,
            i_rst        => i_rst,
            i_write      => i_write,
            i_read       => i_read,
            i_address    => i_address,
            i_data_in    => i_data_in,
            o_data_out   => o_data_out,
            o_irq        => o_irq,
            i_mii_rx_clk => i_rgmii_rxc,
            i_mii_rxd    => gmii_rxd,
            i_mii_rx_dv  => gmii_rx_dv,
            i_mii_rx_er  => gmii_rx_er,
            i_mii_tx_clk => i_tx_clk,
            i_tx_ce      => tx_ce,
            o_tx_speed   => tx_speed,
            o_mii_txd    => gmii_txd,
            o_mii_tx_en  => gmii_tx_en,
            o_mii_tx_er  => gmii_tx_er,
            o_mdc        => o_mdc,
            i_mdio       => i_mdio,
            o_mdio_out   => o_mdio_out,
            o_mdio_oe    => o_mdio_oe,
            i_phy_int_n  => i_phy_int_n,
            o_phy_rst_n  => o_phy_rst_n
        );

    u_rgmii : entity work.eth_rgmii
        generic map (
            shifted_txc => shifted_txc
        )
        port map (
            i_tx_clk       => i_tx_clk,
            i_tx_clk_dly   => i_tx_clk_dly,
            i_tx_speed     => tx_speed,
            o_tx_ce        => tx_ce,
            i_gmii_txd     => gmii_txd,
            i_gmii_tx_en   => gmii_tx_en,
            i_gmii_tx_er   => gmii_tx_er,
            o_rgmii_txc    => o_rgmii_txc,
            o_rgmii_txd    => o_rgmii_txd,
            o_rgmii_tx_ctl => o_rgmii_tx_ctl,
            i_rgmii_rxc    => i_rgmii_rxc,
            i_rgmii_rxd    => i_rgmii_rxd,
            i_rgmii_rx_ctl => i_rgmii_rx_ctl,
            o_gmii_rxd     => gmii_rxd,
            o_gmii_rx_dv   => gmii_rx_dv,
            o_gmii_rx_er   => gmii_rx_er
        );

end architecture rtl;

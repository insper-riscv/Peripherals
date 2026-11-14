-- =============================================================================
-- MAC Ethernet de 10, 100 e 1000 Mbit/s em MII ou GMII com mestre MDIO
--
-- Topo estrutural do periférico de barramento que liga um PHY como o Marvell
-- 88E1111 das placas DE2-115 (uma instância por PHY, ENET0 e ENET1). Reúne os
-- registradores, o transmissor (domínio do TX_CLK), o receptor (domínio do
-- RX_CLK) com a FIFO assíncrona de Gray até o domínio do sistema, os buffers
-- de quadro em memória de dois clocks e o mestre MDIO. Os resets dos domínios
-- do PHY nascem do reset do sistema, alongado e sincronizado. Os pinos do PHY
-- são portas: o pino MDIO bidirecional chega como entrada, saída e habilitação
-- para a camada de tristate do topo da plataforma, e o periférico não
-- instancia primitiva de fabricante.
--
-- Com gigabit em false é o MAC de 10 e 100 Mbit/s do MII, com o clock de cada
-- sentido vindo do PHY e nibbles de quatro bits. Com gigabit em true os dados
-- têm oito bits (GMII), o registrador SPEED escolhe a velocidade (automática,
-- lida do PHY por MDIO, ou forçada) e o transmissor roda no clock livre de
-- 125 MHz de i_mii_tx_clk, avançando só com i_tx_ce: um byte por ciclo a
-- 1000 Mbit/s e um nibble a cada i_tx_ce a 100 e 10 Mbit/s. A camada que leva o
-- GMII ao RGMII fica em eth_rgmii, fora deste bloco.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.eth_consts.all;
use work.eth_gmii_consts.all;

entity eth is
    generic (
        -- Verdadeiro habilita o GMII de oito bits e a seleção de velocidade de 1000 Mbit/s.
        gigabit             : boolean := false;
        -- Endereço MDIO do PHY consultado pela velocidade automática (PHYADDR do chip).
        phy_addr            : natural range 0 to 31 := 16;
        -- Ciclos do sistema entre duas consultas de velocidade ao PHY.
        poll_cycles         : positive := 50_000;
        -- Frequência do clock do sistema em hertz.
        clk_freq_hz         : positive := 50_000_000;
        -- Frequência de MDC em hertz (2,5 MHz é o limite do 88E1111).
        mdc_freq_hz         : positive := 2_500_000;
        -- Largura do endereço de palavra do buffer de envio (2**n palavras).
        tx_buffer_addr_bits : positive := 9;
        -- Largura do endereço de palavra do buffer de recepção (2**n palavras).
        rx_buffer_addr_bits : positive := 9;
        -- Largura do endereço da FIFO de recepção (2**n bytes).
        rx_fifo_addr_bits   : positive := 4;
        -- Estágios dos sincronizadores entre domínios.
        sync_stages         : positive := 2;
        -- Ciclos do clock do sistema em que os domínios do PHY ficam em reset.
        reset_cycles        : positive := 64
    );
    port (
        -- Clock do sistema.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de escrita do núcleo.
        i_write       : in    std_logic;
        -- Pulso de leitura do núcleo.
        i_read        : in    std_logic;
        -- Endereço de palavra.
        i_address     : in    std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita.
        i_data_in     : in    word_t;
        -- Dado de leitura.
        o_data_out    : out   word_t;
        -- Interrupção, ativa em '1'.
        o_irq         : out   std_logic;

        -- RX_CLK do PHY (ENETn_RX_CLK).
        i_mii_rx_clk  : in    std_logic;
        -- RXD do PHY (ENETn_RX_DATA), com oito bits no GMII.
        i_mii_rxd     : in    std_logic_vector(phy_data_width(gigabit) - 1 downto 0);
        -- RX_DV do PHY (ENETn_RX_DV).
        i_mii_rx_dv   : in    std_logic;
        -- RX_ER do PHY (ENETn_RX_ER).
        i_mii_rx_er   : in    std_logic;
        -- TX_CLK do PHY (ENETn_TX_CLK), ou o clock livre de 125 MHz do GMII.
        i_mii_tx_clk  : in    std_logic;
        -- Habilitação de avanço do transmissor no GMII; fica em '1' no MII.
        i_tx_ce       : in    std_logic := '1';
        -- Velocidade em uso, sincronizada ao clock de envio (SPEED_*); sem uso no MII.
        o_tx_speed    : out   std_logic_vector(1 downto 0);
        -- TXD para o PHY (ENETn_TX_DATA), com oito bits no GMII.
        o_mii_txd     : out   std_logic_vector(phy_data_width(gigabit) - 1 downto 0);
        -- TX_EN para o PHY (ENETn_TX_EN).
        o_mii_tx_en   : out   std_logic;
        -- TX_ER para o PHY (ENETn_TX_ER), sempre em '0'.
        o_mii_tx_er   : out   std_logic;
        -- MDC para o PHY (ENETn_MDC).
        o_mdc         : out   std_logic;
        -- Entrada do pino MDIO (ENETn_MDIO).
        i_mdio        : in    std_logic;
        -- Saída do pino MDIO.
        o_mdio_out    : out   std_logic;
        -- Habilitação do driver do pino MDIO.
        o_mdio_oe     : out   std_logic;
        -- INT_N do PHY, ativo em '0' (ENETn_INT_N).
        i_phy_int_n   : in    std_logic;
        -- RESET_N para o PHY, ativo em '0' (ENETn_RST_N).
        o_phy_rst_n   : out   std_logic
    );
end entity eth;

architecture rtl of eth is

    -- Largura do comprimento de quadro do buffer de envio.
    constant TX_LEN_WIDTH : positive := tx_buffer_addr_bits + 3;
    -- Largura do comprimento de quadro do buffer de recepção.
    constant RX_LEN_WIDTH : positive := rx_buffer_addr_bits + 3;

    -- Pedido de reset de qualquer origem.
    signal reset_req     : std_logic;
    -- Reset alongado do domínio do sistema.
    signal rst           : std_logic;
    -- Reset do domínio do TX_CLK, sincronizado.
    signal rst_tx        : std_logic;
    -- Reset do domínio do RX_CLK, sincronizado.
    signal rst_rx        : std_logic;
    -- Vetores de um bit dos sincronizadores de reset.
    signal rst_tx_vec    : std_logic_vector(0 downto 0);
    -- Reset do domínio do RX_CLK em vetor de um bit.
    signal rst_rx_vec    : std_logic_vector(0 downto 0);
    -- Pedido de reset por software.
    signal soft_reset    : std_logic;

    -- Dado de escrita e de leitura dos registradores, 32 bits.
    signal reg_data_in   : std_logic_vector(31 downto 0);
    -- Dado de leitura dos registradores.
    signal reg_data_out  : std_logic_vector(31 downto 0);

    -- Configuração vinda dos registradores.
    signal enable, promiscuous, broadcast, multicast, accept_errors, phy_reset : std_logic;
    -- Endereço MAC próprio.
    signal mac_addr      : std_logic_vector(47 downto 0);

    -- Escrita, endereço e dado do buffer de envio.
    signal tx_ram_we     : std_logic;
    -- Endereço de escrita no buffer de envio.
    signal tx_ram_waddr  : std_logic_vector(tx_buffer_addr_bits - 1 downto 0);
    -- Palavra escrita no buffer de envio.
    signal tx_ram_wdata  : std_logic_vector(31 downto 0);
    -- Leitura do buffer de envio pelo transmissor.
    signal tx_ram_raddr  : std_logic_vector(tx_buffer_addr_bits - 1 downto 0);
    -- Palavra lida do buffer de envio.
    signal tx_ram_rdata  : std_logic_vector(31 downto 0);
    -- Comprimento, início e fim do envio.
    signal tx_len        : std_logic_vector(TX_LEN_WIDTH - 1 downto 0);
    -- Início do envio no domínio do sistema.
    signal tx_start_sys  : std_logic;
    -- Início do envio no domínio do TX_CLK.
    signal tx_start_phy  : std_logic;
    -- Fim do envio no domínio do TX_CLK.
    signal tx_done_phy   : std_logic;
    -- Fim do envio no domínio do sistema.
    signal tx_done_sys   : std_logic;
    -- Ocupação do transmissor, sem uso fora do domínio do PHY.
    signal tx_busy_phy   : std_logic;

    -- Palavras da FIFO de recepção.
    signal fifo_wr_en    : std_logic;
    -- Palavra do receptor para a FIFO.
    signal fifo_wr_data  : std_logic_vector(8 downto 0);
    -- FIFO cheia, vista pelo receptor.
    signal fifo_full     : std_logic;
    -- FIFO cheia depois da escrita em curso, vista pelo receptor.
    signal fifo_full_next : std_logic;
    -- Retirada de uma palavra da FIFO.
    signal fifo_rd_en    : std_logic;
    -- Palavra do topo da FIFO.
    signal fifo_rd_data  : std_logic_vector(8 downto 0);
    -- FIFO vazia, vista pelo sistema.
    signal fifo_empty    : std_logic;

    -- Buffer de recepção.
    signal rx_ram_we     : std_logic;
    -- Endereço de escrita no buffer de recepção.
    signal rx_ram_waddr  : std_logic_vector(rx_buffer_addr_bits - 1 downto 0);
    -- Palavra escrita no buffer de recepção.
    signal rx_ram_wdata  : std_logic_vector(31 downto 0);
    -- Endereço de leitura do buffer de recepção.
    signal rx_ram_raddr  : std_logic_vector(rx_buffer_addr_bits - 1 downto 0);
    -- Palavra lida do buffer de recepção.
    signal rx_ram_rdata  : std_logic_vector(31 downto 0);
    -- Há quadro pronto no buffer de recepção.
    signal rx_ready      : std_logic;
    -- Comprimento do quadro pronto.
    signal rx_len        : std_logic_vector(RX_LEN_WIDTH - 1 downto 0);
    -- Liberação do quadro pronto.
    signal rx_release    : std_logic;

    -- Eventos do receptor.
    -- Evento de quadro entregue.
    signal ev_frame : std_logic;
    -- Evento de erro de CRC.
    signal ev_crc : std_logic;
    -- Evento de erro de PHY.
    signal ev_phy : std_logic;
    -- Evento de quadro descartado.
    signal ev_dropped : std_logic;
    -- Evento de quadro filtrado.
    signal ev_filtered : std_logic;

    -- MDIO.
    signal mdio_start    : std_logic;
    -- A transação MDIO é de escrita.
    signal mdio_write    : std_logic;
    -- Endereço do PHY da transação MDIO.
    signal mdio_phy_addr : std_logic_vector(4 downto 0);
    -- Endereço do registrador da transação MDIO.
    signal mdio_reg_addr : std_logic_vector(4 downto 0);
    -- Dado a escrever pelo MDIO.
    signal mdio_wdata    : std_logic_vector(15 downto 0);
    -- Dado lido pelo MDIO.
    signal mdio_rdata    : std_logic_vector(15 downto 0);
    -- Mestre MDIO ocupado.
    signal mdio_busy     : std_logic;
    -- Transação MDIO concluída.
    signal mdio_done     : std_logic;
    -- O PHY não respondeu à leitura MDIO.
    signal mdio_no_ack   : std_logic;

    -- Entrada do mestre MDIO: início da transação, vinda do programa ou da consulta de velocidade.
    signal m_start       : std_logic;
    -- Entrada do mestre MDIO: operação de escrita.
    signal m_write       : std_logic;
    -- Entrada do mestre MDIO: endereço do PHY.
    signal m_phy_addr    : std_logic_vector(4 downto 0);
    -- Entrada do mestre MDIO: endereço do registrador.
    signal m_reg_addr    : std_logic_vector(4 downto 0);
    -- Saída do mestre MDIO: ocupado.
    signal m_busy        : std_logic;
    -- Saída do mestre MDIO: pulso de fim de transação.
    signal m_done        : std_logic;
    -- Saída do mestre MDIO: o PHY não respondeu.
    signal m_no_ack      : std_logic;
    -- A consulta de velocidade inicia uma leitura neste ciclo.
    signal poll_start    : std_logic;
    -- Endereço do PHY da consulta de velocidade.
    signal poll_phy_addr : std_logic_vector(4 downto 0);
    -- Endereço do registrador da consulta de velocidade.
    signal poll_reg_addr : std_logic_vector(4 downto 0);
    -- A consulta de velocidade usa o mestre MDIO.
    signal poll_hold     : std_logic;
    -- Palavra do registrador SPEED, zero sem o modo gigabit.
    signal speed_word    : std_logic_vector(31 downto 0);
    -- Velocidade em uso no domínio do sistema.
    signal speed_sys     : std_logic_vector(1 downto 0);
    -- Velocidade em uso sincronizada ao clock de envio.
    signal speed_tx      : std_logic_vector(1 downto 0);
    -- Velocidade de 1000 Mbit/s sincronizada ao clock de recepção, em vetor de um bit.
    signal wide_rx_vec   : std_logic_vector(0 downto 0);
    -- Dados do receptor com oito bits.
    signal rx_data8      : std_logic_vector(7 downto 0);
    -- Dados do transmissor com oito bits.
    signal tx_data8      : std_logic_vector(7 downto 0);
    -- Palavra lida do barramento antes do ajuste de largura.
    signal read_word     : std_logic_vector(31 downto 0);
    -- Último estado de falta de resposta de uma leitura MDIO do programa.
    signal sw_no_ack     : std_logic := '0';

    -- INT_N do PHY sincronizado e com polaridade ativa em '1'.
    signal phy_int_sync  : std_logic_vector(0 downto 0);
    -- Interrupção do PHY, ativa em '1'.
    signal phy_int       : std_logic;
    -- Reset do PHY registrado, para não gerar glitch no pino.
    signal phy_rst_n_reg : std_logic := '1';

begin

    reg_data_in <= i_data_in(31 downto 0);
    read_word   <= speed_word when gigabit and i_address = SPEED_ADDR else reg_data_out;
    o_data_out  <= std_logic_vector(resize(unsigned(read_word), word_t'length));

    -----------------------------------------------------------------------------
    -- Resets
    -----------------------------------------------------------------------------

    reset_req <= i_rst or soft_reset;

    u_reset : entity work.eth_reset_stretch
        generic map (
            cycles => reset_cycles
        )
        port map (
            i_clk => i_clk,
            i_rst => reset_req,
            o_rst => rst
        );

    u_rst_tx : entity work.synchronizer
        generic map (
            stages     => sync_stages,
            data_width => 1
        )
        port map (
            i_clk  => i_mii_tx_clk,
            i_rst  => '0',
            i_d(0) => rst,
            o_d    => rst_tx_vec
        );

    u_rst_rx : entity work.synchronizer
        generic map (
            stages     => sync_stages,
            data_width => 1
        )
        port map (
            i_clk  => i_mii_rx_clk,
            i_rst  => '0',
            i_d(0) => rst,
            o_d    => rst_rx_vec
        );

    rst_tx <= rst_tx_vec(0);
    rst_rx <= rst_rx_vec(0);

    -----------------------------------------------------------------------------
    -- Registradores
    -----------------------------------------------------------------------------

    u_regs : entity work.eth_regs
        generic map (
            tx_buffer_addr_bits => tx_buffer_addr_bits,
            rx_buffer_addr_bits => rx_buffer_addr_bits
        )
        port map (
            i_clk           => i_clk,
            i_rst           => rst,
            i_write         => i_write,
            i_read          => i_read,
            i_address       => i_address,
            i_data_in       => reg_data_in,
            o_data_out      => reg_data_out,
            o_irq           => o_irq,
            o_enable        => enable,
            o_promiscuous   => promiscuous,
            o_broadcast     => broadcast,
            o_multicast     => multicast,
            o_accept_errors => accept_errors,
            o_phy_reset     => phy_reset,
            o_soft_reset    => soft_reset,
            o_mac_addr      => mac_addr,
            o_tx_ram_we     => tx_ram_we,
            o_tx_ram_addr   => tx_ram_waddr,
            o_tx_ram_data   => tx_ram_wdata,
            o_tx_len        => tx_len,
            o_tx_start      => tx_start_sys,
            i_tx_done       => tx_done_sys,
            i_rx_ready      => rx_ready,
            i_rx_len        => rx_len,
            i_rx_ram_data   => rx_ram_rdata,
            o_rx_ram_addr   => rx_ram_raddr,
            o_rx_release    => rx_release,
            o_mdio_start    => mdio_start,
            o_mdio_write    => mdio_write,
            o_mdio_phy_addr => mdio_phy_addr,
            o_mdio_reg_addr => mdio_reg_addr,
            o_mdio_wdata    => mdio_wdata,
            i_mdio_busy     => mdio_busy,
            i_mdio_done     => mdio_done,
            i_mdio_rdata    => mdio_rdata,
            i_mdio_no_ack   => mdio_no_ack,
            i_phy_int       => phy_int,
            i_ev_frame      => ev_frame,
            i_ev_crc        => ev_crc,
            i_ev_phy        => ev_phy,
            i_ev_dropped    => ev_dropped,
            i_ev_filtered   => ev_filtered
        );

    -----------------------------------------------------------------------------
    -- Envio
    -----------------------------------------------------------------------------

    u_tx_ram : entity work.eth_dpram
        generic map (
            data_width => 32,
            addr_width => tx_buffer_addr_bits
        )
        port map (
            i_wclk  => i_clk,
            i_we    => tx_ram_we,
            i_waddr => tx_ram_waddr,
            i_wdata => tx_ram_wdata,
            i_rclk  => i_mii_tx_clk,
            i_raddr => tx_ram_raddr,
            o_rdata => tx_ram_rdata
        );

    u_tx_start : entity work.eth_pulse_cdc
        generic map (
            sync_stages => sync_stages
        )
        port map (
            i_src_clk => i_clk,
            i_src_rst => rst,
            i_pulse   => tx_start_sys,
            i_dst_clk => i_mii_tx_clk,
            i_dst_rst => rst_tx,
            o_pulse   => tx_start_phy
        );

    u_mac_tx : entity work.eth_mac_tx
        generic map (
            buffer_addr_bits => tx_buffer_addr_bits
        )
        port map (
            i_clk      => i_mii_tx_clk,
            i_rst      => rst_tx,
            i_ce       => i_tx_ce,
            i_wide     => speed_tx(1),
            i_start    => tx_start_phy,
            i_length   => tx_len,
            o_ram_addr => tx_ram_raddr,
            i_ram_data => tx_ram_rdata,
            o_txd      => tx_data8,
            o_tx_en    => o_mii_tx_en,
            o_busy     => tx_busy_phy,
            o_done     => tx_done_phy
        );

    u_tx_done : entity work.eth_pulse_cdc
        generic map (
            sync_stages => sync_stages
        )
        port map (
            i_src_clk => i_mii_tx_clk,
            i_src_rst => rst_tx,
            i_pulse   => tx_done_phy,
            i_dst_clk => i_clk,
            i_dst_rst => rst,
            o_pulse   => tx_done_sys
        );

    o_mii_txd   <= tx_data8(phy_data_width(gigabit) - 1 downto 0);
    o_mii_tx_er <= '0';
    o_tx_speed  <= speed_tx;

    -----------------------------------------------------------------------------
    -- Recepção
    -----------------------------------------------------------------------------

    u_mac_rx : entity work.eth_mac_rx
        port map (
            i_clk     => i_mii_rx_clk,
            i_rst     => rst_rx,
            i_wide    => wide_rx_vec(0),
            i_rxd     => rx_data8,
            i_rx_dv   => i_mii_rx_dv,
            i_rx_er   => i_mii_rx_er,
            o_wr_en   => fifo_wr_en,
            o_wr_data => fifo_wr_data,
            i_full    => fifo_full,
            i_full_next => fifo_full_next
        );

    u_rx_fifo : entity work.eth_async_fifo
        generic map (
            data_width  => 9,
            addr_bits   => rx_fifo_addr_bits,
            sync_stages => sync_stages
        )
        port map (
            i_wclk  => i_mii_rx_clk,
            i_wrst  => rst_rx,
            i_wr_en => fifo_wr_en,
            i_wdata => fifo_wr_data,
            o_full  => fifo_full,
            o_full_next => fifo_full_next,
            i_rclk  => i_clk,
            i_rrst  => rst,
            i_rd_en => fifo_rd_en,
            o_rdata => fifo_rd_data,
            o_empty => fifo_empty
        );

    u_rx_store : entity work.eth_rx_store
        generic map (
            buffer_addr_bits => rx_buffer_addr_bits
        )
        port map (
            i_clk           => i_clk,
            i_rst           => rst,
            i_empty         => fifo_empty,
            i_word          => fifo_rd_data,
            o_rd_en         => fifo_rd_en,
            i_mac_addr      => mac_addr,
            i_enable        => enable,
            i_promiscuous   => promiscuous,
            i_broadcast     => broadcast,
            i_multicast     => multicast,
            i_accept_errors => accept_errors,
            i_release       => rx_release,
            o_ram_we        => rx_ram_we,
            o_ram_addr      => rx_ram_waddr,
            o_ram_data      => rx_ram_wdata,
            o_frame_ready   => rx_ready,
            o_frame_len     => rx_len,
            o_ev_frame      => ev_frame,
            o_ev_crc        => ev_crc,
            o_ev_phy        => ev_phy,
            o_ev_dropped    => ev_dropped,
            o_ev_filtered   => ev_filtered
        );

    u_rx_ram : entity work.eth_dpram
        generic map (
            data_width => 32,
            addr_width => rx_buffer_addr_bits
        )
        port map (
            i_wclk  => i_clk,
            i_we    => rx_ram_we,
            i_waddr => rx_ram_waddr,
            i_wdata => rx_ram_wdata,
            i_rclk  => i_clk,
            i_raddr => rx_ram_raddr,
            o_rdata => rx_ram_rdata
        );

    -----------------------------------------------------------------------------
    -- Velocidade e largura dos dados
    -----------------------------------------------------------------------------

    rx_data8 <= std_logic_vector(resize(unsigned(i_mii_rxd), rx_data8'length));

    g_speed : if gigabit generate

        u_speed : entity work.eth_speed
            generic map (
                phy_addr    => phy_addr,
                poll_cycles => poll_cycles
            )
            port map (
                i_clk           => i_clk,
                i_rst           => rst,
                i_write         => i_write,
                i_address       => i_address,
                i_data_in       => reg_data_in,
                o_data_out      => speed_word,
                i_sw_start      => mdio_start,
                i_mdio_busy     => m_busy,
                i_mdio_done     => m_done,
                i_mdio_no_ack   => m_no_ack,
                i_mdio_rdata    => mdio_rdata,
                o_mdio_start    => poll_start,
                o_mdio_phy_addr => poll_phy_addr,
                o_mdio_reg_addr => poll_reg_addr,
                o_mdio_hold     => poll_hold,
                o_speed         => speed_sys
            );

        u_speed_tx : entity work.synchronizer
            generic map (
                stages     => sync_stages,
                data_width => 2
            )
            port map (
                i_clk => i_mii_tx_clk,
                i_rst => '0',
                i_d   => speed_sys,
                o_d   => speed_tx
            );

        u_wide_rx : entity work.synchronizer
            generic map (
                stages     => sync_stages,
                data_width => 1
            )
            port map (
                i_clk  => i_mii_rx_clk,
                i_rst  => '0',
                i_d(0) => speed_sys(1),
                o_d    => wide_rx_vec
            );

        -- O programa vê o mestre ocupado durante a consulta, e só os seus resultados.
        m_start    <= mdio_start or poll_start;
        m_write    <= mdio_write and not poll_start;
        m_phy_addr <= poll_phy_addr when poll_start = '1' else mdio_phy_addr;
        m_reg_addr <= poll_reg_addr when poll_start = '1' else mdio_reg_addr;
        mdio_busy  <= m_busy or poll_hold;
        mdio_done  <= m_done and not poll_hold;
        mdio_no_ack <= sw_no_ack;

        p_no_ack : process (i_clk) is
        begin

            if rising_edge(i_clk) then
                if rst = '1' then
                    sw_no_ack <= '0';
                elsif m_done = '1' and poll_hold = '0' then
                    sw_no_ack <= m_no_ack;
                end if;
            end if;

        end process p_no_ack;

    else generate

        -- Sem o modo gigabit o PHY fixa a velocidade e os dados têm nibbles.
        speed_word    <= (others => '0');
        speed_sys     <= SPEED_100;
        speed_tx      <= SPEED_100;
        wide_rx_vec   <= "0";
        poll_start    <= '0';
        poll_phy_addr <= (others => '0');
        poll_reg_addr <= (others => '0');
        poll_hold     <= '0';
        m_start       <= mdio_start;
        m_write       <= mdio_write;
        m_phy_addr    <= mdio_phy_addr;
        m_reg_addr    <= mdio_reg_addr;
        mdio_busy     <= m_busy;
        mdio_done     <= m_done;
        mdio_no_ack   <= m_no_ack;

    end generate g_speed;

    -----------------------------------------------------------------------------
    -- MDIO e pinos de gerenciamento do PHY
    -----------------------------------------------------------------------------

    u_mdio : entity work.eth_mdio
        generic map (
            clk_freq_hz => clk_freq_hz,
            mdc_freq_hz => mdc_freq_hz
        )
        port map (
            i_clk      => i_clk,
            i_rst      => rst,
            i_start    => m_start,
            i_write    => m_write,
            i_phy_addr => m_phy_addr,
            i_reg_addr => m_reg_addr,
            i_wdata    => mdio_wdata,
            o_rdata    => mdio_rdata,
            o_busy     => m_busy,
            o_done     => m_done,
            o_no_ack   => m_no_ack,
            o_mdc      => o_mdc,
            i_mdio     => i_mdio,
            o_mdio_out => o_mdio_out,
            o_mdio_oe  => o_mdio_oe
        );

    u_phy_int : entity work.synchronizer
        generic map (
            stages     => sync_stages,
            data_width => 1
        )
        port map (
            i_clk  => i_clk,
            i_rst  => '0',
            i_d(0) => i_phy_int_n,
            o_d    => phy_int_sync
        );

    phy_int <= not phy_int_sync(0);

    p_phy_rst : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            phy_rst_n_reg <= not phy_reset;
        end if;

    end process p_phy_rst;

    o_phy_rst_n <= phy_rst_n_reg;

end architecture rtl;

-- =============================================================================
-- Registradores do MAC Ethernet (domínio do sistema)
--
-- Decodifica o barramento do núcleo e guarda controle, filtro, comprimento do
-- quadro a enviar, ponteiros das portas de dados dos dois buffers, comando do
-- mestre MDIO, contadores e interrupções. Não conhece os clocks do PHY: fala
-- com o transmissor e com o receptor só por pulsos e níveis do domínio do
-- sistema. A leitura é combinacional no endereço; ler RX_DATA consome uma
-- palavra do buffer de recepção, e escrever TX_DATA acrescenta uma palavra ao
-- buffer de envio. Escrever em qualquer contador zera esse contador.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.eth_consts.all;

entity eth_regs is
    generic (
        -- Largura do endereço de palavra do buffer de envio.
        tx_buffer_addr_bits : positive := 9;
        -- Largura do endereço de palavra do buffer de recepção.
        rx_buffer_addr_bits : positive := 9
    );
    port (
        -- Clock do sistema.
        i_clk            : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst            : in    std_logic;
        -- Pulso de escrita do núcleo.
        i_write          : in    std_logic;
        -- Pulso de leitura do núcleo.
        i_read           : in    std_logic;
        -- Endereço de palavra.
        i_address        : in    std_logic_vector(ETH_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita.
        i_data_in        : in    std_logic_vector(31 downto 0);
        -- Dado de leitura, combinacional no endereço.
        o_data_out       : out   std_logic_vector(31 downto 0);
        -- Interrupção, ativa em '1'.
        o_irq            : out   std_logic;

        -- MAC habilitado.
        o_enable         : out   std_logic;
        -- Filtro promíscuo.
        o_promiscuous    : out   std_logic;
        -- Filtro aceita difusão.
        o_broadcast      : out   std_logic;
        -- Filtro aceita grupo.
        o_multicast      : out   std_logic;
        -- Entrega quadros com erro.
        o_accept_errors  : out   std_logic;
        -- Mantém o PHY em reset.
        o_phy_reset      : out   std_logic;
        -- Pedido de reset do MAC, pulso de um ciclo.
        o_soft_reset     : out   std_logic;
        -- Endereço MAC próprio.
        o_mac_addr       : out   std_logic_vector(47 downto 0);

        -- Escrita no buffer de envio.
        o_tx_ram_we      : out   std_logic;
        -- Endereço de palavra da escrita no buffer de envio.
        o_tx_ram_addr    : out   std_logic_vector(tx_buffer_addr_bits - 1 downto 0);
        -- Palavra escrita no buffer de envio.
        o_tx_ram_data    : out   std_logic_vector(31 downto 0);
        -- Comprimento do quadro a enviar.
        o_tx_len         : out   std_logic_vector(tx_buffer_addr_bits + 2 downto 0);
        -- Inicia o envio, pulso de um ciclo.
        o_tx_start       : out   std_logic;
        -- O transmissor terminou o quadro, pulso de um ciclo.
        i_tx_done        : in    std_logic;

        -- Há quadro pronto no buffer de recepção.
        i_rx_ready       : in    std_logic;
        -- Comprimento do quadro pronto.
        i_rx_len         : in    std_logic_vector(rx_buffer_addr_bits + 2 downto 0);
        -- Palavra lida do buffer de recepção, um ciclo depois do endereço.
        i_rx_ram_data    : in    std_logic_vector(31 downto 0);
        -- Endereço de leitura do buffer de recepção.
        o_rx_ram_addr    : out   std_logic_vector(rx_buffer_addr_bits - 1 downto 0);
        -- Libera o quadro pronto, pulso de um ciclo.
        o_rx_release     : out   std_logic;

        -- Inicia uma transação MDIO, pulso de um ciclo.
        o_mdio_start     : out   std_logic;
        -- Transação de escrita.
        o_mdio_write     : out   std_logic;
        -- Endereço do PHY.
        o_mdio_phy_addr  : out   std_logic_vector(4 downto 0);
        -- Endereço do registrador do PHY.
        o_mdio_reg_addr  : out   std_logic_vector(4 downto 0);
        -- Dado a escrever no PHY.
        o_mdio_wdata     : out   std_logic_vector(15 downto 0);
        -- Mestre MDIO ocupado.
        i_mdio_busy      : in    std_logic;
        -- Transação MDIO concluída, pulso de um ciclo.
        i_mdio_done      : in    std_logic;
        -- Dado lido do PHY.
        i_mdio_rdata     : in    std_logic_vector(15 downto 0);
        -- O PHY não respondeu.
        i_mdio_no_ack    : in    std_logic;

        -- Nível da interrupção do PHY, ativo em '1'.
        i_phy_int        : in    std_logic;
        -- Evento: quadro entregue ao buffer.
        i_ev_frame       : in    std_logic;
        -- Evento: erro de CRC.
        i_ev_crc         : in    std_logic;
        -- Evento: erro de PHY, alinhamento ou quadro curto.
        i_ev_phy         : in    std_logic;
        -- Evento: quadro descartado.
        i_ev_dropped     : in    std_logic;
        -- Evento: quadro recusado pelo filtro.
        i_ev_filtered    : in    std_logic
    );
end entity eth_regs;

architecture rtl of eth_regs is

    -- Palavras que o buffer de envio comporta.
    constant TX_WORDS : natural := 2 ** tx_buffer_addr_bits;

    -- Registrador de controle.
    signal ctrl         : std_logic_vector(6 downto 0) := "0000100";
    -- Interrupções memorizadas (bits 0 a 3 de IRQ_STATUS).
    signal irq_pending  : std_logic_vector(3 downto 0) := (others => '0');
    -- Habilitação das interrupções.
    signal irq_enable   : std_logic_vector(4 downto 0) := (others => '0');
    -- Endereço MAC próprio.
    signal mac_addr     : std_logic_vector(47 downto 0) := (others => '0');
    -- Comprimento do quadro a enviar.
    signal tx_len       : unsigned(tx_buffer_addr_bits + 2 downto 0) := (others => '0');
    -- Ponteiro de escrita do buffer de envio, em palavras.
    signal tx_ptr       : unsigned(tx_buffer_addr_bits downto 0) := (others => '0');
    -- Envio em andamento.
    signal tx_busy      : std_logic := '0';
    -- Ponteiro de leitura do buffer de recepção, em palavras.
    signal rx_ptr       : unsigned(rx_buffer_addr_bits - 1 downto 0) := (others => '0');
    -- Ponteiro de leitura depois da leitura deste ciclo.
    signal rx_ptr_next  : unsigned(rx_buffer_addr_bits - 1 downto 0);
    -- Comando MDIO guardado: endereço do registrador.
    signal mdio_reg     : std_logic_vector(4 downto 0) := (others => '0');
    -- Comando MDIO guardado: endereço do PHY.
    signal mdio_phy     : std_logic_vector(4 downto 0) := (others => '0');
    -- Comando MDIO guardado: operação de escrita.
    signal mdio_write   : std_logic := '0';
    -- Dado MDIO, a escrever ou o último lido.
    signal mdio_data    : std_logic_vector(15 downto 0) := (others => '0');
    -- Contador de quadros enviados.
    signal cnt_tx       : unsigned(31 downto 0) := (others => '0');
    -- Contador de quadros recebidos.
    signal cnt_rx       : unsigned(31 downto 0) := (others => '0');
    -- Contador de erros de CRC.
    signal cnt_crc      : unsigned(31 downto 0) := (others => '0');
    -- Contador de erros de PHY.
    signal cnt_phy      : unsigned(31 downto 0) := (others => '0');
    -- Contador de quadros descartados.
    signal cnt_drop     : unsigned(31 downto 0) := (others => '0');
    -- Contador de quadros filtrados.
    signal cnt_filter   : unsigned(31 downto 0) := (others => '0');

    -- Escrita em cada registrador, decodificada do endereço.
    signal wr_ctrl      : std_logic;
    -- Escrita em IRQ_STATUS.
    signal wr_irq       : std_logic;
    -- Escrita em IRQ_ENABLE.
    signal wr_irq_en    : std_logic;
    -- Escrita em MAC_LO.
    signal wr_mac_lo    : std_logic;
    -- Escrita em MAC_HI.
    signal wr_mac_hi    : std_logic;
    -- Escrita em TX_LEN.
    signal wr_tx_len    : std_logic;
    -- Escrita em TX_CMD.
    signal wr_tx_cmd    : std_logic;
    -- Escrita em TX_DATA.
    signal wr_tx_data   : std_logic;
    -- Escrita em RX_CMD.
    signal wr_rx_cmd    : std_logic;
    -- Escrita em MDIO_CMD.
    signal wr_mdio_cmd  : std_logic;
    -- Escrita em MDIO_DATA.
    signal wr_mdio_data : std_logic;
    -- Escrita em cada contador, que o zera.
    signal clr_tx       : std_logic;
    -- Escrita em CNT_RX, que o zera.
    signal clr_rx       : std_logic;
    -- Escrita em CNT_CRC, que o zera.
    signal clr_crc      : std_logic;
    -- Escrita em CNT_PHY, que o zera.
    signal clr_phy      : std_logic;
    -- Escrita em CNT_DROP, que o zera.
    signal clr_drop     : std_logic;
    -- Escrita em CNT_FILTER, que o zera.
    signal clr_filter   : std_logic;

    -- Leitura de RX_DATA que consome uma palavra.
    signal rx_pop       : std_logic;
    -- Pedido de início de envio aceito.
    signal tx_go        : std_logic;
    -- Pedido de início de envio recusado ou escrita recusada no buffer de envio.
    signal tx_error     : std_logic;
    -- Pedido de início de transação MDIO aceito.
    signal mdio_go      : std_logic;
    -- Evento de erro que aciona a interrupção de erro.
    signal err_event    : std_logic;
    -- O comando de recepção pede ponteiro de volta a zero.
    signal rx_rewind    : std_logic;
    -- Pedido de reset do MAC registrado.
    signal soft_reset   : std_logic := '0';
    -- Início de envio registrado.
    signal tx_start_reg : std_logic := '0';
    -- Liberação do quadro registrada.
    signal rx_release_reg : std_logic := '0';
    -- Início de MDIO registrado.
    signal mdio_start_reg : std_logic := '0';
    -- Escrita registrada no buffer de envio.
    signal tx_we_reg    : std_logic := '0';
    -- Endereço registrado da escrita no buffer de envio.
    signal tx_addr_reg  : std_logic_vector(tx_buffer_addr_bits - 1 downto 0) := (others => '0');
    -- Palavra registrada da escrita no buffer de envio.
    signal tx_data_reg  : std_logic_vector(31 downto 0) := (others => '0');
    -- Palavra de STATUS.
    signal status       : std_logic_vector(31 downto 0);
    -- Palavra de IRQ_STATUS.
    signal irq_word     : std_logic_vector(31 downto 0);
    -- Uma transação MDIO de leitura está em curso.
    signal mdio_is_read : std_logic := '0';

    -- Converte booleano em std_logic.
    function to_sl (
        value : boolean
    ) return std_logic is
    begin
        if value then
            return '1';
        end if;
        return '0';
    end function to_sl;

    -- Soma um ao contador se houve evento e zera se o contador foi escrito.
    function bump (
        value : unsigned(31 downto 0);
        event : std_logic;
        clear : std_logic
    ) return unsigned is
    begin
        if clear = '1' then
            return to_unsigned(0, 32);
        elsif event = '1' then
            return value + 1;
        end if;
        return value;
    end function bump;

begin

    wr_ctrl      <= i_write when i_address = ADDR_CTRL else '0';
    wr_irq       <= i_write when i_address = ADDR_IRQ_STATUS else '0';
    wr_irq_en    <= i_write when i_address = ADDR_IRQ_ENABLE else '0';
    wr_mac_lo    <= i_write when i_address = ADDR_MAC_LO else '0';
    wr_mac_hi    <= i_write when i_address = ADDR_MAC_HI else '0';
    wr_tx_len    <= i_write when i_address = ADDR_TX_LEN else '0';
    wr_tx_cmd    <= i_write when i_address = ADDR_TX_CMD else '0';
    wr_tx_data   <= i_write when i_address = ADDR_TX_DATA else '0';
    wr_rx_cmd    <= i_write when i_address = ADDR_RX_CMD else '0';
    wr_mdio_cmd  <= i_write when i_address = ADDR_MDIO_CMD else '0';
    wr_mdio_data <= i_write when i_address = ADDR_MDIO_DATA else '0';
    clr_tx       <= i_write when i_address = ADDR_CNT_TX else '0';
    clr_rx       <= i_write when i_address = ADDR_CNT_RX else '0';
    clr_crc      <= i_write when i_address = ADDR_CNT_CRC else '0';
    clr_phy      <= i_write when i_address = ADDR_CNT_PHY else '0';
    clr_drop     <= i_write when i_address = ADDR_CNT_DROP else '0';
    clr_filter   <= i_write when i_address = ADDR_CNT_FILTER else '0';

    rx_pop <= i_read when i_address = ADDR_RX_DATA and i_rx_ready = '1' else '0';

    -- O envio exige transmissor livre e comprimento de 1 byte até o tamanho do buffer.
    tx_go    <= wr_tx_cmd and i_data_in(0) and not tx_busy and to_sl(tx_len /= 0);
    tx_error <= (wr_tx_cmd and i_data_in(0) and tx_busy)
                or (wr_tx_cmd and i_data_in(0) and to_sl(tx_len = 0))
                or (wr_tx_data and to_sl(tx_ptr = TX_WORDS));
    mdio_go  <= wr_mdio_cmd and not i_mdio_busy;

    err_event <= i_ev_crc or i_ev_phy or i_ev_dropped or tx_error;

    rx_rewind   <= wr_rx_cmd and (i_data_in(0) or i_data_in(1));
    rx_ptr_next <= (others => '0') when rx_rewind = '1' else
                   rx_ptr + 1 when rx_pop = '1' else
                   rx_ptr;

    p_regs : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            soft_reset     <= '0';
            tx_start_reg   <= '0';
            rx_release_reg <= '0';
            mdio_start_reg <= '0';
            tx_we_reg      <= '0';

            if i_rst = '1' then
                ctrl         <= "0000100";
                irq_pending  <= (others => '0');
                irq_enable   <= (others => '0');
                mac_addr     <= (others => '0');
                tx_len       <= (others => '0');
                tx_ptr       <= (others => '0');
                tx_busy      <= '0';
                rx_ptr       <= (others => '0');
                mdio_reg     <= (others => '0');
                mdio_phy     <= (others => '0');
                mdio_write   <= '0';
                mdio_data    <= (others => '0');
                mdio_is_read <= '0';
                cnt_tx       <= (others => '0');
                cnt_rx       <= (others => '0');
                cnt_crc      <= (others => '0');
                cnt_phy      <= (others => '0');
                cnt_drop     <= (others => '0');
                cnt_filter   <= (others => '0');
            else
                if wr_ctrl = '1' then
                    ctrl       <= i_data_in(6 downto 0);
                    soft_reset <= i_data_in(CTRL_SOFT_RESET);
                end if;
                if wr_irq_en = '1' then
                    irq_enable <= i_data_in(4 downto 0);
                end if;
                if wr_mac_lo = '1' then
                    mac_addr(31 downto 0) <= i_data_in;
                end if;
                if wr_mac_hi = '1' then
                    mac_addr(47 downto 32) <= i_data_in(15 downto 0);
                end if;
                if wr_tx_len = '1' and tx_busy = '0' then
                    tx_len <= unsigned(i_data_in(tx_buffer_addr_bits + 2 downto 0));
                end if;

                -- Buffer de envio: uma palavra por escrita, ponteiro com autoincremento.
                if wr_tx_data = '1' and tx_busy = '0' and tx_ptr < TX_WORDS then
                    tx_we_reg   <= '1';
                    tx_addr_reg <= std_logic_vector(tx_ptr(tx_buffer_addr_bits - 1 downto 0));
                    tx_data_reg <= i_data_in;
                    tx_ptr      <= tx_ptr + 1;
                end if;
                if wr_tx_cmd = '1' and i_data_in(1) = '1' and tx_busy = '0' then
                    tx_ptr <= (others => '0');
                end if;
                if tx_go = '1' then
                    tx_busy      <= '1';
                    tx_start_reg <= '1';
                end if;
                if i_tx_done = '1' then
                    tx_busy <= '0';
                    tx_ptr  <= (others => '0');
                end if;

                -- Buffer de recepção.
                rx_ptr <= rx_ptr_next;
                if wr_rx_cmd = '1' and i_data_in(0) = '1' then
                    rx_release_reg <= '1';
                end if;

                -- MDIO: a leitura concluída deixa o dado em MDIO_DATA.
                if wr_mdio_data = '1' and i_mdio_busy = '0' then
                    mdio_data <= i_data_in(15 downto 0);
                end if;
                if mdio_go = '1' then
                    mdio_reg       <= i_data_in(4 downto 0);
                    mdio_phy       <= i_data_in(9 downto 5);
                    mdio_write     <= i_data_in(10);
                    mdio_is_read   <= not i_data_in(10);
                    mdio_start_reg <= '1';
                end if;
                if i_mdio_done = '1' and mdio_is_read = '1' then
                    mdio_data <= i_mdio_rdata;
                end if;

                -- Interrupções memorizadas: o evento tem prioridade sobre a limpeza.
                for k in 0 to 3 loop
                    if wr_irq = '1' and i_data_in(k) = '1' then
                        irq_pending(k) <= '0';
                    end if;
                end loop;
                if i_ev_frame = '1' then
                    irq_pending(IRQ_RX_FRAME) <= '1';
                end if;
                if i_tx_done = '1' then
                    irq_pending(IRQ_TX_DONE) <= '1';
                end if;
                if err_event = '1' then
                    irq_pending(IRQ_ERROR) <= '1';
                end if;
                if i_mdio_done = '1' then
                    irq_pending(IRQ_MDIO_DONE) <= '1';
                end if;

                cnt_tx     <= bump(cnt_tx, i_tx_done, clr_tx);
                cnt_rx     <= bump(cnt_rx, i_ev_frame, clr_rx);
                cnt_crc    <= bump(cnt_crc, i_ev_crc, clr_crc);
                cnt_phy    <= bump(cnt_phy, i_ev_phy, clr_phy);
                cnt_drop   <= bump(cnt_drop, i_ev_dropped, clr_drop);
                cnt_filter <= bump(cnt_filter, i_ev_filtered, clr_filter);
            end if;
        end if;

    end process p_regs;

    status <= (STATUS_TX_BUSY    => tx_busy,
               STATUS_RX_READY   => i_rx_ready,
               STATUS_MDIO_BUSY  => i_mdio_busy,
               STATUS_PHY_INT    => i_phy_int,
               STATUS_MDIO_NOACK => i_mdio_no_ack,
               others            => '0');

    irq_word <= (31 downto 5 => '0') & i_phy_int & irq_pending;

    with i_address select o_data_out <=
        (31 downto 7 => '0') & ctrl                                                     when ADDR_CTRL,
        status                                                                          when ADDR_STATUS,
        irq_word                                                                        when ADDR_IRQ_STATUS,
        (31 downto 5 => '0') & irq_enable                                               when ADDR_IRQ_ENABLE,
        mac_addr(31 downto 0)                                                           when ADDR_MAC_LO,
        (31 downto 16 => '0') & mac_addr(47 downto 32)                                  when ADDR_MAC_HI,
        std_logic_vector(resize(tx_len, 32))                                            when ADDR_TX_LEN,
        std_logic_vector(resize(tx_ptr, 32))                                            when ADDR_TX_DATA,
        std_logic_vector(resize(unsigned(i_rx_len), 32))                                when ADDR_RX_LEN,
        i_rx_ram_data                                                                   when ADDR_RX_DATA,
        (31 downto 11 => '0') & mdio_write & mdio_phy & mdio_reg                        when ADDR_MDIO_CMD,
        (31 downto 16 => '0') & mdio_data                                               when ADDR_MDIO_DATA,
        std_logic_vector(cnt_tx)                                                        when ADDR_CNT_TX,
        std_logic_vector(cnt_rx)                                                        when ADDR_CNT_RX,
        std_logic_vector(cnt_crc)                                                       when ADDR_CNT_CRC,
        std_logic_vector(cnt_phy)                                                       when ADDR_CNT_PHY,
        std_logic_vector(cnt_drop)                                                      when ADDR_CNT_DROP,
        std_logic_vector(cnt_filter)                                                    when ADDR_CNT_FILTER,
        (31 downto 0 => '0')                                                            when others;

    o_irq <= '1' when ((irq_pending & i_phy_int) and (irq_enable(3 downto 0) & irq_enable(4))) /= "00000" else '0';

    o_enable        <= ctrl(CTRL_ENABLE);
    o_promiscuous   <= ctrl(CTRL_PROMISCUOUS);
    o_broadcast     <= ctrl(CTRL_BROADCAST);
    o_multicast     <= ctrl(CTRL_MULTICAST);
    o_accept_errors <= ctrl(CTRL_ACCEPT_ERRORS);
    o_phy_reset     <= ctrl(CTRL_PHY_RESET);
    o_soft_reset    <= soft_reset;
    o_mac_addr      <= mac_addr;

    o_tx_ram_we     <= tx_we_reg;
    o_tx_ram_addr   <= tx_addr_reg;
    o_tx_ram_data   <= tx_data_reg;
    o_tx_len        <= std_logic_vector(tx_len);
    o_tx_start      <= tx_start_reg;

    o_rx_ram_addr   <= std_logic_vector(rx_ptr_next);
    o_rx_release    <= rx_release_reg;

    o_mdio_start    <= mdio_start_reg;
    o_mdio_write    <= mdio_write;
    o_mdio_phy_addr <= mdio_phy;
    o_mdio_reg_addr <= mdio_reg;
    o_mdio_wdata    <= mdio_data;

end architecture rtl;

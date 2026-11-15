-- =============================================================================
-- Ponte do módulo Wi-Fi NINA (u-blox NINA-W10, ESP32) para o processador
--
-- Reúne, numa só janela de registradores, tudo o que o FPGA liga ao módulo:
-- o bloco de controle (reset, seleção de boot e a entrada ACK), o mestre SPI
-- que fala com o firmware de co-processador Wi-Fi do módulo e a UART que fala
-- com o firmware de comandos AT ou com o carregador de firmware. O módulo roda
-- só um dos dois firmwares por vez, então o software usa o SPI ou a UART, e o
-- periférico oferece os dois com os pinos que a placa liga a cada um. Cada
-- parte é uma instância de uma entidade que já existe (o mestre SPI e a UART
-- do repositório), de modo que este topo só decodifica o endereço, escolhe o
-- dado de leitura e soma as interrupções.
--
-- Mapa de endereços de palavra (i_address de 5 bits, ver wifi_consts):
--   - 0x00 a 0x02, bloco de controle (CTRL, STATUS, RESET_PULSE);
--   - 0x08 a 0x0D, mestre SPI (TX_DATA, RX_DATA, STATUS, CONTROL, DIVIDER,
--     TX_LISTEN);
--   - 0x10 a 0x13, UART (TX_DATA, RX_DATA, STATUS, CONTROL).
-- Os demais endereços leem zero e ignoram a escrita. O pino de seleção do
-- módulo no SPI é o o_wm_cs_n da instância do mestre SPI, ativo em baixo.
-- A interrupção é o OU das interrupções dos três blocos.
--
-- O periférico não faz a ponte de passagem do módulo para o microcontrolador
-- SAMD21 da placa, que a plataforma fecha por fora quando precisa dela.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;
use work.wifi_consts.all;

entity wifi is
    generic (
        -- Frequência do clock do sistema em hertz.
        clock_hz           : positive := 50_000_000;
        -- Duração do pulso de reset do módulo em milissegundos.
        reset_pulse_ms     : positive := 10;
        -- Módulo fora de reset logo depois do reset do sistema.
        run_at_reset       : boolean  := false;
        -- Frequência de SCLK do SPI no reset, em hertz.
        spi_reset_sclk_hz  : positive := 1_000_000;
        -- Palavras da fila de recepção do SPI.
        spi_rx_fifo_depth  : positive := 16;
        -- Palavras da fila de transmissão do SPI.
        spi_tx_fifo_depth  : positive := 16;
        -- Constante de frequência do gerador de baud da UART (OpenCores).
        uart_baud_freq     : natural  := 16#240#;
        -- Constante de limite do gerador de baud da UART (OpenCores).
        uart_baud_limit    : natural  := 16#3AC9#;
        -- Bytes da fila de recepção da UART.
        uart_rx_fifo_depth : positive := 16;
        -- Bytes da fila de transmissão da UART.
        uart_tx_fifo_depth : positive := 16;
        -- Inclui o controle de fluxo RTS e CTS na UART.
        has_flow_control   : boolean  := false
    );
    port (
        -- Clock do sistema.
        i_clk         : in    std_logic;
        -- Reset síncrono, ativo em '1'.
        i_rst         : in    std_logic;
        -- Pulso de escrita do processador.
        i_write       : in    std_logic;
        -- Pulso de leitura do processador.
        i_read        : in    std_logic;
        -- Endereço de palavra dentro do periférico.
        i_address     : in    std_logic_vector(WIFI_ADDR_WIDTH - 1 downto 0);
        -- Dado de escrita vindo do processador.
        i_data_in     : in    word_t;
        -- Dado de leitura para o processador.
        o_data_out    : out   word_t;
        -- Requisição de interrupção de nível, ativa em '1'.
        o_irq         : out   std_logic;
        -- Reset do módulo, ativo em '0'.
        o_wm_reset_n  : out   std_logic;
        -- Valor do pino GPIO0 do módulo, sempre em baixo, válido com a habilitação.
        o_wm_gpio0    : out   std_logic;
        -- Habilitação do driver de GPIO0.
        o_wm_gpio0_oe : out   std_logic;
        -- Pino ACK do módulo, assíncrono.
        i_wm_ack      : in    std_logic;
        -- Relógio do SPI para o módulo.
        o_wm_sck      : out   std_logic;
        -- Dado do SPI do mestre para o módulo (COPI).
        o_wm_copi     : out   std_logic;
        -- Dado do SPI do módulo para o mestre (CIPO).
        i_wm_cipo     : in    std_logic;
        -- Seleção do módulo no SPI, ativa em '0'.
        o_wm_cs_n     : out   std_logic;
        -- Linha serial que sai do módulo (TX do módulo, RX da UART do FPGA).
        i_wm_tx       : in    std_logic;
        -- Linha serial que entra no módulo (RX do módulo, TX da UART do FPGA).
        o_wm_rx       : out   std_logic;
        -- RTS do módulo, ativo em '0', lido como CTS da UART do FPGA.
        i_wm_rts      : in    std_logic;
        -- CTS do módulo, ativo em '0', escrito como RTS da UART do FPGA.
        o_wm_cts      : out   std_logic
    );
end entity wifi;

architecture rtl of wifi is

    -- Seletor de bloco do endereço.
    signal block_sel  : std_logic_vector(1 downto 0);
    -- Endereço de palavra dentro do bloco.
    signal block_addr : std_logic_vector(2 downto 0);
    -- Acesso ao bloco de controle.
    signal sel_ctrl   : std_logic;
    -- Acesso ao mestre SPI, dentro do mapa.
    signal sel_spi    : std_logic;
    -- Acesso à UART, dentro do mapa.
    signal sel_uart   : std_logic;

    -- Dado de leitura do bloco de controle.
    signal ctrl_data  : word_t;
    -- Dado de leitura do mestre SPI.
    signal spi_data   : word_t;
    -- Dado de leitura da UART.
    signal uart_data  : word_t;
    -- Interrupção do bloco de controle.
    signal ctrl_irq   : std_logic;
    -- Interrupção do mestre SPI.
    signal spi_irq    : std_logic;
    -- Interrupção da UART.
    signal uart_irq   : std_logic;
    -- Seleção de chip do SPI.
    signal spi_cs_n   : std_logic_vector(0 downto 0);

begin

    block_sel  <= i_address(4 downto 3);
    block_addr <= i_address(2 downto 0);
    sel_ctrl   <= '1' when block_sel = BLOCK_CONTROL and unsigned(block_addr) <= 2 else
                  '0';
    sel_spi    <= '1' when block_sel = BLOCK_SPI and unsigned(block_addr) <= SPI_LAST_ADDRESS else
                  '0';
    sel_uart   <= '1' when block_sel = BLOCK_UART and unsigned(block_addr) <= UART_LAST_ADDRESS else
                  '0';

    o_data_out <= ctrl_data when sel_ctrl = '1' else
                  spi_data when sel_spi = '1' else
                  uart_data when sel_uart = '1' else
                  (others => '0');
    o_irq      <= ctrl_irq or spi_irq or uart_irq;
    o_wm_cs_n  <= spi_cs_n(0);

    u_ctrl : entity work.wifi_regs
        generic map (
            reset_pulse_cycles => clock_hz / 1000 * reset_pulse_ms,
            run_at_reset       => run_at_reset
        )
        port map (
            i_clk         => i_clk,
            i_rst         => i_rst,
            i_write       => i_write and sel_ctrl,
            i_address     => block_addr,
            i_data_in     => i_data_in,
            o_data_out    => ctrl_data,
            o_irq         => ctrl_irq,
            i_wm_ack      => i_wm_ack,
            o_wm_reset_n  => o_wm_reset_n,
            o_wm_gpio0    => o_wm_gpio0,
            o_wm_gpio0_oe => o_wm_gpio0_oe
        );

    u_spi : entity work.spi
        generic map (
            clock_hz      => clock_hz,
            reset_sclk_hz => spi_reset_sclk_hz,
            word_width    => 32,
            cs_count      => 1,
            rx_fifo_depth => spi_rx_fifo_depth,
            tx_fifo_depth => spi_tx_fifo_depth
        )
        port map (
            i_clk      => i_clk,
            i_rst      => i_rst,
            i_data_in  => i_data_in,
            i_address  => block_addr,
            i_write    => i_write and sel_spi,
            i_read     => i_read and sel_spi,
            o_data_out => spi_data,
            o_irq      => spi_irq,
            o_sclk     => o_wm_sck,
            o_mosi     => o_wm_copi,
            o_mosi_oe  => open,
            i_miso     => i_wm_cipo,
            o_cs_n     => spi_cs_n
        );

    u_uart : entity work.uart
        generic map (
            data_width       => XLEN,
            baud_freq        => uart_baud_freq,
            baud_limit       => uart_baud_limit,
            rx_fifo_depth    => uart_rx_fifo_depth,
            tx_fifo_depth    => uart_tx_fifo_depth,
            has_flow_control => has_flow_control
        )
        port map (
            i_clk      => i_clk,
            i_rst      => i_rst,
            i_data_in  => i_data_in,
            i_address  => block_addr(1 downto 0),
            i_write    => i_write and sel_uart,
            i_read     => i_read and sel_uart,
            o_data_out => uart_data,
            o_irq      => uart_irq,
            i_uart_rx  => i_wm_tx,
            o_uart_tx  => o_wm_rx,
            i_uart_cts => i_wm_rts,
            o_uart_rts => o_wm_cts
        );

end architecture rtl;

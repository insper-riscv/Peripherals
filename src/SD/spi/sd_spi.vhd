-- ==========================================================================
-- Controlador de cartão SD no modo SPI mapeado em memória
-- ==========================================================================
-- Liga o mestre SPI de um byte a duas filas síncronas (transmissão e
-- recepção) e aos registradores do barramento. O software enfileira bytes em
-- TX_DATA, cada byte transmitido gera um byte recebido na fila de recepção, e
-- a linha de seleção de chip é controlada pelo registrador CONTROL. Não há
-- pino de detecção de cartão nas placas DE0-CV e DE2-115, então a presença do
-- cartão é detectada pela resposta ao CMD0.
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 TX_DATA  W      bits 7:0, byte enfileirado para transmissão
--   1 RX_DATA  R      bits 7:0, byte mais antigo, removido pela leitura
--   2 STATUS   R/W1C  bits 0 RX_VALID, 1 TX_READY, 2 TX_EMPTY, 3 BUSY,
--                     4 RX_FULL, 5 DONE, 6 RX_OVERRUN, 7 TX_DROPPED,
--                     15:8 RX_LEVEL e 23:16 TX_LEVEL
--   3 CONTROL  R/W    bit 0 CS_ASSERT, 1 RX_IRQ_ENABLE,
--                     2 TX_EMPTY_IRQ_ENABLE, 3 DONE_IRQ_ENABLE,
--                     4 ERROR_IRQ_ENABLE
--   4 DIVIDER  R/W    bits 15:0, SCLK = clock / (2 * (DIVIDER + 1))
--
-- DONE, RX_OVERRUN e TX_DROPPED são limpos escrevendo 1 no bit em STATUS, e
-- um evento novo tem prioridade sobre a limpeza. DONE é marcado quando um
-- byte termina e a fila de transmissão está vazia. A saída o_irq é de nível
-- e soma quatro causas, cada uma com a sua habilitação (zero no reset).
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;

entity sd_spi is
    generic (
        -- Frequência do clock do módulo, em hertz.
        clock_hz      : positive := 50_000_000;
        -- Frequência de SCLK no reset, em hertz (a inicialização exige no máximo 400 kHz).
        init_sclk_hz  : positive := 400_000;
        -- Quantidade de bytes na fila de recepção.
        rx_fifo_depth : positive := 32;
        -- Quantidade de bytes na fila de transmissão.
        tx_fifo_depth : positive := 32
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra do registrador, entre zero e quatro.
        i_address  : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq      : out   std_logic;
        -- Relógio serial do cartão (SD_CLK).
        o_sd_sclk  : out   std_logic;
        -- Dado do mestre para o cartão (SD_CMD no modo SPI).
        o_sd_mosi  : out   std_logic;
        -- Dado do cartão para o mestre (SD_DAT0 no modo SPI).
        i_sd_miso  : in    std_logic;
        -- Seleção de chip, ativa em nível baixo (SD_DAT3 no modo SPI).
        o_sd_cs_n  : out   std_logic
    );
end entity sd_spi;

architecture rtl of sd_spi is

    -- Endereço do registrador de transmissão.
    constant TX_DATA_ADDRESS : std_logic_vector(2 downto 0) := "000";
    -- Endereço do registrador de recepção.
    constant RX_DATA_ADDRESS : std_logic_vector(2 downto 0) := "001";
    -- Endereço do registrador de estado.
    constant STATUS_ADDRESS  : std_logic_vector(2 downto 0) := "010";
    -- Endereço do registrador de controle.
    constant CONTROL_ADDRESS : std_logic_vector(2 downto 0) := "011";
    -- Endereço do registrador do divisor.
    constant DIVIDER_ADDRESS : std_logic_vector(2 downto 0) := "100";

    -- Largura do divisor em bits.
    constant DIVIDER_WIDTH : positive := 16;

    -- Divisor do reset, que mantém SCLK em init_sclk_hz ou abaixo.
    constant RESET_DIVIDER : natural := (clock_hz + 2 * init_sclk_hz - 1) / (2 * init_sclk_hz) - 1;

    -- Linha MISO sincronizada com o clock.
    signal miso_sync : std_logic_vector(0 downto 0);

    -- Byte entregue ao mestre SPI.
    signal phy_tx_data : std_logic_vector(7 downto 0);
    -- Pulso que inicia um byte.
    signal phy_start   : std_logic;
    -- Indica um byte em andamento.
    signal phy_busy    : std_logic;
    -- Pulso de fim de byte.
    signal phy_done    : std_logic;
    -- Byte recebido pelo mestre SPI.
    signal phy_rx_data : std_logic_vector(7 downto 0);

    -- Pedido de inserção na fila de transmissão.
    signal tx_fifo_push          : std_logic;
    -- Indica que a inserção na fila de transmissão foi aceita.
    signal tx_fifo_push_accepted : std_logic;
    -- Indica que a remoção da fila de transmissão foi aceita.
    signal tx_fifo_pop_accepted  : std_logic;
    -- Byte mais antigo da fila de transmissão.
    signal tx_fifo_data          : std_logic_vector(7 downto 0);
    -- Indica que a fila de transmissão está cheia.
    signal tx_fifo_full          : std_logic;
    -- Indica que a fila de transmissão está vazia.
    signal tx_fifo_empty         : std_logic;
    -- Quantidade de bytes na fila de transmissão.
    signal tx_fifo_level         : natural range 0 to tx_fifo_depth;

    -- Pedido de remoção da fila de recepção.
    signal rx_fifo_pop           : std_logic;
    -- Indica que a inserção na fila de recepção foi aceita.
    signal rx_fifo_push_accepted : std_logic;
    -- Byte mais antigo da fila de recepção.
    signal rx_fifo_data          : std_logic_vector(7 downto 0);
    -- Indica que a fila de recepção está cheia.
    signal rx_fifo_full          : std_logic;
    -- Indica que a fila de recepção está vazia.
    signal rx_fifo_empty         : std_logic;
    -- Quantidade de bytes na fila de recepção.
    signal rx_fifo_level         : natural range 0 to rx_fifo_depth;

    -- Seleção de chip pedida pelo software.
    signal cs_assert      : std_logic;
    -- Habilitação da interrupção por byte recebido.
    signal rx_irq_enable  : std_logic;
    -- Habilitação da interrupção por fila de transmissão vazia.
    signal tx_irq_enable  : std_logic;
    -- Habilitação da interrupção por fim de transferência.
    signal done_irq_enable : std_logic;
    -- Habilitação da interrupção por erro.
    signal err_irq_enable : std_logic;
    -- Divisor de clock do SCLK.
    signal divider        : std_logic_vector(DIVIDER_WIDTH - 1 downto 0);
    -- Marca persistente de fim de transferência.
    signal done_flag      : std_logic;
    -- Erro persistente de recepção com a fila cheia.
    signal rx_overrun     : std_logic;
    -- Erro persistente de escrita com a fila de transmissão cheia.
    signal tx_dropped     : std_logic;

begin

    assert RESET_DIVIDER < 2 ** DIVIDER_WIDTH
        report "sd_spi: clock_hz / init_sclk_hz does not fit in the 16-bit divider"
        severity failure;

    assert rx_fifo_depth <= 255 and tx_fifo_depth <= 255
        report "sd_spi: fifo depths must fit in the 8-bit level fields"
        severity failure;

    o_sd_cs_n <= not cs_assert;

    tx_fifo_push <= '1' when i_write = '1' and i_address = TX_DATA_ADDRESS else '0';
    rx_fifo_pop  <= '1' when i_read = '1' and i_address = RX_DATA_ADDRESS else '0';
    phy_start    <= '1' when phy_busy = '0' and tx_fifo_empty = '0' else '0';

    o_irq <= (rx_irq_enable and not rx_fifo_empty)
             or (tx_irq_enable and tx_fifo_empty)
             or (done_irq_enable and done_flag)
             or (err_irq_enable and (rx_overrun or tx_dropped));

    u_miso_sync : entity work.synchronizer
        generic map (
            stages     => 2,
            data_width => 1
        )
        port map (
            i_clk => i_clk,
            i_rst => i_rst,
            i_d(0) => i_sd_miso,
            o_d   => miso_sync
        );

    u_tx_fifo : entity work.uart_fifo
        generic map (
            data_width => 8,
            depth      => tx_fifo_depth
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_push          => tx_fifo_push,
            i_push_data     => i_data_in(7 downto 0),
            i_pop           => phy_start,
            o_pop_data      => tx_fifo_data,
            o_push_accepted => tx_fifo_push_accepted,
            o_pop_accepted  => tx_fifo_pop_accepted,
            o_full          => tx_fifo_full,
            o_empty         => tx_fifo_empty,
            o_level         => tx_fifo_level
        );

    u_rx_fifo : entity work.uart_fifo
        generic map (
            data_width => 8,
            depth      => rx_fifo_depth
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_push          => phy_done,
            i_push_data     => phy_rx_data,
            i_pop           => rx_fifo_pop,
            o_pop_data      => rx_fifo_data,
            o_push_accepted => rx_fifo_push_accepted,
            o_pop_accepted  => open,
            o_full          => rx_fifo_full,
            o_empty         => rx_fifo_empty,
            o_level         => rx_fifo_level
        );

    phy_tx_data <= tx_fifo_data;

    u_phy : entity work.sd_spi_phy
        generic map (
            divider_width => DIVIDER_WIDTH
        )
        port map (
            i_clk     => i_clk,
            i_rst     => i_rst,
            i_divider => divider,
            i_start   => tx_fifo_pop_accepted,
            i_tx_data => phy_tx_data,
            o_busy    => phy_busy,
            o_done    => phy_done,
            o_rx_data => phy_rx_data,
            o_sclk    => o_sd_sclk,
            o_mosi    => o_sd_mosi,
            i_miso    => miso_sync(0)
        );

    p_registers : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            if i_rst = '1' then
                cs_assert       <= '0';
                rx_irq_enable   <= '0';
                tx_irq_enable   <= '0';
                done_irq_enable <= '0';
                err_irq_enable  <= '0';
                divider         <= std_logic_vector(to_unsigned(RESET_DIVIDER, DIVIDER_WIDTH));
                done_flag       <= '0';
                rx_overrun      <= '0';
                tx_dropped      <= '0';
            else
                if i_write = '1' and i_address = CONTROL_ADDRESS then
                    cs_assert       <= i_data_in(0);
                    rx_irq_enable   <= i_data_in(1);
                    tx_irq_enable   <= i_data_in(2);
                    done_irq_enable <= i_data_in(3);
                    err_irq_enable  <= i_data_in(4);
                end if;

                if i_write = '1' and i_address = DIVIDER_ADDRESS then
                    divider <= i_data_in(DIVIDER_WIDTH - 1 downto 0);
                end if;

                -- Os eventos novos têm prioridade sobre uma limpeza simultânea.
                if i_write = '1' and i_address = STATUS_ADDRESS then
                    done_flag  <= done_flag and not i_data_in(5);
                    rx_overrun <= rx_overrun and not i_data_in(6);
                    tx_dropped <= tx_dropped and not i_data_in(7);
                end if;

                if phy_done = '1' and tx_fifo_empty = '1' then
                    done_flag <= '1';
                end if;

                if phy_done = '1' and rx_fifo_push_accepted = '0' then
                    rx_overrun <= '1';
                end if;

                if tx_fifo_push = '1' and tx_fifo_push_accepted = '0' then
                    tx_dropped <= '1';
                end if;
            end if;
        end if;

    end process p_registers;

    p_readback : process (
                          i_address, rx_fifo_data, rx_fifo_empty, rx_fifo_full, rx_fifo_level, tx_fifo_empty,
                          tx_fifo_full, tx_fifo_level, phy_busy, phy_done, done_flag, rx_overrun, tx_dropped, cs_assert,
                          rx_irq_enable, tx_irq_enable, done_irq_enable, err_irq_enable, divider
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : word_t;

    begin

        value := (others => '0');

        case i_address is

            when RX_DATA_ADDRESS =>

                value(7 downto 0) := rx_fifo_data;

            when STATUS_ADDRESS =>

                value(0)            := not rx_fifo_empty;
                value(1)            := not tx_fifo_full;
                value(2)            := tx_fifo_empty;
                value(3)            := phy_busy or phy_done or not tx_fifo_empty;
                value(4)            := rx_fifo_full;
                value(5)            := done_flag;
                value(6)            := rx_overrun;
                value(7)            := tx_dropped;
                value(15 downto 8)  := std_logic_vector(to_unsigned(rx_fifo_level, 8));
                value(23 downto 16) := std_logic_vector(to_unsigned(tx_fifo_level, 8));

            when CONTROL_ADDRESS =>

                value(0) := cs_assert;
                value(1) := rx_irq_enable;
                value(2) := tx_irq_enable;
                value(3) := done_irq_enable;
                value(4) := err_irq_enable;

            when DIVIDER_ADDRESS =>

                value(DIVIDER_WIDTH - 1 downto 0) := divider;

            when others =>

                null;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;

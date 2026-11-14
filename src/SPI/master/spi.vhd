-- ==========================================================================
-- Mestre SPI mapeado em memória
-- ==========================================================================
-- Liga o mestre SPI genérico a duas filas síncronas (transmissão e
-- recepção) e aos registradores do barramento. O software enfileira palavras
-- de 1 a word_width bits em TX_DATA, cada palavra transmitida gera uma
-- palavra recebida na fila de recepção, e a seleção de chip, o modo (CPOL e
-- CPHA), a largura da palavra e a ordem dos bits ficam em CONTROL. Há de uma
-- a cs_count linhas de seleção de chip, uma ativa por vez.
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 TX_DATA   W      palavra enfileirada para transmissão
--   1 RX_DATA   R      palavra mais antiga recebida, removida pela leitura
--   2 STATUS    R/W1C  bits 0 RX_VALID, 1 TX_READY, 2 TX_EMPTY, 3 BUSY,
--                      4 RX_FULL, 5 DONE, 6 RX_OVERRUN, 7 TX_DROPPED,
--                      15:8 RX_LEVEL e 23:16 TX_LEVEL
--   3 CONTROL   R/W    bit 0 CS_ASSERT, 1 RX_IRQ_ENABLE,
--                      2 TX_EMPTY_IRQ_ENABLE, 3 DONE_IRQ_ENABLE,
--                      4 ERROR_IRQ_ENABLE, 5 CPOL, 6 CPHA, 7 LSB_FIRST,
--                      13:8 WORD_BITS, 21:16 CS_SELECT
--   4 DIVIDER   R/W    bits 15:0, SCLK = clock / (2 * (DIVIDER + 1))
--   5 TX_LISTEN W      como TX_DATA, mas o mestre solta MOSI na palavra
--                      (leitura de escravo de três fios)
--
-- DONE, RX_OVERRUN e TX_DROPPED são limpos escrevendo 1 no bit em STATUS, e
-- um evento novo tem prioridade sobre a limpeza. DONE é marcado quando uma
-- palavra termina e a fila de transmissão está vazia. A saída o_irq é de
-- nível e soma quatro causas, cada uma com a sua habilitação (zero no reset).
-- O modo, a largura, a ordem e o divisor valem a partir da palavra seguinte,
-- e CPOL só deve mudar com CS_ASSERT em zero.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;

entity spi is
    generic (
        -- Frequência do clock do módulo, em hertz.
        clock_hz      : positive := 50_000_000;
        -- Frequência de SCLK no reset, em hertz.
        reset_sclk_hz : positive := 1_000_000;
        -- Largura máxima da palavra, em bits.
        word_width    : positive range 1 to 32 := 32;
        -- Quantidade de linhas de seleção de chip.
        cs_count      : positive range 1 to 64 := 1;
        -- Quantidade de palavras na fila de recepção.
        rx_fifo_depth : positive := 16;
        -- Quantidade de palavras na fila de transmissão.
        tx_fifo_depth : positive := 16
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset síncrono, ativo em nível alto.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    word_t;
        -- Endereço de palavra do registrador, entre zero e cinco.
        i_address  : in    std_logic_vector(2 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out : out   word_t;
        -- Requisição de interrupção de nível.
        o_irq      : out   std_logic;
        -- Relógio serial.
        o_sclk     : out   std_logic;
        -- Dado do mestre para o escravo.
        o_mosi     : out   std_logic;
        -- Habilitação do driver de MOSI, em 0 durante as palavras de escuta.
        o_mosi_oe  : out   std_logic;
        -- Dado do escravo para o mestre.
        i_miso     : in    std_logic;
        -- Seleções de chip, ativas em nível baixo.
        o_cs_n     : out   std_logic_vector(cs_count - 1 downto 0)
    );
end entity spi;

architecture rtl of spi is

    -- Endereço do registrador de transmissão.
    constant TX_DATA_ADDRESS   : std_logic_vector(2 downto 0) := "000";
    -- Endereço do registrador de recepção.
    constant RX_DATA_ADDRESS   : std_logic_vector(2 downto 0) := "001";
    -- Endereço do registrador de estado.
    constant STATUS_ADDRESS    : std_logic_vector(2 downto 0) := "010";
    -- Endereço do registrador de controle.
    constant CONTROL_ADDRESS   : std_logic_vector(2 downto 0) := "011";
    -- Endereço do registrador do divisor.
    constant DIVIDER_ADDRESS   : std_logic_vector(2 downto 0) := "100";
    -- Endereço do registrador de transmissão de escuta.
    constant TX_LISTEN_ADDRESS : std_logic_vector(2 downto 0) := "101";

    -- Largura do divisor em bits.
    constant DIVIDER_WIDTH : positive := 16;

    -- Largura de uma entrada da fila de transmissão: a palavra e o bit de escuta.
    constant TX_ENTRY_WIDTH : positive := word_width + 1;

    -- Palavra de 8 bits do reset, na codificação do campo WORD_BITS.
    constant RESET_WORD_BITS : natural := 8;

    -- Divisor do reset, que mantém SCLK em reset_sclk_hz ou abaixo.
    constant RESET_DIVIDER : natural := (clock_hz + 2 * reset_sclk_hz - 1) / (2 * reset_sclk_hz) - 1;

    -- Linha MISO sincronizada com o clock.
    signal miso_sync : std_logic_vector(0 downto 0);

    -- Palavra entregue ao mestre SPI.
    signal phy_tx_data : std_logic_vector(word_width - 1 downto 0);
    -- Pulso que inicia uma palavra.
    signal phy_start   : std_logic;
    -- Indica uma palavra em andamento.
    signal phy_busy    : std_logic;
    -- Pulso de fim de palavra.
    signal phy_done    : std_logic;
    -- Palavra recebida pelo mestre SPI.
    signal phy_rx_data : std_logic_vector(word_width - 1 downto 0);
    -- Em 0 o mestre solta MOSI nesta palavra.
    signal phy_drive   : std_logic;

    -- Pedido de inserção na fila de transmissão.
    signal tx_fifo_push          : std_logic;
    -- Em 1 a escrita é em TX_LISTEN e a palavra só escuta.
    signal tx_listen             : std_logic;
    -- Entrada que entra na fila de transmissão.
    signal tx_fifo_push_data     : std_logic_vector(TX_ENTRY_WIDTH - 1 downto 0);
    -- Indica que a inserção na fila de transmissão foi aceita.
    signal tx_fifo_push_accepted : std_logic;
    -- Indica que a remoção da fila de transmissão foi aceita.
    signal tx_fifo_pop_accepted  : std_logic;
    -- Entrada mais antiga da fila de transmissão.
    signal tx_fifo_data          : std_logic_vector(TX_ENTRY_WIDTH - 1 downto 0);
    -- Indica que a fila de transmissão está cheia.
    signal tx_fifo_full          : std_logic;
    -- Indica que a fila de transmissão está vazia.
    signal tx_fifo_empty         : std_logic;
    -- Quantidade de entradas na fila de transmissão.
    signal tx_fifo_level         : natural range 0 to tx_fifo_depth;

    -- Pedido de remoção da fila de recepção.
    signal rx_fifo_pop           : std_logic;
    -- Indica que a inserção na fila de recepção foi aceita.
    signal rx_fifo_push_accepted : std_logic;
    -- Palavra mais antiga da fila de recepção.
    signal rx_fifo_data          : std_logic_vector(word_width - 1 downto 0);
    -- Indica que a fila de recepção está cheia.
    signal rx_fifo_full          : std_logic;
    -- Indica que a fila de recepção está vazia.
    signal rx_fifo_empty         : std_logic;
    -- Quantidade de palavras na fila de recepção.
    signal rx_fifo_level         : natural range 0 to rx_fifo_depth;

    -- Seleção de chip pedida pelo software.
    signal cs_assert       : std_logic;
    -- Habilitação da interrupção por palavra recebida.
    signal rx_irq_enable   : std_logic;
    -- Habilitação da interrupção por fila de transmissão vazia.
    signal tx_irq_enable   : std_logic;
    -- Habilitação da interrupção por fim de transferência.
    signal done_irq_enable : std_logic;
    -- Habilitação da interrupção por erro.
    signal err_irq_enable  : std_logic;
    -- Nível de repouso de SCLK.
    signal cpol            : std_logic;
    -- Fase de amostragem.
    signal cpha            : std_logic;
    -- Ordem dos bits da palavra.
    signal lsb_first       : std_logic;
    -- Quantidade de bits da palavra.
    signal word_bits       : std_logic_vector(5 downto 0);
    -- Linha de seleção de chip ativa quando CS_ASSERT vale 1.
    signal cs_select       : std_logic_vector(5 downto 0);
    -- Divisor de clock do SCLK.
    signal divider         : std_logic_vector(DIVIDER_WIDTH - 1 downto 0);
    -- Marca persistente de fim de transferência.
    signal done_flag       : std_logic;
    -- Erro persistente de recepção com a fila cheia.
    signal rx_overrun      : std_logic;
    -- Erro persistente de escrita com a fila de transmissão cheia.
    signal tx_dropped      : std_logic;

begin

    assert RESET_DIVIDER < 2 ** DIVIDER_WIDTH
        report "spi: clock_hz / reset_sclk_hz does not fit in the 16-bit divider"
        severity failure;

    assert rx_fifo_depth <= 255 and tx_fifo_depth <= 255
        report "spi: fifo depths must fit in the 8-bit level fields"
        severity failure;

    g_cs : for line in 0 to cs_count - 1 generate
        o_cs_n(line) <= '0' when cs_assert = '1' and to_integer(unsigned(cs_select)) = line else '1';
    end generate g_cs;

    tx_fifo_push <= '1' when i_write = '1' and (i_address = TX_DATA_ADDRESS or i_address = TX_LISTEN_ADDRESS) else '0';
    tx_listen         <= '1' when i_address = TX_LISTEN_ADDRESS else '0';
    tx_fifo_push_data <= tx_listen & i_data_in(word_width - 1 downto 0);
    rx_fifo_pop  <= '1' when i_read = '1' and i_address = RX_DATA_ADDRESS else '0';
    phy_start    <= '1' when phy_busy = '0' and tx_fifo_empty = '0' else '0';
    phy_tx_data  <= tx_fifo_data(word_width - 1 downto 0);
    phy_drive    <= not tx_fifo_data(word_width);

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
            i_d(0) => i_miso,
            o_d   => miso_sync
        );

    u_tx_fifo : entity work.uart_fifo
        generic map (
            data_width => TX_ENTRY_WIDTH,
            depth      => tx_fifo_depth
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_push          => tx_fifo_push,
            i_push_data     => tx_fifo_push_data,
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
            data_width => word_width,
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

    u_master : entity work.spi_master
        generic map (
            divider_width => DIVIDER_WIDTH,
            word_width    => word_width
        )
        port map (
            i_clk       => i_clk,
            i_rst       => i_rst,
            i_cpol      => cpol,
            i_cpha      => cpha,
            i_lsb_first => lsb_first,
            i_word_bits => word_bits,
            i_divider   => divider,
            i_tx_drive  => phy_drive,
            i_start     => tx_fifo_pop_accepted,
            i_tx_data   => phy_tx_data,
            o_busy      => phy_busy,
            o_done      => phy_done,
            o_rx_data   => phy_rx_data,
            o_sclk      => o_sclk,
            o_mosi      => o_mosi,
            o_mosi_oe   => o_mosi_oe,
            i_miso      => miso_sync(0)
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
                cpol            <= '0';
                cpha            <= '0';
                lsb_first       <= '0';
                word_bits       <= std_logic_vector(to_unsigned(RESET_WORD_BITS, 6));
                cs_select       <= (others => '0');
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
                    cpol            <= i_data_in(5);
                    cpha            <= i_data_in(6);
                    lsb_first       <= i_data_in(7);
                    word_bits       <= i_data_in(13 downto 8);
                    cs_select       <= i_data_in(21 downto 16);
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
                          rx_irq_enable, tx_irq_enable, done_irq_enable, err_irq_enable, divider, cpol, cpha,
                          lsb_first, word_bits, cs_select
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : word_t;

    begin

        value := (others => '0');

        case i_address is

            when RX_DATA_ADDRESS =>

                value(word_width - 1 downto 0) := rx_fifo_data;

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

                value(0)            := cs_assert;
                value(1)            := rx_irq_enable;
                value(2)            := tx_irq_enable;
                value(3)            := done_irq_enable;
                value(4)            := err_irq_enable;
                value(5)            := cpol;
                value(6)            := cpha;
                value(7)            := lsb_first;
                value(13 downto 8)  := word_bits;
                value(21 downto 16) := cs_select;

            when DIVIDER_ADDRESS =>

                value(DIVIDER_WIDTH - 1 downto 0) := divider;

            when others =>

                null;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;

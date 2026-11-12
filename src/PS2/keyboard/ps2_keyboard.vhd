-- ==========================================================================
-- Teclado PS/2 mapeado em memória, com fila de bytes recebidos
-- ==========================================================================
-- Liga um teclado PS/2 ao barramento do núcleo. A camada física (ps2_host)
-- entrega os bytes dos scancodes do conjunto 2 (make, break 0xF0 e estendido
-- 0xE0), que entram numa fila síncrona na ordem de chegada; o software os
-- retira um a um. Comandos ao teclado (por exemplo reset 0xFF e ajuste dos
-- LEDs 0xED) saem por uma escrita em COMMAND. Cada instância é independente,
-- então o teclado (canal 0) e o mouse (canal 1) coexistem num cabo Y.
--
-- Mapa de registradores, em endereços de palavra (4 registradores):
--
--   0 DATA     R      bits 7:0, byte mais antigo, removido pela leitura
--   1 STATUS   R/W1C  bits 0 RX_VALID, 1 TX_READY, 2 RX_OVERFLOW,
--                     3 RX_ERROR, 4 RX_FULL, 5 TX_DROPPED e
--                     15:8 RX_LEVEL; escrever 1 em 2, 3 ou 5 limpa o bit
--   2 COMMAND  W      bits 7:0, byte enviado ao teclado
--   3 CONTROL  R/W    bits 0 RX_IRQ_ENABLE e 1 ERROR_IRQ_ENABLE
--
-- A saída o_irq é de nível: fila não vazia (com RX_IRQ_ENABLE) ou erro
-- persistente, RX_OVERFLOW ou RX_ERROR (com ERROR_IRQ_ENABLE). Os dois
-- habilitadores valem zero no reset.
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_keyboard is
    generic (
        -- Largura do barramento de dados em bits.
        data_width    : natural  := 32;
        -- Quantidade de bytes na fila de recepção.
        rx_fifo_depth : positive := 16;
        -- Ciclos que um nível das linhas precisa durar para passar no filtro de glitch.
        filter_cycles : positive := 8;
        -- Ciclos com o clock em '0' antes de um comando (padrão de 120 us a 50 MHz).
        inhibit_cycles : positive := 6000;
        -- Ciclos sem borda de clock que abortam um quadro (padrão de 20 ms a 50 MHz).
        timeout_cycles : positive := 1000000
    );
    port (
        -- Clock do módulo.
        i_clk      : in    std_logic;
        -- Reset, ativo em nível alto.
        i_rst      : in    std_logic;
        -- Dado de escrita vindo do processador.
        i_data_in  : in    std_logic_vector(data_width - 1 downto 0);
        -- Endereço de palavra do registrador, entre zero e três.
        i_address  : in    std_logic_vector(1 downto 0);
        -- Pulso de escrita do processador.
        i_write    : in    std_logic;
        -- Pulso de leitura do processador.
        i_read     : in    std_logic;
        -- Dado de leitura devolvido ao processador.
        o_data_out : out   std_logic_vector(data_width - 1 downto 0);
        -- Requisição de interrupção de nível (byte recebido ou erro).
        o_irq      : out   std_logic;
        -- Linha de clock do conector PS/2, open-drain.
        io_ps2_clk : inout std_logic;
        -- Linha de dados do conector PS/2, open-drain.
        io_ps2_dat : inout std_logic
    );
end entity ps2_keyboard;

architecture rtl of ps2_keyboard is

    -- Endereço do registrador de dados recebidos.
    constant DATA_ADDRESS    : std_logic_vector(1 downto 0) := "00";
    -- Endereço do registrador de estado.
    constant STATUS_ADDRESS  : std_logic_vector(1 downto 0) := "01";
    -- Endereço do registrador de comando.
    constant COMMAND_ADDRESS : std_logic_vector(1 downto 0) := "10";
    -- Endereço do registrador de controle.
    constant CONTROL_ADDRESS : std_logic_vector(1 downto 0) := "11";

    -- Reset da camada física, ativo em nível baixo.
    signal rst_n : std_logic;

    -- Byte entregue pela camada física.
    signal phy_rx_data  : std_logic_vector(7 downto 0);
    -- Pulso de byte recebido.
    signal phy_rx_valid : std_logic;
    -- Pulso de erro da camada física.
    signal phy_rx_error : std_logic;
    -- Pulso de pedido de envio de um comando.
    signal phy_tx_valid : std_logic;
    -- A camada física aceita um comando.
    signal phy_tx_ready : std_logic;

    -- Pedido de remoção da fila de recepção.
    signal rx_fifo_pop           : std_logic;
    -- Byte mais antigo da fila de recepção.
    signal rx_fifo_data          : std_logic_vector(7 downto 0);
    -- A inserção na fila de recepção foi aceita.
    signal rx_fifo_push_accepted : std_logic;
    -- A fila de recepção está cheia.
    signal rx_fifo_full          : std_logic;
    -- A fila de recepção está vazia.
    signal rx_fifo_empty         : std_logic;
    -- Quantidade de bytes na fila de recepção.
    signal rx_fifo_level         : natural range 0 to rx_fifo_depth;

    -- Erro persistente de byte descartado com a fila cheia.
    signal rx_overflow    : std_logic;
    -- Erro persistente de quadro inválido ou comando sem reconhecimento.
    signal rx_error       : std_logic;
    -- Comando descartado por escrita com o transmissor ocupado.
    signal tx_dropped     : std_logic;
    -- Habilitação da interrupção por byte recebido.
    signal rx_irq_enable  : std_logic;
    -- Habilitação da interrupção por erro.
    signal err_irq_enable : std_logic;

begin

    assert data_width >= 16
        report "ps2_keyboard data_width must be at least 16"
        severity failure;

    assert rx_fifo_depth <= 255
        report "ps2_keyboard rx_fifo_depth must fit in the 8-bit RX_LEVEL field"
        severity failure;

    rst_n <= not i_rst;

    rx_fifo_pop  <= '1' when i_read = '1' and i_address = DATA_ADDRESS else '0';
    phy_tx_valid <= '1' when i_write = '1' and i_address = COMMAND_ADDRESS else '0';

    o_irq <= ((not rx_fifo_empty) and rx_irq_enable) or ((rx_overflow or rx_error) and err_irq_enable);

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
            i_tx_data  => i_data_in(7 downto 0),
            i_tx_valid => phy_tx_valid,
            o_tx_ready => phy_tx_ready
        );

    u_rx_fifo : entity work.uart_fifo
        generic map (
            data_width => 8,
            depth      => rx_fifo_depth
        )
        port map (
            i_clk           => i_clk,
            i_rst           => i_rst,
            i_push          => phy_rx_valid,
            i_push_data     => phy_rx_data,
            i_pop           => rx_fifo_pop,
            o_pop_data      => rx_fifo_data,
            o_push_accepted => rx_fifo_push_accepted,
            o_pop_accepted  => open,
            o_full          => rx_fifo_full,
            o_empty         => rx_fifo_empty,
            o_level         => rx_fifo_level
        );

    p_registers : process (i_rst, i_clk) is
    begin

        if i_rst = '1' then
            rx_overflow    <= '0';
            rx_error       <= '0';
            tx_dropped     <= '0';
            rx_irq_enable  <= '0';
            err_irq_enable <= '0';
        elsif rising_edge(i_clk) then
            if i_write = '1' and i_address = CONTROL_ADDRESS then
                rx_irq_enable  <= i_data_in(0);
                err_irq_enable <= i_data_in(1);
            end if;

            -- Os eventos novos têm prioridade sobre uma limpeza simultânea.
            if i_write = '1' and i_address = STATUS_ADDRESS then
                if i_data_in(2) = '1' then
                    rx_overflow <= '0';
                end if;
                if i_data_in(3) = '1' then
                    rx_error <= '0';
                end if;
                if i_data_in(5) = '1' then
                    tx_dropped <= '0';
                end if;
            end if;

            if phy_rx_valid = '1' and rx_fifo_push_accepted = '0' then
                rx_overflow <= '1';
            end if;

            if phy_rx_error = '1' then
                rx_error <= '1';
            end if;

            if phy_tx_valid = '1' and phy_tx_ready = '0' then
                tx_dropped <= '1';
            end if;
        end if;

    end process p_registers;

    p_readback : process (
                          i_address, rx_fifo_data, rx_fifo_empty, rx_fifo_full, rx_fifo_level, phy_tx_ready,
                          rx_overflow, rx_error, tx_dropped, rx_irq_enable, err_irq_enable
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : std_logic_vector(data_width - 1 downto 0);

    begin

        value := (others => '0');

        case i_address is

            when DATA_ADDRESS =>

                value(7 downto 0) := rx_fifo_data;

            when STATUS_ADDRESS =>

                value(0)           := not rx_fifo_empty;
                value(1)           := phy_tx_ready;
                value(2)           := rx_overflow;
                value(3)           := rx_error;
                value(4)           := rx_fifo_full;
                value(5)           := tx_dropped;
                value(15 downto 8) := std_logic_vector(to_unsigned(rx_fifo_level, 8));

            when CONTROL_ADDRESS =>

                value(0) := rx_irq_enable;
                value(1) := err_irq_enable;

            when others =>

                null;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;

-- ==========================================================================
-- UART serial mapeada em memória com filas de recepção e transmissão
-- ==========================================================================
-- Envolve a camada física do OpenCores (8N1, com paridade e segundo bit de
-- parada opcionais) com duas filas síncronas. O software enfileira bytes para
-- transmissão e retira os bytes recebidos em ordem. A interface mapeada em
-- memória continua concluindo cada acesso em um ciclo e sinaliza tentativas
-- rejeitadas por falta de espaço.
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 TX_DATA   W      bits 7:0, byte enfileirado para transmissão
--   1 RX_DATA   R      bits 7:0, byte mais antigo, removido pela leitura
--   2 STATUS    R/W1C  bits 0 RX_VALID, 1 TX_READY, 2 RX_OVERRUN,
--                      3 TX_DROPPED, 4 RX_FULL, 5 TX_EMPTY, 6 TX_IDLE,
--                      7 FRAME_ERROR, 15:8 RX_LEVEL, 23:16 TX_LEVEL,
--                      24 PARITY_ERROR, 25 CTS_ACTIVE, 26 RTS_ACTIVE
--                      (CTS_ACTIVE e RTS_ACTIVE só leitura, e só com
--                      has_flow_control; sem ele leem zero)
--   3 CONTROL   R/W    bit 0 RX_IRQ_ENABLE, 1 TX_EMPTY_IRQ_ENABLE,
--                      2 ERROR_IRQ_ENABLE, 3 PARITY_ENABLE, 4 PARITY_ODD,
--                      5 STOP_BITS_2, 6 LINE_ERROR_IRQ_ENABLE e, só com
--                      has_flow_control, 7 FLOW_ENABLE e 15:8 RTS_THRESHOLD
--
-- A saída o_irq é de nível e vale a soma de quatro causas, cada uma com a sua
-- habilitação (zero no reset): fila de recepção não vazia (RX_VALID), fila de
-- transmissão vazia (TX_EMPTY), erro de fila (RX_OVERRUN ou TX_DROPPED) e erro
-- de linha (FRAME_ERROR ou PARITY_ERROR). Os erros são persistentes e o
-- software os limpa escrevendo 1 no bit em STATUS. As duas primeiras causas
-- param quando a condição some (leitura de RX_DATA, escrita em TX_DATA).
--
-- O quadro é 8N1 até o software escrever em CONTROL: PARITY_ENABLE acrescenta
-- o bit de paridade depois dos dados (par, ou ímpar com PARITY_ODD) e
-- STOP_BITS_2 envia dois bits de parada. O receptor confere a paridade e o
-- primeiro bit de parada; o byte com erro entra na fila como qualquer outro, e
-- só as flags registram o erro. O formato só deve mudar com a linha ociosa.
--
-- Com has_flow_control, FLOW_ENABLE (zero no reset) liga o controle de fluxo
-- por hardware, com as duas linhas de nível baixo ativo. Com i_uart_cts em
-- nível alto o transmissor não inicia um novo quadro (o quadro em curso
-- termina e os bytes esperam na fila). o_uart_rts sobe, registrado, enquanto a
-- fila de recepção tem RTS_THRESHOLD bytes ou mais, e desce quando tem menos;
-- RTS_THRESHOLD vale a metade da fila (no mínimo 1) no reset, e zero mantém
-- o_uart_rts sempre inativo. Sem FLOW_ENABLE, ou sem o generic, a UART ignora
-- i_uart_cts e mantém o_uart_rts ativo (baixo).
-- ==========================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart is
    generic (
        -- Largura do barramento de dados em bits.
        data_width    : natural  := 32;
        -- Constante de frequência do gerador de baud do OpenCores.
        baud_freq     : natural  := 16#240#;
        -- Constante de limite do gerador de baud do OpenCores.
        baud_limit    : natural  := 16#3AC9#;
        -- Quantidade de bytes na fila de recepção.
        rx_fifo_depth : positive := 16;
        -- Quantidade de bytes na fila de transmissão.
        tx_fifo_depth : positive := 16;
        -- Inclui o controle de fluxo por hardware (RTS e CTS); falso mantém o comportamento só com RX e TX.
        has_flow_control : boolean := false
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
        -- Requisição de interrupção de nível (recepção, transmissor vazio ou erro).
        o_irq      : out   std_logic;
        -- Linha serial de recepção.
        i_uart_rx  : in    std_logic;
        -- Linha serial de transmissão.
        o_uart_tx  : out   std_logic;
        -- Clear to send, nível baixo ativo: o outro lado aceita bytes. Ignorada sem has_flow_control.
        i_uart_cts : in    std_logic := '0';
        -- Request to send, nível baixo ativo: há espaço na fila de recepção. Ativa (baixa) sem has_flow_control.
        o_uart_rts : out   std_logic
    );
end entity uart;

architecture rtl of uart is

    -- Endereço do registrador de transmissão.
    constant TX_DATA_ADDRESS : std_logic_vector(1 downto 0) := "00";
    -- Endereço do registrador de recepção.
    constant RX_DATA_ADDRESS : std_logic_vector(1 downto 0) := "01";
    -- Endereço do registrador de estado.
    constant STATUS_ADDRESS  : std_logic_vector(1 downto 0) := "10";
    -- Endereço do registrador de controle.
    constant CONTROL_ADDRESS : std_logic_vector(1 downto 0) := "11";

    -- Constante de frequência na largura exigida pela camada física.
    constant BAUD_FREQ_VALUE  : std_logic_vector(11 downto 0) :=
        std_logic_vector(to_unsigned(baud_freq, 12));
    -- Constante de limite na largura exigida pela camada física.
    constant BAUD_LIMIT_VALUE : std_logic_vector(15 downto 0) :=
        std_logic_vector(to_unsigned(baud_limit, 16));

    -- Byte entregue ao transmissor físico.
    signal phy_tx_data     : std_logic_vector(7 downto 0);
    -- Pulso que inicia uma transmissão física.
    signal phy_new_tx_data : std_logic;
    -- Indica uma transmissão física em andamento.
    signal phy_tx_busy     : std_logic;
    -- Byte produzido pelo receptor físico.
    signal phy_rx_data     : std_logic_vector(7 downto 0);
    -- Pulso que indica a chegada de um byte físico.
    signal phy_new_rx_data : std_logic;

    -- Pedido de inserção na fila de transmissão.
    signal tx_fifo_push          : std_logic;
    -- Pedido de remoção da fila de transmissão.
    signal tx_fifo_pop           : std_logic;
    -- Byte mais antigo da fila de transmissão.
    signal tx_fifo_data          : std_logic_vector(7 downto 0);
    -- Indica que a inserção na fila de transmissão foi aceita.
    signal tx_fifo_push_accepted : std_logic;
    -- Indica que a remoção da fila de transmissão foi aceita.
    signal tx_fifo_pop_accepted  : std_logic;
    -- Indica que a fila de transmissão está cheia.
    signal tx_fifo_full          : std_logic;
    -- Indica que a fila de transmissão está vazia.
    signal tx_fifo_empty         : std_logic;
    -- Quantidade de bytes na fila de transmissão.
    signal tx_fifo_level         : natural range 0 to tx_fifo_depth;

    -- Pedido de inserção na fila de recepção.
    signal rx_fifo_push          : std_logic;
    -- Pedido de remoção da fila de recepção.
    signal rx_fifo_pop           : std_logic;
    -- Byte mais antigo da fila de recepção.
    signal rx_fifo_data          : std_logic_vector(7 downto 0);
    -- Indica que a inserção na fila de recepção foi aceita.
    signal rx_fifo_push_accepted : std_logic;
    -- Indica que a fila de recepção está cheia.
    signal rx_fifo_full          : std_logic;
    -- Indica que a fila de recepção está vazia.
    signal rx_fifo_empty         : std_logic;
    -- Quantidade de bytes na fila de recepção.
    signal rx_fifo_level         : natural range 0 to rx_fifo_depth;

    -- Erro persistente de recepção com a fila cheia.
    signal rx_overrun     : std_logic;
    -- Erro persistente de escrita com a fila de transmissão cheia.
    signal tx_dropped     : std_logic;
    -- Habilitação da interrupção por recepção pendente.
    signal rx_irq_enable  : std_logic;
    -- Habilitação da interrupção por fila de transmissão vazia.
    signal tx_irq_enable  : std_logic;
    -- Habilitação da interrupção por erro (overrun de recepção ou descarte de transmissão).
    signal err_irq_enable : std_logic;

    -- Pulso do receptor físico: o bit de parada foi amostrado em zero.
    signal phy_frame_error  : std_logic;
    -- Pulso do receptor físico: o bit de paridade não confere com o byte.
    signal phy_parity_error : std_logic;
    -- Erro persistente de quadro (bit de parada em zero).
    signal frame_error      : std_logic;
    -- Erro persistente de paridade.
    signal parity_error     : std_logic;
    -- Habilitação do bit de paridade nos dois sentidos.
    signal parity_enable    : std_logic;
    -- Paridade ímpar quando um, par quando zero.
    signal parity_odd       : std_logic;
    -- Dois bits de parada na transmissão.
    signal stop_bits_2      : std_logic;
    -- Habilitação da interrupção por erro de linha (quadro ou paridade).
    signal line_irq_enable  : std_logic;

    -- Habilitação do controle de fluxo (sempre zero sem has_flow_control).
    signal flow_enable   : std_logic;
    -- Nível da fila de recepção a partir do qual o_uart_rts fica inativo.
    signal rts_threshold : unsigned(7 downto 0);
    -- Saída de RTS registrada, um é inativo.
    signal rts_inactive  : std_logic;
    -- Entrada de CTS sincronizada com o clock em dois estágios, um é inativo.
    signal cts_sync      : std_logic_vector(1 downto 0);
    -- Indica que o transmissor pode iniciar um novo quadro.
    signal cts_ok        : std_logic;

    -- Limiar de RTS do reset: metade da fila de recepção, no mínimo um byte.

    function reset_threshold return natural is
    begin

        if rx_fifo_depth / 2 < 1 then
            return 1;
        end if;

        return rx_fifo_depth / 2;

    end function reset_threshold;

begin

    assert data_width >= 32
        report "UART data_width must be at least 32"
        severity failure;

    assert baud_freq <= 16#FFF#
        report "UART baud_freq does not fit in 12 bits"
        severity failure;

    assert baud_limit <= 16#FFFF#
        report "UART baud_limit does not fit in 16 bits"
        severity failure;

    assert rx_fifo_depth <= 255
        report "UART rx_fifo_depth must fit in the 8-bit RX_LEVEL field"
        severity failure;

    assert tx_fifo_depth <= 255
        report "UART tx_fifo_depth must fit in the 8-bit TX_LEVEL field"
        severity failure;

    tx_fifo_push <= '1'
                    when i_write = '1' and i_address = TX_DATA_ADDRESS else
                    '0';
    tx_fifo_pop  <= '1'
                    when phy_tx_busy = '0' and tx_fifo_empty = '0' and cts_ok = '1' else
                    '0';

    cts_ok <= '1' when (not has_flow_control) or flow_enable = '0' or cts_sync(1) = '0' else '0';

    o_uart_rts <= rts_inactive;

    rx_fifo_push <= phy_new_rx_data;
    rx_fifo_pop  <= '1'
                    when i_read = '1' and i_address = RX_DATA_ADDRESS else
                    '0';

    phy_tx_data     <= tx_fifo_data;
    phy_new_tx_data <= tx_fifo_pop_accepted;

    o_irq <= ((not rx_fifo_empty) and rx_irq_enable)
             or (tx_fifo_empty and tx_irq_enable)
             or ((rx_overrun or tx_dropped) and err_irq_enable)
             or ((frame_error or parity_error) and line_irq_enable);

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
            i_pop           => tx_fifo_pop,
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
            i_push          => rx_fifo_push,
            i_push_data     => phy_rx_data,
            i_pop           => rx_fifo_pop,
            o_pop_data      => rx_fifo_data,
            o_push_accepted => rx_fifo_push_accepted,
            o_pop_accepted  => open,
            o_full          => rx_fifo_full,
            o_empty         => rx_fifo_empty,
            o_level         => rx_fifo_level
        );

    u_uart_phy : entity work.uarttop
        port map (
            clr       => i_rst,
            clk       => i_clk,
            serin     => i_uart_rx,
            serout    => o_uart_tx,
            txdata    => phy_tx_data,
            newtxdata => phy_new_tx_data,
            txbusy    => phy_tx_busy,
            rxdata    => phy_rx_data,
            newrxdata => phy_new_rx_data,
            baudfreq  => BAUD_FREQ_VALUE,
            baudlimit => BAUD_LIMIT_VALUE,
            baudclk   => open,
            cfgparityen  => parity_enable,
            cfgparityodd => parity_odd,
            cfgstop2     => stop_bits_2,
            frameerr     => phy_frame_error,
            parityerr    => phy_parity_error
        );

    p_registers : process (i_rst, i_clk) is
    begin

        if i_rst = '1' then
            rx_overrun      <= '0';
            tx_dropped      <= '0';
            rx_irq_enable   <= '0';
            tx_irq_enable   <= '0';
            err_irq_enable  <= '0';
            frame_error     <= '0';
            parity_error    <= '0';
            parity_enable   <= '0';
            parity_odd      <= '0';
            stop_bits_2     <= '0';
            line_irq_enable <= '0';
            flow_enable     <= '0';
            rts_threshold   <= to_unsigned(reset_threshold, 8);
            rts_inactive    <= '0';
            cts_sync        <= (others => '1');
        elsif rising_edge(i_clk) then
            -- Sem o generic, o fluxo fica desligado e o limiar parado no valor do reset.
            if not has_flow_control then
                flow_enable   <= '0';
                rts_threshold <= to_unsigned(reset_threshold, 8);
            end if;

            if i_write = '1' and i_address = CONTROL_ADDRESS then
                rx_irq_enable   <= i_data_in(0);
                tx_irq_enable   <= i_data_in(1);
                err_irq_enable  <= i_data_in(2);
                parity_enable   <= i_data_in(3);
                parity_odd      <= i_data_in(4);
                stop_bits_2     <= i_data_in(5);
                line_irq_enable <= i_data_in(6);

                if has_flow_control then
                    flow_enable   <= i_data_in(7);
                    rts_threshold <= unsigned(i_data_in(15 downto 8));
                end if;
            end if;

            -- Os eventos novos têm prioridade sobre uma limpeza simultânea.
            if i_write = '1' and i_address = STATUS_ADDRESS then
                if i_data_in(2) = '1' then
                    rx_overrun <= '0';
                end if;
                if i_data_in(3) = '1' then
                    tx_dropped <= '0';
                end if;
                if i_data_in(7) = '1' then
                    frame_error <= '0';
                end if;
                if i_data_in(24) = '1' then
                    parity_error <= '0';
                end if;
            end if;

            if tx_fifo_push = '1' and tx_fifo_push_accepted = '0' then
                tx_dropped <= '1';
            end if;

            if rx_fifo_push = '1' and rx_fifo_push_accepted = '0' then
                rx_overrun <= '1';
            end if;

            if phy_frame_error = '1' then
                frame_error <= '1';
            end if;

            if phy_parity_error = '1' then
                parity_error <= '1';
            end if;

            -- CTS vem de fora do domínio de clock; RTS sai registrado, sem glitch.
            cts_sync <= cts_sync(0) & i_uart_cts;

            if flow_enable = '1' and rx_fifo_level >= to_integer(rts_threshold) then
                rts_inactive <= '1';
            else
                rts_inactive <= '0';
            end if;
        end if;

    end process p_registers;

    p_readback : process (
                          i_address, rx_fifo_data, rx_fifo_empty, rx_fifo_full, rx_fifo_level, tx_fifo_empty,
                          tx_fifo_full, tx_fifo_level, phy_tx_busy, rx_overrun, tx_dropped, rx_irq_enable,
                          tx_irq_enable, err_irq_enable, frame_error, parity_error, parity_enable, parity_odd,
                          stop_bits_2, line_irq_enable, flow_enable, rts_threshold, rts_inactive, cts_sync
                         ) is

        -- Valor montado para o registrador selecionado.
        variable value : std_logic_vector(data_width - 1 downto 0);

    begin

        value := (others => '0');

        case i_address is

            when TX_DATA_ADDRESS =>

                null;

            when RX_DATA_ADDRESS =>

                value(7 downto 0) := rx_fifo_data;

            when STATUS_ADDRESS =>

                value(0)            := not rx_fifo_empty;
                value(1)            := not tx_fifo_full;
                value(2)            := rx_overrun;
                value(3)            := tx_dropped;
                value(4)            := rx_fifo_full;
                value(5)            := tx_fifo_empty;
                value(6)            := tx_fifo_empty and not phy_tx_busy;
                value(7)            := frame_error;
                value(15 downto 8)  := std_logic_vector(to_unsigned(rx_fifo_level, 8));
                value(23 downto 16) := std_logic_vector(to_unsigned(tx_fifo_level, 8));
                value(24)           := parity_error;

                if has_flow_control then
                    value(25) := not cts_sync(1);
                    value(26) := not rts_inactive;
                end if;

            when CONTROL_ADDRESS =>

                value(0) := rx_irq_enable;
                value(1) := tx_irq_enable;
                value(2) := err_irq_enable;
                value(3) := parity_enable;
                value(4) := parity_odd;
                value(5) := stop_bits_2;
                value(6) := line_irq_enable;

                if has_flow_control then
                    value(7)           := flow_enable;
                    value(15 downto 8) := std_logic_vector(rts_threshold);
                end if;

            when others =>

                null;

        end case;

        o_data_out <= value;

    end process p_readback;

end architecture rtl;

-- ==========================================================================
-- UART serial mapeada em memória com filas de recepção e transmissão
-- ==========================================================================
-- Envolve a camada física 8N1 do OpenCores com duas filas síncronas. O
-- software enfileira bytes para transmissão e retira os bytes recebidos em
-- ordem. A interface mapeada em memória continua concluindo cada acesso em um
-- ciclo e sinaliza tentativas rejeitadas por falta de espaço.
--
-- Mapa de registradores, em endereços de palavra:
--
--   0 TX_DATA   W      bits 7:0, byte enfileirado para transmissão
--   1 RX_DATA   R      bits 7:0, byte mais antigo, removido pela leitura
--   2 STATUS    R/W1C  bits 0 RX_VALID, 1 TX_READY, 2 RX_OVERRUN,
--                      3 TX_DROPPED, 4 RX_FULL, 5 TX_EMPTY, 6 TX_IDLE,
--                      15:8 RX_LEVEL e 23:16 TX_LEVEL
--   3 CONTROL   R/W    bit 0 RX_IRQ_ENABLE
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
    tx_fifo_depth : positive := 16
  );
  port (
    -- Clock do módulo.
    i_clk      : in  std_logic;
    -- Reset, ativo em nível alto.
    i_rst      : in  std_logic;
    -- Dado de escrita vindo do processador.
    i_data_in  : in  std_logic_vector(data_width - 1 downto 0);
    -- Endereço de palavra do registrador, entre zero e três.
    i_address  : in  std_logic_vector(1 downto 0);
    -- Pulso de escrita do processador.
    i_write    : in  std_logic;
    -- Pulso de leitura do processador.
    i_read     : in  std_logic;
    -- Dado de leitura devolvido ao processador.
    o_data_out : out std_logic_vector(data_width - 1 downto 0);
    -- Requisição de interrupção de recepção.
    o_irq      : out std_logic;
    -- Linha serial de recepção.
    i_uart_rx  : in  std_logic;
    -- Linha serial de transmissão.
    o_uart_tx  : out std_logic
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
  constant BAUD_FREQ_VALUE : std_logic_vector(11 downto 0) :=
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
  signal rx_overrun    : std_logic;
  -- Erro persistente de escrita com a fila de transmissão cheia.
  signal tx_dropped    : std_logic;
  -- Habilitação da interrupção por recepção pendente.
  signal rx_irq_enable : std_logic;
begin
  assert data_width >= 24
    report "UART data_width must be at least 24"
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
    when i_write = '1' and i_address = TX_DATA_ADDRESS
    else '0';
  tx_fifo_pop <= '1'
    when phy_tx_busy = '0' and tx_fifo_empty = '0'
    else '0';

  rx_fifo_push <= phy_new_rx_data;
  rx_fifo_pop <= '1'
    when i_read = '1' and i_address = RX_DATA_ADDRESS
    else '0';

  phy_tx_data     <= tx_fifo_data;
  phy_new_tx_data <= tx_fifo_pop_accepted;

  o_irq <= (not rx_fifo_empty) and rx_irq_enable;

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

  u_uart_phy : entity work.uartTop
    port map (
      clr       => i_rst,
      clk       => i_clk,
      serIn     => i_uart_rx,
      serOut    => o_uart_tx,
      txData    => phy_tx_data,
      newTxData => phy_new_tx_data,
      txBusy    => phy_tx_busy,
      rxData    => phy_rx_data,
      newRxData => phy_new_rx_data,
      baudFreq  => BAUD_FREQ_VALUE,
      baudLimit => BAUD_LIMIT_VALUE,
      baudClk   => open
    );

  p_registers : process (i_rst, i_clk)
  begin
    if i_rst = '1' then
      rx_overrun    <= '0';
      tx_dropped    <= '0';
      rx_irq_enable <= '0';
    elsif rising_edge(i_clk) then
      if i_write = '1' and i_address = CONTROL_ADDRESS then
        rx_irq_enable <= i_data_in(0);
      end if;

      -- Os eventos novos têm prioridade sobre uma limpeza simultânea.
      if i_write = '1' and i_address = STATUS_ADDRESS then
        if i_data_in(2) = '1' then
          rx_overrun <= '0';
        end if;
        if i_data_in(3) = '1' then
          tx_dropped <= '0';
        end if;
      end if;

      if tx_fifo_push = '1' and tx_fifo_push_accepted = '0' then
        tx_dropped <= '1';
      end if;

      if rx_fifo_push = '1' and rx_fifo_push_accepted = '0' then
        rx_overrun <= '1';
      end if;
    end if;
  end process p_registers;

  p_readback : process (
    i_address,
    rx_fifo_data,
    rx_fifo_empty,
    rx_fifo_full,
    rx_fifo_level,
    tx_fifo_empty,
    tx_fifo_full,
    tx_fifo_level,
    phy_tx_busy,
    rx_overrun,
    tx_dropped,
    rx_irq_enable
  )
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
        value(0) := not rx_fifo_empty;
        value(1) := not tx_fifo_full;
        value(2) := rx_overrun;
        value(3) := tx_dropped;
        value(4) := rx_fifo_full;
        value(5) := tx_fifo_empty;
        value(6) := tx_fifo_empty and not phy_tx_busy;
        value(15 downto 8) :=
          std_logic_vector(to_unsigned(rx_fifo_level, 8));
        value(23 downto 16) :=
          std_logic_vector(to_unsigned(tx_fifo_level, 8));

      when CONTROL_ADDRESS =>
        value(0) := rx_irq_enable;

      when others =>
        null;
    end case;

    o_data_out <= value;
  end process p_readback;
end architecture rtl;

-- =============================================================================
-- UART mapeada em memória
--
-- Envoltório mapeado em memória dos blocos físicos de UART uart2bus do
-- OpenCores. O analisador de comandos e mestre de barramento do uart2bus não é
-- usado de propósito: o software que roda no processador RV32 controla este
-- periférico diretamente.
--
-- Mapa de registradores (endereços de palavra):
--
--   0 TX_DATA   W      [7:0] byte a transmitir; a leitura devolve zero
--   1 RX_DATA   R      [7:0] byte recebido; a leitura consome RX_VALID
--   2 STATUS    R/W1C  bit 0 RX_VALID, bit 1 TX_READY, bit 2 RX_OVERRUN, bit 3 TX_DROPPED
--   3 CONTROL   R/W    bit 0 RX_IRQ_ENABLE
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart is
  generic (
    -- Largura do barramento de dados em bits.
    data_width : natural := 32;
    -- Constante de frequência do gerador de baud do OpenCores.
    baud_freq  : natural := 16#240#;
    -- Constante de limite do gerador de baud do OpenCores.
    baud_limit : natural := 16#3AC9#
  );
  port (
    -- Clock do módulo.
    i_clk    : in  std_logic;
    -- Reset, ativo em '1'.
    i_rst    : in  std_logic;
    -- Dado de escrita vindo do processador.
    i_data_in  : in  std_logic_vector(data_width - 1 downto 0);
    -- Endereço de palavra do registrador (0 a 3).
    i_address  : in  std_logic_vector(1 downto 0);
    -- Pulso de escrita do processador ('1' = escreve).
    i_write    : in  std_logic;
    -- Pulso de leitura do processador ('1' = lê).
    i_read     : in  std_logic;
    -- Dado de leitura para o processador.
    o_data_out : out std_logic_vector(data_width - 1 downto 0);
    -- Requisição de interrupção, ativa em '1'.
    o_irq      : out std_logic;
    -- Linha serial de recepção.
    i_uart_rx  : in  std_logic;
    -- Linha serial de transmissão.
    o_uart_tx  : out std_logic
  );
end entity uart;

architecture rtl of uart is
  -- Endereço do registrador TX_DATA.
  constant TX_DATA_ADDRESS : std_logic_vector(1 downto 0) := "00";
  -- Endereço do registrador RX_DATA.
  constant RX_DATA_ADDRESS : std_logic_vector(1 downto 0) := "01";
  -- Endereço do registrador STATUS.
  constant STATUS_ADDRESS  : std_logic_vector(1 downto 0) := "10";
  -- Endereço do registrador CONTROL.
  constant CONTROL_ADDRESS : std_logic_vector(1 downto 0) := "11";

  -- baud_freq em 12 bits, a entrada do gerador de baud.
  constant BAUD_FREQ_VALUE : std_logic_vector(11 downto 0) :=
    std_logic_vector(to_unsigned(baud_freq, 12));
  -- baud_limit em 16 bits, a entrada do gerador de baud.
  constant BAUD_LIMIT_VALUE : std_logic_vector(15 downto 0) :=
    std_logic_vector(to_unsigned(baud_limit, 16));

  -- Byte entregue ao transmissor físico.
  signal phy_tx_data     : std_logic_vector(7 downto 0);
  -- Pulso que inicia a transmissão do byte.
  signal phy_new_tx_data : std_logic;
  -- O transmissor físico está ocupado ('1').
  signal phy_tx_busy     : std_logic;
  -- Byte recebido pelo receptor físico.
  signal phy_rx_data     : std_logic_vector(7 downto 0);
  -- Pulso que indica um byte novo recebido.
  signal phy_new_rx_data : std_logic;

  -- Último byte recebido.
  signal rx_data_reg  : std_logic_vector(7 downto 0);
  -- Há um byte recebido ainda não lido.
  signal rx_valid     : std_logic;
  -- Um byte chegou com o anterior ainda não lido.
  signal rx_overrun   : std_logic;
  -- Uma escrita foi descartada por transmissor ocupado.
  signal tx_dropped   : std_logic;
  -- Habilita a interrupção por byte recebido.
  signal rx_irq_enable : std_logic;
begin
  assert data_width >= 8
    report "UART DATA_WIDTH must be at least 8"
    severity failure;

  assert baud_freq <= 16#fff#
    report "UART BAUD_FREQ does not fit in 12 bits"
    severity failure;

  assert baud_limit <= 16#ffff#
    report "UART BAUD_LIMIT does not fit in 16 bits"
    severity failure;

  phy_tx_data <= i_data_in(7 downto 0);
  phy_new_tx_data <= '1'
    when i_write = '1' and i_address = TX_DATA_ADDRESS and phy_tx_busy = '0'
    else '0';

  o_irq <= rx_valid and rx_irq_enable;

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

  registers : process (i_rst, i_clk)
  begin
    if i_rst = '1' then
      rx_data_reg   <= (others => '0');
      rx_valid      <= '0';
      rx_overrun    <= '0';
      tx_dropped    <= '0';
      rx_irq_enable <= '0';
    elsif rising_edge(i_clk) then
      -- CONTROL é um registrador comum de leitura e escrita.
      if i_write = '1' and i_address = CONTROL_ADDRESS then
        rx_irq_enable <= i_data_in(0);
      end if;

      -- Os bits de erro de STATUS limpam escrevendo 1. Um evento novo
      -- no mesmo ciclo vence a limpeza simultânea do software.
      if i_write = '1' and i_address = STATUS_ADDRESS then
        if i_data_in(2) = '1' then
          rx_overrun <= '0';
        end if;
        if i_data_in(3) = '1' then
          tx_dropped <= '0';
        end if;
      end if;

      -- Uma escrita com o transmissor ocupado é descartada de propósito.
      if i_write = '1' and i_address = TX_DATA_ADDRESS and phy_tx_busy = '1' then
        tx_dropped <= '1';
      end if;

      -- Um byte recém-recebido tem prioridade sobre a limpeza de RX_VALID. Assim,
      -- quando a leitura e a chegada coincidem, o software consome o byte anterior
      -- e o byte novo continua pendente.
      if phy_new_rx_data = '1' then
        if rx_valid = '1' and
           not (i_read = '1' and i_address = RX_DATA_ADDRESS) then
          rx_overrun <= '1';
        end if;
        rx_data_reg <= phy_rx_data;
        rx_valid    <= '1';
      elsif i_read = '1' and i_address = RX_DATA_ADDRESS then
        rx_valid <= '0';
      end if;
    end if;
  end process registers;

  readback : process (
    i_address,
    rx_data_reg,
    rx_valid,
    phy_tx_busy,
    rx_overrun,
    tx_dropped,
    rx_irq_enable
  )
    -- Valor lido do registrador selecionado.
    variable value : std_logic_vector(data_width - 1 downto 0);
  begin
    value := (others => '0');

    case i_address is
      when TX_DATA_ADDRESS =>
        null;

      when RX_DATA_ADDRESS =>
        value(7 downto 0) := rx_data_reg;

      when STATUS_ADDRESS =>
        value(0) := rx_valid;
        value(1) := not phy_tx_busy;
        value(2) := rx_overrun;
        value(3) := tx_dropped;

      when CONTROL_ADDRESS =>
        value(0) := rx_irq_enable;

      when others =>
        null;
    end case;

    o_data_out <= value;
  end process readback;
end architecture rtl;

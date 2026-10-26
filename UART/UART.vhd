-- =============================================================================
-- Entity: UART
-- Description:
--   Memory-mapped wrapper around the OpenCores uart2bus physical UART blocks.
--   The command parser/bus-master portion of uart2bus is deliberately not used:
--   software running on the RV32 processor controls this peripheral directly.
--
-- Register map (word addresses):
--   0 TX_DATA W     [7:0] byte to transmit; reads return zero
--   1 RX_DATA R     [7:0] received byte; reading consumes RX_VALID
--   2 STATUS  R/W1C bit 0 RX_VALID, bit 1 TX_READY,
--                    bit 2 RX_OVERRUN, bit 3 TX_DROPPED
--   3 CONTROL R/W   bit 0 RX_IRQ_ENABLE
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART is
  generic (
    DATA_WIDTH : natural := 32;
    BAUD_FREQ  : natural := 16#240#;
    BAUD_LIMIT : natural := 16#3AC9#
  );
  port (
    clock    : in  std_logic;
    clear    : in  std_logic;
    data_in  : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    address  : in  std_logic_vector(1 downto 0);
    write    : in  std_logic;
    read     : in  std_logic;
    data_out : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    irq      : out std_logic;
    uart_rx  : in  std_logic;
    uart_tx  : out std_logic
  );
end entity UART;

architecture RTL of UART is
  constant TX_DATA_ADDRESS : std_logic_vector(1 downto 0) := "00";
  constant RX_DATA_ADDRESS : std_logic_vector(1 downto 0) := "01";
  constant STATUS_ADDRESS  : std_logic_vector(1 downto 0) := "10";
  constant CONTROL_ADDRESS : std_logic_vector(1 downto 0) := "11";

  constant BAUD_FREQ_VALUE : std_logic_vector(11 downto 0) :=
    std_logic_vector(to_unsigned(BAUD_FREQ, 12));
  constant BAUD_LIMIT_VALUE : std_logic_vector(15 downto 0) :=
    std_logic_vector(to_unsigned(BAUD_LIMIT, 16));

  signal phy_tx_data     : std_logic_vector(7 downto 0);
  signal phy_new_tx_data : std_logic;
  signal phy_tx_busy     : std_logic;
  signal phy_rx_data     : std_logic_vector(7 downto 0);
  signal phy_new_rx_data : std_logic;

  signal rx_data_reg  : std_logic_vector(7 downto 0);
  signal rx_valid     : std_logic;
  signal rx_overrun   : std_logic;
  signal tx_dropped   : std_logic;
  signal rx_irq_enable : std_logic;
begin
  assert DATA_WIDTH >= 8
    report "UART DATA_WIDTH must be at least 8"
    severity failure;

  assert BAUD_FREQ <= 16#FFF#
    report "UART BAUD_FREQ does not fit in 12 bits"
    severity failure;

  assert BAUD_LIMIT <= 16#FFFF#
    report "UART BAUD_LIMIT does not fit in 16 bits"
    severity failure;

  phy_tx_data <= data_in(7 downto 0);
  phy_new_tx_data <= '1'
    when write = '1' and address = TX_DATA_ADDRESS and phy_tx_busy = '0'
    else '0';

  irq <= rx_valid and rx_irq_enable;

  UART_PHY : entity work.uartTop
    port map (
      clr       => clear,
      clk       => clock,
      serIn     => uart_rx,
      serOut    => uart_tx,
      txData    => phy_tx_data,
      newTxData => phy_new_tx_data,
      txBusy    => phy_tx_busy,
      rxData    => phy_rx_data,
      newRxData => phy_new_rx_data,
      baudFreq  => BAUD_FREQ_VALUE,
      baudLimit => BAUD_LIMIT_VALUE,
      baudClk   => open
    );

  REGISTERS : process (clear, clock)
  begin
    if clear = '1' then
      rx_data_reg   <= (others => '0');
      rx_valid      <= '0';
      rx_overrun    <= '0';
      tx_dropped    <= '0';
      rx_irq_enable <= '0';
    elsif rising_edge(clock) then
      -- CONTROL is an ordinary read/write register.
      if write = '1' and address = CONTROL_ADDRESS then
        rx_irq_enable <= data_in(0);
      end if;

      -- STATUS error bits use write-one-to-clear semantics. A new event later
      -- in this clock cycle wins over a simultaneous software clear.
      if write = '1' and address = STATUS_ADDRESS then
        if data_in(2) = '1' then
          rx_overrun <= '0';
        end if;
        if data_in(3) = '1' then
          tx_dropped <= '0';
        end if;
      end if;

      -- A write while the transmitter is busy is intentionally discarded.
      if write = '1' and address = TX_DATA_ADDRESS and phy_tx_busy = '1' then
        tx_dropped <= '1';
      end if;

      -- A newly received byte has priority over clearing RX_VALID. Therefore,
      -- when read and arrival coincide, software consumes the previous byte
      -- and the new byte remains pending.
      if phy_new_rx_data = '1' then
        if rx_valid = '1' and
           not (read = '1' and address = RX_DATA_ADDRESS) then
          rx_overrun <= '1';
        end if;
        rx_data_reg <= phy_rx_data;
        rx_valid    <= '1';
      elsif read = '1' and address = RX_DATA_ADDRESS then
        rx_valid <= '0';
      end if;
    end if;
  end process REGISTERS;

  READBACK : process (
    address,
    rx_data_reg,
    rx_valid,
    phy_tx_busy,
    rx_overrun,
    tx_dropped,
    rx_irq_enable
  )
    variable value : std_logic_vector(DATA_WIDTH - 1 downto 0);
  begin
    value := (others => '0');

    case address is
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

    data_out <= value;
  end process READBACK;
end architecture RTL;

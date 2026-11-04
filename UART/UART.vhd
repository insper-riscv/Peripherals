-- =============================================================================
-- Entity: UART
-- Description:
--   Memory-mapped wrapper around the OpenCores uart2bus physical UART blocks.
--   The command parser/bus-master portion of uart2bus is deliberately not used:
--   software running on the RV32 processor controls this peripheral directly.
--
-- Register map (word addresses):
--   0 TX_DATA W     [7:0] byte enqueued for transmission; reads return zero
--   1 RX_DATA R     [7:0] oldest received byte; reading dequeues it
--   2 STATUS  R/W1C bits 0 RX_VALID, 1 TX_READY, 2 RX_OVERRUN,
--                    3 TX_DROPPED, 4 RX_FULL, 5 TX_EMPTY, 6 TX_IDLE,
--                    15:8 RX_LEVEL, 23:16 TX_LEVEL
--   3 CONTROL R/W   bit 0 RX_IRQ_ENABLE
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART is
  generic (
    DATA_WIDTH    : natural  := 32;
    BAUD_FREQ     : natural  := 16#240#;
    BAUD_LIMIT    : natural  := 16#3AC9#;
    RX_FIFO_DEPTH : positive := 16;
    TX_FIFO_DEPTH : positive := 16
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

  signal phy_tx_data      : std_logic_vector(7 downto 0);
  signal phy_new_tx_data  : std_logic;
  signal phy_tx_busy      : std_logic;
  signal phy_rx_data      : std_logic_vector(7 downto 0);
  signal phy_new_rx_data  : std_logic;

  signal tx_fifo_push          : std_logic;
  signal tx_fifo_pop           : std_logic;
  signal tx_fifo_data          : std_logic_vector(7 downto 0);
  signal tx_fifo_push_accepted : std_logic;
  signal tx_fifo_pop_accepted  : std_logic;
  signal tx_fifo_full          : std_logic;
  signal tx_fifo_empty         : std_logic;
  signal tx_fifo_level         : natural range 0 to TX_FIFO_DEPTH;

  signal rx_fifo_push          : std_logic;
  signal rx_fifo_pop           : std_logic;
  signal rx_fifo_data          : std_logic_vector(7 downto 0);
  signal rx_fifo_push_accepted : std_logic;
  signal rx_fifo_pop_accepted  : std_logic;
  signal rx_fifo_full          : std_logic;
  signal rx_fifo_empty         : std_logic;
  signal rx_fifo_level         : natural range 0 to RX_FIFO_DEPTH;

  signal rx_overrun    : std_logic;
  signal tx_dropped    : std_logic;
  signal rx_irq_enable : std_logic;
begin
  assert DATA_WIDTH >= 24
    report "UART DATA_WIDTH must be at least 24"
    severity failure;

  assert BAUD_FREQ <= 16#FFF#
    report "UART BAUD_FREQ does not fit in 12 bits"
    severity failure;

  assert BAUD_LIMIT <= 16#FFFF#
    report "UART BAUD_LIMIT does not fit in 16 bits"
    severity failure;

  assert RX_FIFO_DEPTH <= 255
    report "UART RX_FIFO_DEPTH must fit in the 8-bit RX_LEVEL field"
    severity failure;

  assert TX_FIFO_DEPTH <= 255
    report "UART TX_FIFO_DEPTH must fit in the 8-bit TX_LEVEL field"
    severity failure;

  tx_fifo_push <= '1'
    when write = '1' and address = TX_DATA_ADDRESS
    else '0';
  tx_fifo_pop <= '1'
    when phy_tx_busy = '0' and tx_fifo_empty = '0'
    else '0';

  rx_fifo_push <= phy_new_rx_data;
  rx_fifo_pop <= '1'
    when read = '1' and address = RX_DATA_ADDRESS
    else '0';

  phy_tx_data     <= tx_fifo_data;
  phy_new_tx_data <= tx_fifo_pop_accepted;

  irq <= (not rx_fifo_empty) and rx_irq_enable;

  TX_FIFO : entity work.UART_FIFO
    generic map (
      DATA_WIDTH => 8,
      DEPTH      => TX_FIFO_DEPTH
    )
    port map (
      clock         => clock,
      clear         => clear,
      push          => tx_fifo_push,
      push_data     => data_in(7 downto 0),
      pop           => tx_fifo_pop,
      pop_data      => tx_fifo_data,
      push_accepted => tx_fifo_push_accepted,
      pop_accepted  => tx_fifo_pop_accepted,
      full          => tx_fifo_full,
      empty         => tx_fifo_empty,
      level         => tx_fifo_level
    );

  RX_FIFO : entity work.UART_FIFO
    generic map (
      DATA_WIDTH => 8,
      DEPTH      => RX_FIFO_DEPTH
    )
    port map (
      clock         => clock,
      clear         => clear,
      push          => rx_fifo_push,
      push_data     => phy_rx_data,
      pop           => rx_fifo_pop,
      pop_data      => rx_fifo_data,
      push_accepted => rx_fifo_push_accepted,
      pop_accepted  => rx_fifo_pop_accepted,
      full          => rx_fifo_full,
      empty         => rx_fifo_empty,
      level         => rx_fifo_level
    );

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

      -- The FIFO may accept a write while the physical transmitter is busy.
      -- A write is dropped only when no queue slot can be allocated.
      if tx_fifo_push = '1' and tx_fifo_push_accepted = '0' then
        tx_dropped <= '1';
      end if;

      -- A simultaneous accepted RX_DATA pop releases space for the new byte,
      -- so only a rejected physical receive event is an overrun.
      if rx_fifo_push = '1' and rx_fifo_push_accepted = '0' then
        rx_overrun <= '1';
      end if;
    end if;
  end process REGISTERS;

  READBACK : process (
    address,
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
    variable value : std_logic_vector(DATA_WIDTH - 1 downto 0);
  begin
    value := (others => '0');

    case address is
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
        value(15 downto 8) := std_logic_vector(to_unsigned(rx_fifo_level, 8));
        value(23 downto 16) := std_logic_vector(to_unsigned(tx_fifo_level, 8));

      when CONTROL_ADDRESS =>
        value(0) := rx_irq_enable;

      when others =>
        null;
    end case;

    data_out <= value;
  end process READBACK;
end architecture RTL;

-- =============================================================================
-- Entity: UART_FIFO
-- Description:
--   Single-clock synchronous FIFO used by the memory-mapped UART. The oldest
--   element is exposed combinationally so RX_DATA can preserve the peripheral
--   bus protocol: software samples the byte before the clock edge that pops it.
--
--   A pop from an empty FIFO is rejected. A push into a full FIFO is accepted
--   only when a pop is also accepted in the same cycle, reusing the slot that
--   is being released without changing the level.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity UART_FIFO is
  generic (
    DATA_WIDTH : positive := 8;
    DEPTH      : positive := 16
  );
  port (
    clock         : in  std_logic;
    clear         : in  std_logic;
    push          : in  std_logic;
    push_data     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    pop           : in  std_logic;
    pop_data      : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    push_accepted : out std_logic;
    pop_accepted  : out std_logic;
    full          : out std_logic;
    empty         : out std_logic;
    level         : out natural range 0 to DEPTH
  );
end entity UART_FIFO;

architecture RTL of UART_FIFO is
  type memory_type is array (0 to DEPTH - 1) of
    std_logic_vector(DATA_WIDTH - 1 downto 0);

  signal memory        : memory_type;
  signal read_pointer  : natural range 0 to DEPTH - 1;
  signal write_pointer : natural range 0 to DEPTH - 1;
  signal count         : natural range 0 to DEPTH;
  signal push_accept_i : std_logic;
  signal pop_accept_i  : std_logic;

  function next_pointer(pointer : natural) return natural is
  begin
    if pointer = DEPTH - 1 then
      return 0;
    end if;

    return pointer + 1;
  end function;
begin
  empty <= '1' when count = 0 else '0';
  full  <= '1' when count = DEPTH else '0';
  level <= count;

  pop_accept_i <= '1' when pop = '1' and count > 0 else '0';
  push_accept_i <= '1'
    when push = '1' and (count < DEPTH or pop_accept_i = '1')
    else '0';

  push_accepted <= push_accept_i;
  pop_accepted  <= pop_accept_i;

  pop_data <= memory(read_pointer) when count > 0 else (others => '0');

  STORAGE : process (clear, clock)
  begin
    if clear = '1' then
      read_pointer  <= 0;
      write_pointer <= 0;
      count         <= 0;
    elsif rising_edge(clock) then
      if push_accept_i = '1' then
        memory(write_pointer) <= push_data;
        write_pointer <= next_pointer(write_pointer);
      end if;

      if pop_accept_i = '1' then
        read_pointer <= next_pointer(read_pointer);
      end if;

      if push_accept_i = '1' and pop_accept_i = '0' then
        count <= count + 1;
      elsif push_accept_i = '0' and pop_accept_i = '1' then
        count <= count - 1;
      end if;
    end if;
  end process STORAGE;
end architecture RTL;

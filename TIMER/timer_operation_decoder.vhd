-- =============================================================================
-- Entity: TIMER_OPERATION_DECODER
-- Description:
--   Decodes read / write accesses for a memory-mapped Timer-/PWM-peripheral.
--   Generates one-hot write-enables, a counter-input selector, and a
--   read-multiplexer selector.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

-- -----------------------------------------------------------------------------
-- Entity Declaration
-- -----------------------------------------------------------------------------
entity timer_operation_decoder is
  port (
    -- Bus interface 
    i_address : in  std_logic_vector(2 downto 0);  -- 3-bit address from CPU
    i_write   : in  std_logic;                     -- Active-high write strobe
    i_read    : in  std_logic;                     -- Active-high read  strobe

    -- Vector of write enables (see bit-map below) 
    o_wr_en   : out std_logic_vector(6 downto 0);

    -- Counter input selector (cnt_sel)
    o_cnt_sel : out std_logic;

    -- Read selector for the peripheral read-back multiplexer
    o_rd_sel  : out std_logic_vector(2 downto 0)
  );
end entity timer_operation_decoder;

-- -----------------------------------------------------------------------------
-- Architecture Definition
-- -----------------------------------------------------------------------------
architecture rtl of timer_operation_decoder is

  -- ===========================================================================
  -- WRITE-ENABLE VECTOR BIT MAP  (wr_en)
  -- ===========================================================================
  --   Bit : Purpose
  --   ----+------------------------------------------------------------
  --    0  | WR_CONFIG      – Config register (start / mode / pwm_en / irq_mask)
  --    1  | WR_LOAD_TIMER  – Load current counter value
  --    2  | WR_RESET       – Reset the timer
  --    3  | WR_LOAD_TOP    – Load TOP register
  --    4  | WR_LOAD_DUTY   – Load DUTY-CYCLE register
  --    5  | WR_OVF_CLR     – Read-to-clear overflow status (pulse on read)
  --    6  | WR_PRESCALER   – Load prescaler value 
  -- ===========================================================================
  constant WR_CONFIG_I     : integer := 0;
  constant WR_LOAD_TIMER_I : integer := 1;
  constant WR_RESET_I      : integer := 2;
  constant WR_LOAD_TOP_I   : integer := 3;
  constant WR_LOAD_DUTY_I  : integer := 4;
  constant WR_OVF_CLR_I    : integer := 5;
  constant WR_PRESCALER    : integer := 6;

  -- ===========================================================================
  -- Configuration Register
  -- ===========================================================================
  constant ADDR_CONFIG      : std_logic_vector(2 downto 0) := "000";
  -- ===========================================================================
  -- Counter Register
  -- ===========================================================================
  constant ADDR_TIMER_LOAD  : std_logic_vector(2 downto 0) := "001";
  constant ADDR_TIMER_RESET : std_logic_vector(2 downto 0) := "010";
  -- ===========================================================================
  -- TOP Register
  -- ===========================================================================
  constant ADDR_TOP         : std_logic_vector(2 downto 0) := "011";
  -- ===========================================================================
  -- DUTY-CYCLE Register
  -- ===========================================================================
  constant ADDR_DUTY_CYCLE  : std_logic_vector(2 downto 0) := "100";
  -- ===========================================================================
  -- Overflow Status Flag
  --   Read-to-clear overflow status (pulse aligned with the READ)
  -- ===========================================================================
  constant ADDR_OVF_STATUS  : std_logic_vector(2 downto 0) := "101";
  -- ===========================================================================
  -- PWM Output
  -- ===========================================================================
  constant ADDR_PWM         : std_logic_vector(2 downto 0) := "110";
  -- ===========================================================================
  -- Prescaler Register
  -- ===========================================================================
  constant ADDR_PRESCALER   : std_logic_vector(2 downto 0) := "111";

begin

  -- -----------------------------------------------------------------------------
  -- WRITE DECODING : generate one-cycle write-enable strobes
  -- -----------------------------------------------------------------------------
  o_wr_en(WR_CONFIG_I)     <= i_write when i_address = ADDR_CONFIG      else '0';
  o_wr_en(WR_LOAD_TIMER_I) <= i_write when i_address = ADDR_TIMER_LOAD  else '0';
  o_wr_en(WR_RESET_I)      <= i_write when i_address = ADDR_TIMER_RESET else '0';
  o_wr_en(WR_LOAD_TOP_I)   <= i_write when i_address = ADDR_TOP         else '0';
  o_wr_en(WR_LOAD_DUTY_I)  <= i_write when i_address = ADDR_DUTY_CYCLE  else '0';
  o_wr_en(WR_PRESCALER)    <= i_write when i_address = ADDR_PRESCALER   else '0';

  -- Read-to-clear overflow flag (pulse aligned with the READ)
  o_wr_en(WR_OVF_CLR_I)    <= i_read  when i_address = ADDR_OVF_STATUS  else '0';

  -- -----------------------------------------------------------------------------
  -- COUNTER INPUT SELECTOR (cnt_sel)
  --   0 = use “counter + 1”
  --   1 = load external value (WR_LOAD_TIMER)
  -- -----------------------------------------------------------------------------
  o_cnt_sel <= '1' when (i_address = ADDR_TIMER_LOAD and i_write = '1') else '0';

  -- -----------------------------------------------------------------------------
  -- READ-BACK OPERATION: multiplexer selector (rd_sel)
  -- -----------------------------------------------------------------------------
  with i_address select
    o_rd_sel <= "000" when ADDR_TIMER_LOAD,     -- 000 = Current counter
              "000" when ADDR_TIMER_RESET,    -- 000 = Current counter
              "001" when ADDR_TOP,            -- 001 = TOP register
              "010" when ADDR_DUTY_CYCLE,     -- 010 = DUTY-CYCLE register
              "011" when ADDR_CONFIG,         -- 011 = CONFIG (control bits)
              "100" when ADDR_PWM,            -- 100 = PWM output
              "101" when ADDR_OVF_STATUS,     -- 101 = Overflow status (r-to-c)
              "110" when ADDR_PRESCALER,      -- 110 = Prescaler value
              "111" when others;              -- 111 = RESERVED / NOP

end architecture;

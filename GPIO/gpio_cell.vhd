-- =============================================================================
-- Entity: GPIO_CELL
-- Description:
--   Single-bit General-Purpose I/O cell. Interfaces a processor with a
--   bidirectional I/O pin, supporting direction control, output operations,
--   and interrupt configuration (masking, edge detection, and W1C clearing).
--   Provides a readback multiplexer for processor access to internal state.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;

-- -----------------------------------------------------------------------------
-- Entity Declaration
-- -----------------------------------------------------------------------------
entity gpio_cell is
  port (
    -- System interface
    i_clk : in  std_logic; -- System clock
    i_rst : in  std_logic; -- Global clear (asynchronous or synchronous)

    -- Data bus
    i_data_in  : in  std_logic; -- Data from processor (1-bit)
    o_data_out : out std_logic_vector (6 downto 0); -- Data to processor (1-bit)

    -- Control signals
    i_wr_signals : in std_logic_vector(6 downto 0); -- Write enable signals
    i_wr_op  : in std_logic_vector(1 downto 0); -- Output mode: LOAD, SET, CLEAR, TOGGLE

    -- Physical GPIO pin (bidirectional)
    io_gpio_pin : inout std_logic
  );
end entity;

-- -----------------------------------------------------------------------------
-- Architecture Definition
-- -----------------------------------------------------------------------------
architecture rtl of gpio_cell is
  
  -- -----------------------------------------------------------------------------
  -- Internal Registers
  -- -----------------------------------------------------------------------------
  signal dir_reg : std_logic; -- Direction register (input/output)
  signal out_reg : std_logic; -- Output register (data to GPIO pin)
  signal pin_input : std_logic; -- Synchronized input from GPIO pin
  signal mux_write : std_logic; -- Mux output for write operations
  signal irq_mask : std_logic; -- Interrupt mask register (global interrupt enable)
  signal irq_rise_mask : std_logic; -- Rising edge interrupt mask register
  signal irq_fall_mask : std_logic; -- Falling edge interrupt mask register
  signal irq_status : std_logic; -- Interrupt status register 
  -----------------------------------------------------------------------------
  -- Helper Signals
  -----------------------------------------------------------------------------
  signal prev_pin_input : std_logic; -- Previous value of GPIO pin (for edge detection)
  signal interrupt_logic : std_logic; -- Interrupt logic (for edge detection)
  signal mux_write_vector : std_logic_vector(0 downto 0); -- Intermediate vector for mux output
  -- Port-map actuals as signals: GHDL (VHDL-93/2008) requires a name or a
  -- globally static expression there, and these were expressions of signals.
  signal load_vector   : std_logic_vector(0 downto 0);
  signal toggle_vector : std_logic_vector(0 downto 0);
  signal out_enable    : std_logic;
  signal irq_clear     : std_logic;
  signal irq_set       : std_logic;
  constant SET_VECTOR   : std_logic_vector(0 downto 0) := "1";
  constant CLEAR_VECTOR : std_logic_vector(0 downto 0) := "0";
  -- Saída de 1 bit do registrador U_IRQ_STATUS, no formato de vetor do clearable_register.
  signal u_irq_status_q : std_logic_vector(0 downto 0);
  -- Dado de 1 bit com valor '1', usado como entrada do registrador de status.
  constant ONE_BIT : std_logic_vector(0 downto 0) := "1";

begin
  load_vector   <= (0 => i_data_in);
  toggle_vector <= (0 => not out_reg);
  out_enable    <= i_wr_signals(1) or (i_wr_signals(2) and i_data_in);
  irq_clear     <= i_rst or i_wr_signals(6);
  irq_set       <= interrupt_logic and irq_mask;

  -----------------------------------------------------------------------------
  -- Direction Register: Controls GPIO pin direction (input/output).
  -- 0 = input, 1 = output
  -----------------------------------------------------------------------------
  u_reg_dir : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(0), -- Enable write to direction register
        i_d      => i_data_in, -- Data to be written to direction register
        o_d      => dir_reg  -- Direction of GPIO pin (input/output)
    );

  -----------------------------------------------------------------------------
  -- Multiplexer for Write Operations.
  -- When selector 00 = LOAD, 01 = SET, 10 = CLEAR, 11 = TOGGLE
  -----------------------------------------------------------------------------
  u_mux_write : entity work.mux_4x1
    generic map (
      data_width => 1
    )
    port map (
      i_d0  => load_vector,
      i_d1  => SET_VECTOR,
      i_d2  => CLEAR_VECTOR,
      i_d3  => toggle_vector,
      i_sel => i_wr_op,
      o_d   => mux_write_vector
    );

  -- Unpack result from mux (mux_write is std_logic)
  mux_write <= mux_write_vector(0); -- Unpack 1-bit vector to std_logic

  
  -----------------------------------------------------------------------------
  -- Output Register: Holds the value to be sent to the GPIO pin.
  -- Enabled on load operations and when the bit is selected (data in = 1) for SET/CLEAR/TOGGLE.
  -----------------------------------------------------------------------------
  u_reg_out : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => out_enable, -- Load or Set/Clear/Toggle
        i_d      => mux_write, -- Data to be written to output register
        o_d      => out_reg -- Data to be sent to GPIO pin
    );

  -----------------------------------------------------------------------------
  -- Tristate Buffer: Connects output register to GPIO pin based on direction.
  -- If dir_reg = '1', buffer is enabled and out_reg is sent to gpio_pin.
  -- If dir_reg = '0', buffer is disabled and gpio_pin is in high-impedance state.
  -----------------------------------------------------------------------------
  u_gpio_buffer : entity work.tristate_buffer_1bit
    port map (
      i_d      => out_reg,
      i_enable => dir_reg,
      o_d      => io_gpio_pin
    );

  -----------------------------------------------------------------------------
  -- Synchronizer: Synchronizes the asynchronous GPIO pin input to the clock domain.
  -- This is necessary to avoid metastability issues when reading the GPIO pin.
  -----------------------------------------------------------------------------      
  u_sync : entity work.generic_synchronizer_1bit
    generic map (n => 2) -- Number of stages in the synchronizer
    port map (
        i_clk       => i_clk,
        i_async_in  => io_gpio_pin, -- Asynchronous input from GPIO pin
        o_sync_out  => pin_input -- Synchronized output to processor
    );

  -----------------------------------------------------------------------------
  -- Previous Pin Input Register: Holds the previous value of the GPIO pin.
  -- This is used for edge detection in the interrupt logic.
  -----------------------------------------------------------------------------
  u_reg_prev : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => '0', -- No reset
        i_enable => '1', -- Always enabled
        i_d      => pin_input, -- Synchronized input from GPIO pin
        o_d      => prev_pin_input -- Previous pin value
    );

  -----------------------------------------------------------------------------
  -- Interrupt Mask Register: Controls wether interrupts are enabled or disabled for this GPIO cell.
  -- If irq_mask = '1', interrupts are enabled. If irq_mask = '0', interrupts are disabled.
  -----------------------------------------------------------------------------
  u_irq_mask : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(3), -- Enable write to interrupt mask register
        i_d      => i_data_in, -- Data to be written to interrupt mask register
        o_d      => irq_mask -- Interrupt mask register
    );
  
  -----------------------------------------------------------------------------
  -- Interrupt Rising Edge Mask Register: Controls rising edge interrupt detection.
  -- If irq_rise_mask = '1', rising edge interrupts are enabled. If irq_rise_mask = '0', they are disabled.
  -----------------------------------------------------------------------------
  u_irq_rise : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(4), -- Enable write to rising edge mask register
        i_d      => i_data_in, -- Data to be written to rising edge mask register
        o_d      => irq_rise_mask -- Rising edge interrupt mask register
    );
  
  --------------------------------------------------------------------------
  -- Interrupt Falling Edge Mask Register: Controls falling edge interrupt detection.
  -- If irq_fall_mask = '1', falling edge interrupts are enabled. If irq_fall_mask = '0', they are disabled.
  --------------------------------------------------------------------------
  u_irq_fall : entity work.flip_flop
    port map (
        i_clk    => i_clk,
        i_rst    => i_rst,
        i_enable => i_wr_signals(5), -- Enable write to falling edge mask register
        i_d      => i_data_in, -- Data to be written to falling edge mask register
        o_d      => irq_fall_mask -- Falling edge interrupt mask register
    );
  
  -----------------------------------------------------------------------------
  -- Interrupt Logic: Detects rising and falling edges on the GPIO pin.
  -- Generates an interrupt signal if the corresponding mask is set.
  -- Rising edge: pin_input goes from 0 to 1 (prev_pin_input = 0, pin_input = 1)
  -- Falling edge: pin_input goes from 1 to 0 (prev_pin_input = 1, pin_input = 0)
  -----------------------------------------------------------------------------
  interrupt_logic <= (irq_rise_mask and (pin_input and not prev_pin_input)) or
                     (irq_fall_mask and (not pin_input and prev_pin_input)); -- Edge detection logic

  ----------------------------------------------------------------------------
  -- Interrupt Status Register: Holds the interrupt status for this GPIO cell.
  -- If irq_status = '1', an interrupt has occurred. If irq_status = '0', no interrupt.
  -- The status is cleared when the processor writes a '1' to the register (W1C).
  -- The interrupt status is set if the interrupt logic is high and the mask is enabled.
  ----------------------------------------------------------------------------
  u_irq_status : entity work.clearable_register
    generic map (
      data_width => 1
    )
    port map (
      i_clk    => i_clk,
      i_clear  => irq_clear,
      i_enable => irq_set,
      i_d      => ONE_BIT,
      o_d      => u_irq_status_q
    );
  irq_status <= u_irq_status_q(0);
  

  o_data_out(0) <= dir_reg; -- Read direction register
  o_data_out(1) <= out_reg; -- Read output register
  o_data_out(2) <= pin_input; -- Read GPIO pin input
  o_data_out(3) <= irq_mask; -- Read interrupt mask register
  o_data_out(4) <= irq_rise_mask; -- Read rising edge mask register
  o_data_out(5) <= irq_fall_mask; -- Read falling edge mask register
  o_data_out(6) <= irq_status; -- Read interrupt status register
end architecture;

-- =============================================================================
-- Entity: TIMER
-- Description: Timer with configuration register (includes IRQ mask)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library WORK;

entity TIMER is
    generic (
        -- Data Bus Width
        DATA_WIDTH : integer := 32
    );
    port (
        -- Clock Signal
        clock       : in  std_logic;
        -- Clear Signal
        clear       : in  std_logic; 
        -- Data Inputed from the Processor
        data_in     : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        -- GPIO Address accessed by the Processor
        address     : in  STD_LOGIC_VECTOR(2 downto 0);
        -- Write Signal
        write       : in  std_logic; 
        -- Read Signal
        read        : in  std_logic; 
        -- Data Outputed to the Processor
        data_out    : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        -- Interrupt Request Signal (active high)
        irq         : out std_logic;
        -- PWM Output Signal (Pulse Width Modulation)
        pwm        : out std_logic
    );
end entity;

architecture RTL of TIMER is
    -----------------------------------------------------------------------------
    -- Internal Control Signals
    -----------------------------------------------------------------------------
    signal wr_en   : std_logic_vector(6 downto 0); -- Write enable signals
    signal cnt_sel : std_logic;             -- Counter input selector
    signal rd_sel  : std_logic_vector(2 downto 0); -- Readback selector 

    -----------------------------------------------------------------------------
    -- Register Signals
    -----------------------------------------------------------------------------
    signal top_reg  : std_logic_vector(DATA_WIDTH-1 downto 0); -- Top register
    signal duty_reg : std_logic_vector(DATA_WIDTH-1 downto 0); -- Duty register
    signal prescaler_reg : std_logic_vector(DATA_WIDTH-1 downto 0); -- Prescaler register
    signal config_reg : std_logic_vector(3 downto 0); -- Configuration register (4 bits wide)

    -----------------------------------------------------------------------------
    -- State Signals
    -----------------------------------------------------------------------------
    signal start_signal : std_logic; -- Start/Stop signal for the timer
    signal mode_signal  : std_logic; -- Mode signal for the timer
    signal pwm_en       : std_logic; -- PWM enable signal
    signal overflow      : std_logic; -- Overflow signal (active high)
    signal overflow_prev   : std_logic;  -- registered copy of overflow
    signal overflow_pulse  : std_logic;  -- 1-cycle edge pulse
    signal irq_mask  : std_logic; -- IRQ mask register
    signal overflow_status : std_logic; -- Overflow status signal
    signal pwm_out       : std_logic; -- PWM output signal
    signal pwm_alu      : std_logic; -- PWM ALU output signal
    signal irq_vec       : std_logic_vector(0 downto 0); -- IRQ vector signal
    signal tick : std_logic; -- Tick signal for the prescaler

    ---------------------------------------------------------------------------
    -- Multiplexer Signals
    ---------------------------------------------------------------------------
    signal mux_cnt : std_logic_vector(DATA_WIDTH-1 downto 0); -- Mux output for cnt_sel
    signal mux_out : std_logic_vector(DATA_WIDTH-1 downto 0); -- Mux output for data_out
    signal configs_readback : std_logic_vector(DATA_WIDTH-1 downto 0); -- Config register output
    signal pwm_readback : std_logic_vector(DATA_WIDTH-1 downto 0); -- PWM readback signal
    signal overflow_readback : std_logic_vector(DATA_WIDTH-1 downto 0); -- Overflow readback signal

    ---------------------------------------------------------------------------
    -- Counter Signals
    ---------------------------------------------------------------------------
    signal counter : std_logic_vector(DATA_WIDTH-1 downto 0); -- Counter value
    signal next_counter : std_logic_vector(DATA_WIDTH-1 downto 0); -- Next counter value

    -- Port-map actuals as signals: GHDL (VHDL-93/2008) requires a name or a
    -- globally static expression there, and these were expressions of signals.
    signal counter_clear  : std_logic;
    signal counter_enable : std_logic;
    signal ovf_clear      : std_logic;
    signal irq_disabled   : std_logic_vector(0 downto 0);
    signal irq_enabled    : std_logic_vector(0 downto 0);
    signal pwm_inverted   : std_logic;
  -- Constante 1 usada como segundo operando do somador U_CONSTANT_ADDER.
  constant U_CONSTANT_ADDER_ONE : std_logic_vector(DATA_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(1, DATA_WIDTH));
  -- Saída de 1 bit do registrador U_IRQ_STATUS_REG, no formato de vetor do clearable_register.
  signal u_irq_status_reg_q : std_logic_vector(0 downto 0);
  -- Dado de 1 bit com valor '1', usado como entrada do registrador de status.
  constant ONE_BIT : std_logic_vector(0 downto 0) := "1";

  -- Palavra de zeros, a oitava entrada do multiplexador de leitura (sem registrador associado).
  constant ZERO_WORD : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');

begin
    counter_clear  <= clear or wr_en(2) or (overflow and not mode_signal);
    counter_enable <= wr_en(1) or (start_signal and tick and not (overflow and mode_signal));
    ovf_clear      <= clear or wr_en(5);
    irq_disabled   <= (0 => '0');
    irq_enabled    <= (0 => overflow_status);
    pwm_inverted   <= not pwm_alu;

    -------------------------------------------------------------------------------
    -- TIMER_OPERATION_DECODER  
    -------------------------------------------------------------------------------
    U_TIMER_OPERATION_DECODER : entity work.TIMER_OPERATION_DECODER
        port map (
            address => address,
            write   => write,
            read    => read,
            wr_en   => wr_en,
            cnt_sel => cnt_sel,
            rd_sel  => rd_sel
        );

    -------------------------------------------------------------------------------
    -- Prescaler Register
    -- This register holds the prescaler value for the timer.
    -- It is loaded with the data_in value when the wr_en(6) signal is high.
    -- The prescaler value is used to change the clock frequency for the timer.
    -- The prescaler register is 32 bits wide.
    -- It is cleared on system reset or when the prescaler register is written to.
    -------------------------------------------------------------------------------
    U_PRESCALER_REG : entity work.clearable_register
      generic map (
        data_width => 32
      )
      port map (
        i_clk    => clock,
        i_clear  => clear,
        i_enable => wr_en(6),
        i_d      => data_in,
        o_d      => prescaler_reg
      );
    -------------------------------------------------------------------------------
    -- Clock Prescaler
    -- This component generates a tick signal based on the prescaler value.
    -- The tick signal is generated when the prescaler counter matches the prescaler value.
    -- The prescaler is used to slow down the clock frequency for the timer.
    -- The prescaler is 32 bits wide. The frequency varies from 50 Mhz to 0.0116 Hz.
    -------------------------------------------------------------------------------
    U_CLOCK_PRESCALER : entity WORK.CLOCK_PRESCALER
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clock        => clock,
            clear        => clear,
            prescaler_in => prescaler_reg,
            tick         => tick
        );

    -------------------------------------------------------------------------------
    -- Configiration Register
    -- This register holds the configuration bits for the timer
    -- irq_mask, pwm_en, mode_signal, start_signal
    -- irq_mask: Interrupt request mask
    -- pwm_en: PWM enable signal
    -- mode_signal: Mode signal for the timer (e.g., hold mode/ wrap-around)
    -- start_signal: Start/Stop signal for the timer
    -- The register is 4 bits wide, with each bit representing a different configuration
    -- bit:
    --   0: start_signal
    --   1: mode_signal
    --   2: pwm_en
    --   3: irq_mask
    -------------------------------------------------------------------------------
    U_CONFIG_REG : entity work.clearable_register
      generic map (
        data_width => 4
      )
      port map (
        i_clk    => clock,
        i_clear  => clear,
        i_enable => wr_en(0),
        i_d      => data_in(3 downto 0),
        o_d      => config_reg
      );

    -- Unpack the config bits
    start_signal <= config_reg(0);
    mode_signal  <= config_reg(1);
    pwm_en       <= config_reg(2);
    irq_mask     <= config_reg(3);
    ---------------------------------------------------------------------------
    -- Mux Counter Selector
    -- Loads or increments the counter based on the cnt_sel signal.
    -- If cnt_sel is '1', the counter is loaded with the data_in value.
    -- If cnt_sel is '0', the counter is incremented by 1.
    ---------------------------------------------------------------------------
    U_MUX_CNT_SEL : entity work.mux_2x1
      generic map (
        data_width => DATA_WIDTH
      )
      port map (
        i_d0  => next_counter,
        i_d1  => data_in,
        i_sel => cnt_sel,
        o_d   => mux_cnt
      );

    ---------------------------------------------------------------------------
    -- Counter Register
    -- This register holds the current value of the timer counter.
    -- Clear signal resets the counter to zero. It clears on system reset, on timer reset or 
    -- when the overflow signal is high and the mode signal is auto-reset.
    -- Counter enabled on load or when the start signal is high and there is no overflow in hold mode. 
    ------------------------------------------------------------------------------
    U_COUNTER_REG : entity work.clearable_register
      generic map (
        data_width => DATA_WIDTH
      )
      port map (
        i_clk    => clock,
        i_clear  => counter_clear,
        i_enable => counter_enable,
        i_d      => mux_cnt,
        o_d      => counter
      );

    ----------------------------------------------------------------------------
    -- Constant Adder
    -- This adder is used to increment the counter by 1.
    ------------------------------------------------------------------------------
    U_CONSTANT_ADDER : entity work.adder
      generic map (
        data_width => DATA_WIDTH
      )
      port map (
        i_a => counter,
        i_b => U_CONSTANT_ADDER_ONE,
        o_d => next_counter
      );

    --------------------------------------------------------------------------
    -- Top Register
    -- It is used to set the maximum count value for the timer. As default, it is set to 0xFFFFFFFF and it clears to the same value.
    -- It is loaded with the data_in value when the wr_en(4) signal is high.
    --------------------------------------------------------------------------
    U_TOP_REG : entity work.clearable_register
      generic map (
        data_width  => DATA_WIDTH,
        clear_value => '1'
      )
      port map (
        i_clk    => clock,
        i_clear  => clear,
        i_enable => wr_en(3),
        i_d      => data_in,
        o_d      => top_reg
      );

    ---------------------------------------------------------------------------
    -- Overflow Detection Unity
    -- Overflow occurs when the counter reaches the top value.
    ---------------------------------------------------------------------------
    U_COUNTER_OVERFLOW : entity WORK.COUNTER_OVERFLOW
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            counter_value => counter, -- Current counter value
            top_value     => top_reg, -- Top register value
            overflow      => overflow -- Overflow signal (active high)
        );


    -- ============================================================================
    -- REGISTER THE PREVIOUS OVERFLOW
    -- ============================================================================
    U_OVF_PREV : entity WORK.flip_flop
        port map (
        i_clk    => clock,
        i_rst    => clear,
        i_enable => '1',          -- always capture
        i_d      => overflow,     -- current overflow level
        o_d      => overflow_prev -- previous cycle value
    );
    overflow_pulse <= overflow and not overflow_prev;
    ---------------------------------------------------------------------------
    -- Overflow Status Register
    -- This register holds the overflow status of the timer.
    -- It is cleared on read or when the overflow signal is high.
    ---------------------------------------------------------------------------
    U_IRQ_STATUS_REG : entity work.clearable_register
      generic map (
        data_width => 1
      )
      port map (
        i_clk    => clock,
        i_clear  => ovf_clear,
        i_enable => overflow_pulse,
        i_d      => ONE_BIT,
        o_d      => u_irq_status_reg_q
      );
    overflow_status <= u_irq_status_reg_q(0);

    ---------------------------------------------------------------------------
    -- MUX IRQ Selector
    -- IRQ signal is selected based on the IRQ mask value.
    -- If the IRQ mask is '1', the IRQ signal is asserted when overflow occurs.
    -- If the IRQ mask is '0', the IRQ signal is not asserted.
    -- This is used to enable or disable the overflow interrupt.
    -------------------------------------------------------------------------------
    U_MUX_IRQ_SEL : entity work.mux_2x1
      generic map (
        data_width => 1
      )
      port map (
        i_d0  => irq_disabled,
        i_d1  => irq_enabled,
        i_sel => irq_mask,
        o_d   => irq_vec
      );
    irq <= irq_vec(0); -- Assign the IRQ signal to the output

    ---------------------------------------------------------------------------
    -- Duty Register
    -- This register holds the duty cycle value for the PWM output.
    -- It is loaded with the data_in value when the wr_en(5) signal is high.
    -- The duty cycle value is used to control the width of the PWM pulse.
    ---------------------------------------------------------------------------
    U_DUTY_REG : entity work.clearable_register
      generic map (
        data_width => DATA_WIDTH
      )
      port map (
        i_clk    => clock,
        i_clear  => clear,
        i_enable => wr_en(4),
        i_d      => data_in,
        o_d      => duty_reg
      );

  ---------------------------------------------------------------------------
    -- PWM ALU
    -- This ALU is used to compare the current counter value with the duty cycle value.
    -- It outputs a signal indicating whether the counter is less than the duty cycle.
    -- This signal is used to control the PWM output.
    ---------------------------------------------------------------------------
    U_PWM_ALU : entity WORK.ALU_GE_UNSIGNED
        generic map (
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            source_1    => counter, -- Current counter value
            source_2    => duty_reg, -- Duty cycle value
            ge         => pwm_alu  -- PWM output signal (1 when counter < duty cycle)
        );

    ---------------------------------------------------------------------------
    -- PWM Tristate Buffer
    -- This buffer is used to control the PWM output signal.
    -- When the PWM enable signal is '1', the PWM output is driven by the PWM ALU.
    ---------------------------------------------------------------------------
    U_PWM_TRISTATE : entity work.tristate_buffer_1bit
      port map (
        i_d      => pwm_inverted,
        i_enable => pwm_en,
        o_d      => pwm_out
      );
    pwm <= pwm_out; -- Assign the PWM output signal to the output

    ---------------------------------------------------------------------------
    -- Mux Output Selector
    -- This multiplexer selects the output data based on the read signal and the rd_sel signal.
    -- If read is '1', the output is selected based on the rd_sel signal.
    -- If read is '0', the output is selected based on the cnt_sel signal.
    ---------------------------------------------------------------------------
    configs_readback <= (31 downto 4 => '0') & (irq_mask & pwm_en & mode_signal & start_signal); -- Concatenate the registers for the multiplexer
    pwm_readback <= (31 downto 1 => '0') & pwm_out; -- Concatenate the PWM output for the multiplexer
    overflow_readback <= (31 downto 1 => '0') & overflow_status; -- Concatenate the overflow status for the multiplexer
    U_MUX_OUT_SEL : entity work.mux_8x1
      generic map (
        data_width => DATA_WIDTH
      )
      port map (
        i_d0  => counter,
        i_d1  => top_reg,
        i_d2  => duty_reg,
        i_d3  => configs_readback,
        i_d4  => pwm_readback,
        i_d5  => overflow_readback,
        i_d6  => prescaler_reg,
        i_d7  => ZERO_WORD,
        i_sel => rd_sel,
        o_d   => data_out
      );

end architecture;
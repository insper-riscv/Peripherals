-- =============================================================================
-- Entity: GPIO
-- Description:
--   Top-level General-Purpose I/O module interfacing the processor with a 
--   set of bidirectional I/O pins. It integrates multiple GPIO_CELL instances,
--   a decoder for memory-mapped operations, and a multiplexer for data readback.
--   Supports direction control, output operations, and interrupt configuration.
--   Internal logic is based on DATA_WIDTH.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;

-- -----------------------------------------------------------------------------
-- Entity Declaration
-- -----------------------------------------------------------------------------
entity gpio is
    generic (
        --! Data width of processor bus
        data_width : natural := 32
    );
    port (
        --! Clock Signal
        i_clk       : in  std_logic;

        --! Global Reset
        i_rst       : in  std_logic; 

        --! Data input from processor
        i_data_in     : in  std_logic_vector(data_width-1 downto 0);

        --! Address accessed by the processor
        i_address     : in  std_logic_vector(3 downto 0);

        --! Write enable signal
        i_write       : in  std_logic; 

        --! Read enable signal
        i_read        : in  std_logic; 

        --! Data output to processor (adjusted to DATA_WIDTH)
        o_data_out    : out std_logic_vector(data_width-1 downto 0);

        --! Interrupt request signal (active high)
        o_irq         : out std_logic;

        --! Bidirectional GPIO pins
        io_gpio_pins   : inout std_logic_vector(data_width-1 downto 0)
    );
end gpio;

-- -----------------------------------------------------------------------------
-- Architecture Definition
-- -----------------------------------------------------------------------------
architecture rtl of gpio is

    -----------------------------------------------------------------------------
    -- Internal Control Signals
    -----------------------------------------------------------------------------
    signal wr_en   : std_logic_vector(6 downto 0); -- Write enable signals
    signal wr_op   : std_logic_vector(1 downto 0); -- Write operation
    signal rd_sel  : std_logic_vector(2 downto 0); -- Readback selector

    -----------------------------------------------------------------------------
    -- Internal Register Banks (based on DATA_WIDTH)
    -----------------------------------------------------------------------------
    signal dir_reg         : std_logic_vector(data_width-1 downto 0);
    signal out_reg         : std_logic_vector(data_width-1 downto 0);
    signal pins_input      : std_logic_vector(data_width-1 downto 0);
    signal irq_mask        : std_logic_vector(data_width-1 downto 0);
    signal irq_rise_mask   : std_logic_vector(data_width-1 downto 0);
    signal irq_fall_mask   : std_logic_vector(data_width-1 downto 0);
    signal irq_status      : std_logic_vector(data_width-1 downto 0);

    -----------------------------------------------------------------------------
    -- Internal Signal for GPIO_CELL Data Output
    -----------------------------------------------------------------------------
    type dout_array_t is array (0 to data_width - 1) of std_logic_vector(6 downto 0);
    signal dout_array : dout_array_t;

    -----------------------------------------------------------------------------
    -- Internal Signal for Readback Multiplexer
    -----------------------------------------------------------------------------
    signal selected_read : std_logic_vector(data_width-1 downto 0); -- Readback data
    constant ZERO_VECTOR : std_logic_vector(data_width-1 downto 0) := (others => '0'); -- Zero vector for unused readback

begin

    -----------------------------------------------------------------------------
    -- GPIO Operation Decoder
    -----------------------------------------------------------------------------
    u_gpio_operation_decoder : entity work.gpio_operation_decoder
        port map (
            i_address => i_address,
            i_write   => i_write,
            i_read    => i_read,
            o_wr_en   => wr_en,
            o_wr_op   => wr_op,
            o_rd_sel  => rd_sel
        );

    -----------------------------------------------------------------------------
    -- GPIO_CELL Array Instantiation
    -----------------------------------------------------------------------------
    gen_cells : for i in 0 to data_width - 1 generate
    begin
        gpio_cell_i : entity work.gpio_cell
            port map (
                i_clk      => i_clk,
                i_rst      => i_rst,
                i_data_in    => i_data_in(i),
                o_data_out   => dout_array(i),
                i_wr_signals => wr_en,
                i_wr_op      => wr_op,
                io_gpio_pin   => io_gpio_pins(i)
            );

        dir_reg(i)        <= dout_array(i)(0);
        out_reg(i)        <= dout_array(i)(1);
        pins_input(i)     <= dout_array(i)(2);
        irq_mask(i)       <= dout_array(i)(3);
        irq_rise_mask(i)  <= dout_array(i)(4);
        irq_fall_mask(i)  <= dout_array(i)(5);
        irq_status(i)     <= dout_array(i)(6);
    end generate;

    -----------------------------------------------------------------------------
    -- Readback Multiplexer
    -----------------------------------------------------------------------------
    read_mux : entity work.mux_8x1
      generic map (
        data_width => data_width
      )
      port map (
        i_d0  => dir_reg,
        i_d1  => out_reg,
        i_d2  => pins_input,
        i_d3  => irq_status,
        i_d4  => irq_mask,
        i_d5  => irq_rise_mask,
        i_d6  => irq_fall_mask,
        i_d7  => ZERO_VECTOR,
        i_sel => rd_sel,
        o_d   => selected_read
      );
    o_data_out <= selected_read;
    -----------------------------------------------------------------------------
    -- Interrupt Generation Logic. 
    -- IRQ is asserted if any of the interrupt status bits are set (Reduce Or Operation).
    -----------------------------------------------------------------------------
    o_irq <= '1' when irq_status /= ZERO_VECTOR else '0';

end architecture;
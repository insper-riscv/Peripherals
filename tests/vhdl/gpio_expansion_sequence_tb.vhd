-- Regression for expansion connectors with unassigned physical pins.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.config_pkg.all;

entity gpio_expansion_sequence_tb is
end entity;

architecture test of gpio_expansion_sequence_tb is
    -- Deliberately ascending: bit-string actuals need not be descending.
    constant DIRECTIONS : std_logic_vector(0 to 15) := x"8000";
    constant POLARITIES : std_logic_vector(0 to 7) := x"80";
    type sequence_t is array (0 to 7) of natural;
    constant PHASES : sequence_t := (1, 3, 2, 6, 4, 12, 8, 9);
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal data_in : word_t := (others => '0');
    signal address : std_logic_vector(3 downto 0) := (others => '0');
    signal wr : std_logic := '0';
    signal pins : std_logic_vector(7 downto 0);
begin
    clk <= not clk after 10 ns;

    dut : entity work.gpio
        generic map (
            pin_count => 8,
            group_count => 1,
            member_count => 4,
            group_sizes => x"04",
            group_members => x"06040200",
            pin_dirs => DIRECTIONS,
            pin_active_low => POLARITIES
        )
        port map (
            i_clk => clk,
            i_rst => rst,
            i_data_in => data_in,
            i_address => address,
            i_write => wr,
            i_read => '0',
            o_data_out => open,
            o_irq => open,
            io_gpio_pins => pins
        );

    stimulus : process
        procedure write_word(index : natural; value : natural) is
        begin
            wait until falling_edge(clk);
            address <= std_logic_vector(to_unsigned(index, address'length));
            data_in <= std_logic_vector(to_unsigned(value, data_in'length));
            wr <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            wr <= '0';
        end procedure;

        procedure check_phase(value : natural) is
            variable bits : unsigned(3 downto 0);
        begin
            write_word(1, value);
            bits := to_unsigned(value, bits'length);
            for k in 0 to 3 loop
                assert pins(2 * k) = bits(k)
                    report "Wrong logical-to-physical GPIO phase" severity failure;
            end loop;
            assert pins(7) = '1'
                report "Unused active-low output was not inactive" severity failure;
            assert pins(1) = 'Z' and pins(3) = 'Z' and pins(5) = 'Z'
                report "Unassigned bidirectional pins were driven" severity failure;
        end procedure;
    begin
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        rst <= '0';
        write_word(0, 15);
        for k in PHASES'range loop
            check_phase(PHASES(k));
        end loop;
        for k in PHASES'reverse_range loop
            check_phase(PHASES(k));
        end loop;
        check_phase(0);
        report "GPIO expansion: forward/reverse half-steps and release PASS";
        std.env.stop;
        wait;
    end process;
end architecture;

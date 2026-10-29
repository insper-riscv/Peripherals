-- =============================================================================
-- Entity: GENERIC_SYNCHRONIZER_1BIT
-- Description: N‑stage synchronizer for a single asynchronous bit.
--              Each stage is a GENERIC_FLIP_FLOP.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity generic_synchronizer_1bit is
    generic (
        n : natural := 2           -- number of synchronizing stages (≥ 2)
    );
    port (
        i_clk    : in  std_logic;  -- destination clock domain
        i_async_in : in  std_logic;  -- asynchronous input bit
        o_sync_out : out std_logic   -- synchronized output bit
    );
end entity generic_synchronizer_1bit;

-- -----------------------------------------------------------------------------
-- Architecture
-- -----------------------------------------------------------------------------
architecture rtl of generic_synchronizer_1bit is

    -- Pipeline of N + 1 single‑bit stages (stage 0 holds the async input)
    type sync_array_t is array (0 to n) of std_logic;
    signal sync_stages : sync_array_t;

begin
    ---------------------------------------------------------------------------
    -- Stage‑0 : tie the raw asynchronous signal to the pipeline
    ---------------------------------------------------------------------------
    sync_stages(0) <= i_async_in;

    ---------------------------------------------------------------------------
    -- Stages 1 .. N : instantiate a flip‑flop for each stage
    ---------------------------------------------------------------------------
    gen_stage : for i in 1 to n generate
        ff : entity work.flip_flop
            port map (
                i_clk    => i_clk,
                i_rst    => '0',            -- no reset
                i_enable => '1',            -- always enabled
                i_d      => sync_stages(i-1),
                o_d      => sync_stages(i)
            );
    end generate gen_stage;

    ---------------------------------------------------------------------------
    -- Output : last stage of the pipeline
    ---------------------------------------------------------------------------
    o_sync_out <= sync_stages(n);

end architecture rtl;

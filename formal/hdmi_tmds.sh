# Proofs of the HDMI output with the TMDS transmitter wired straight to the FPGA (hdmi_tmds_tx over hdmi_tx and
# tmds_tx), sourced by formal/run.sh and so using its helpers (build, prove, expect, mutant) and variables. The
# three clocks of the wrapper are free, and the proof states what the wrapper itself wires.
for n in video_dpram video_regs; do path_of[$n]="$root/src/video/soc/$n.vhd"; done
for n in hdmi_scanout hdmi_out hdmi_tx hdmi_tmds_tx; do path_of[$n]="$root/src/HDMI/soc/$n.vhd"; done
path_of[tmds_serializer]="$root/src/HDMI/tmds/tmds_serializer.vhd"
# The DDR register of the simulation uses both clock edges, which Yosys does not synthesize: the proofs use a
# register of the rising edge only, as they state the wiring of the wrapper and not the timing of the pins.
path_of[tmds_ddr_out]="$out/tmds_ddr_out_formal.vhd"
cat > "${path_of[tmds_ddr_out]}" <<'EOV'
library ieee;
use ieee.std_logic_1164.all;

entity tmds_ddr_out is
    generic (
        width         : positive := 4;
        device_family : string   := "Cyclone 10 LP"
    );
    port (
        i_clk : in    std_logic;
        i_d_h : in    std_logic_vector(width - 1 downto 0);
        i_d_l : in    std_logic_vector(width - 1 downto 0);
        o_q   : out   std_logic_vector(width - 1 downto 0)
    );
end entity tmds_ddr_out;

architecture formal of tmds_ddr_out is

    signal pin : std_logic_vector(width - 1 downto 0) := (others => '0');

begin

    p_reg : process (i_clk) is
    begin

        if rising_edge(i_clk) then
            pin <= i_d_h;
        end if;

    end process p_reg;

    o_q <= pin;

end architecture formal;
EOV
path_of[tmds_tx]="$root/src/HDMI/tmds/tmds_tx.vhd"

echo "hdmi_tmds_tx"
ht_srcs=(config_pkg video_consts video_timing video_dpram video_regs hdmi_consts hdmi_i2c_writer hdmi_init_seq hdmi_scanout hdmi_out hdmi_regs hdmi_tx tmds_consts tmds_encoder tmds_serializer tmds_ddr_out tmds_tx hdmi_tmds_tx)
htgen=(-gaddr_width=11 -gfb_width=4 -gfb_height=2 -gscale=2 -gh_visible=10 -gh_front_porch=1 -gh_sync=2 -gh_back_porch=1 -gv_visible=6 -gv_front_porch=1 -gv_sync=1 -gv_back_porch=1)
htp="$f/hdmi_tmds_tx_props.sv"
mut_expose=()
multiclock=1
build hdmi_tmds_tx hdmitmds "${ht_srcs[@]}" -- "${htgen[@]}"
expect "status bit 0 is the hot plug pin through the two-stage synchronizer of the system clock, and the other bits of the status word are zero without the ADV7513 sequencer (bounded, free clocks)" PASS "$(prove hdmitmds.v "$htp" bmc 12 '' hdmitmds_safety)"
expect "cover: the status word reads the pin as 1 and as 0 after it was 1" PASS "$(prove hdmitmds.v "$htp" cover 12 '-DCOVER' hdmitmds_cover)"

# Mutants: each defect must make a proof fail.
mutant hdmi_tmds_tx "$htp" hdmi_tmds_tx '' hdmitmds_pin_tied "s/i_tx_int      => i_hpd,/i_tx_int      => '0',/" 12 "${ht_srcs[@]}" -- "${htgen[@]}"
mutant hdmi_tmds_tx "$htp" hdmi_tmds_tx '' hdmitmds_pin_inverted "s/int_active_low  => false/int_active_low  => true/" 12 "${ht_srcs[@]}" -- "${htgen[@]}"
multiclock=0

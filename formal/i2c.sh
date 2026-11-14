# Proofs of the I2C master (line state machine and register block), sourced by formal/run.sh and so using its helpers
# (build, prove, expect, mutant) and variables.
echo "i2c_core"
for n in i2c_consts i2c_core i2c_master; do path_of[$n]="$root/src/I2C/soc/$n.vhd"; done
i2c_core_srcs=(i2c_core)
i2c_master_srcs=(config_pkg i2c_consts i2c_core i2c_master)
icp="$f/i2c_core_props.sv"
mut_expose=()
build i2c_core i2ccore "${i2c_core_srcs[@]}" --
expect "the done pulse lasts one cycle and ends the command; reset, abort and disabled release both lines; the line state is idle or SCL held low between commands; no arbitration loss on lines it alone drives (bounded, 60 cycles)" PASS "$(prove i2ccore.v "$icp" bmc 60 '' i2ccore_safety)"
expect "cover: a start and a stop complete a transaction, and a sent byte gets a NACK" PASS "$(prove i2ccore.v "$icp" cover 220 '-DCOVER' i2ccore_cover)"

echo "i2c_master"
i2c_exp=(ctrl_enable irq_done_en irq_err_en divider:15 tx_data:7 st_done st_nack st_arb_lost st_rejected core_busy core_active core_done core_nack core_arb_lost core_rx:7)
i2c_gen=(-gclk_freq=100 -gscl_freq=5)
imp="$f/i2c_master_props.sv"
mut_expose=("${i2c_exp[@]}")
build i2c_master i2cm "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
expect "registers, sticky bits, the read of every address, the interrupt and the released lines follow the model (bounded, 14 cycles)" PASS "$(prove i2cm.v "$imp" bmc 14 '' i2cm_safety)"
expect "cover: an accepted and a refused command, an error interrupt and a clear of a sticky bit are reachable" PASS "$(prove i2cm.v "$imp" cover 14 '-DCOVER' i2cm_cover)"
expect "cover: a command ends, its done interrupt rises and the status read shows done with busy clear" PASS "$(prove i2cm.v "$imp" cover 40 '-DCOVER_DONE' i2cm_cover_done)"

# Mutants: each defect must make a proof fail.
mutant i2c_master "$imp" i2c_master '' i2cm_clear_ignored "s/st_done <= st_done and not i_data_in(ST_DONE_BIT);/st_done <= st_done;/" 44 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_done_mask_ignored "s/(st_done = '1' and irq_done_en = '1')/(st_done = '1')/" 44 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_error_mask_ignored "s/and irq_err_en = '1')/)/" 14 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_divider_unclamped "s/divider <= std_logic_vector(to_unsigned(MIN_DIVIDER, 16));/divider <= i_data_in(15 downto 0);/" 14 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_reject_not_flagged "s/st_rejected <= '1';/null;/" 14 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_busy_hides_done "s/<= core_busy or core_done;/<= core_busy;/" 40 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_read_ungated "s/read_word when i_read = '1' else/read_word when true else/" 14 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_command_while_busy "s/ctrl_enable = '1' and core_busy = '0'/ctrl_enable = '1'/" 14 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"
mutant i2c_master "$imp" i2c_master '' i2cm_tx_address "s/tx_data <= i_data_in(7 downto 0);/tx_data <= i_data_in(8 downto 1);/" 14 "${i2c_master_srcs[@]}" -- "${i2c_gen[@]}"

mut_expose=()
mutant i2c_core "$icp" i2c_core '' i2ccore_done_stuck "s/^ done_pulse <= '0';/ null;/" 60 "${i2c_core_srcs[@]}" --
mutant i2c_core "$icp" i2c_core '' i2ccore_start_not_active "s/bus_active <= '1';/bus_active <= '0';/" 60 "${i2c_core_srcs[@]}" --
mutant i2c_core "$icp" i2c_core '' i2ccore_arb_always "s/if i_sda = '0' then/if i_sda = '1' then/" 60 "${i2c_core_srcs[@]}" --

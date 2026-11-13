# Proofs of the LCD controller (registers and bus physical layer), sourced by formal/run.sh and so using its
# helpers (build, prove, expect, mutant) and variables. The write queue is the uart_fifo, proved with the UART.
echo "lcd_regs"
for n in lcd_consts lcd_regs lcd_phy; do path_of[$n]="$root/src/LCD/soc/$n.vhd"; done
lcdr_srcs=(lcd_consts lcd_regs)
lcdr_gen=(-gfifo_depth=3 -gdelay_reset=5 -gdelay_long_reset=9)
lrp="$f/lcd_regs_props.sv"
mut_expose=(); mut_open=0
build lcd_regs lcdr "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
expect "CONTROL, DELAY and DELAY_LONG keep what is written and reset to their values; DROPPED and TIMEOUT rise on their events and fall only by writing 1 (an event wins over the clear); the push is only a write to COMMAND or DATA with RS from the address; the IRQ is the empty queue enabled and not initializing; every address reads as the model (bounded, 14 cycles, 3 words)" PASS "$(prove lcdr.v "$lrp" bmc 14 '' lcdr_safety)"
expect "cover: DROPPED set then cleared, TIMEOUT set, the IRQ high, and the delays changed are reachable" PASS "$(prove lcdr.v "$lrp" cover 14 '-DCOVER' lcdr_cover)"
build lcd_regs lcdr_norw "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}" -ghas_rw=false
expect "without RW the polling bit resets to zero and cannot be set (bounded, 14 cycles)" PASS "$(prove lcdr_norw.v "$lrp" bmc 14 '-DNORW' lcdr_norw_safety)"

echo "lcd_phy"
lcdp_srcs=(lcd_consts lcd_phy)
lcdp_gen=(-gsetup_cycles=2 -gpulse_cycles=3 -ghold_cycles=2 -gtimeout_cycles=8)
lpp="$f/lcd_phy_props.sv"
build lcd_phy lcdp "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
expect "no bus conflict, lines steady while EN is high, setup before and hold after EN, EN high for the pulse time, the write shows the accepted RS and byte, and a fixed-delay operation lasts setup + pulse + hold + delay cycles (bounded, 40 cycles)" PASS "$(prove lcdp.v "$lpp" bmc 40 '' lcdp_safety)"
expect "with the busy flag low the single read doubles the operation and there is no timeout (bounded, 40 cycles)" PASS "$(prove lcdp.v "$lpp" bmc 40 '-DBUSY0' lcdp_busy0)"
expect "with the busy flag stuck high the layer reads twice, gives up with a timeout and returns to idle (bounded, 60 cycles)" PASS "$(prove lcdp.v "$lpp" bmc 60 '-DBUSY1' lcdp_busy1)"
expect "cover: a data write, a busy read, a timeout and the longest fixed delay are reachable" PASS "$(prove lcdp.v "$lpp" cover 60 '-DCOVER' lcdp_cover)"
expect "cover under the stuck busy flag: the timeout is reachable" PASS "$(prove lcdp.v "$lpp" cover 60 '-DBUSY1 -DCOVER' lcdp_cover_busy1)"

# Mutants: each defect must make a proof fail.
mutant lcd_regs "$lrp" lcd_regs '' lcdr_dropped_ignored "s/if push = '1' and i_push_accepted = '0' then/if false then/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_event_loses_to_clear "s/if i_timeout = '1' then/if i_timeout = '1' and not (i_write = '1' and i_address = STATUS_ADDRESS) then/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_timeout_wrong_bit "s/if i_data_in(STATUS_TIMEOUT) = '1' then/if i_data_in(STATUS_DROPPED) = '1' then/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_irq_ignores_init "s/i_fifo_empty and not i_init_busy/i_fifo_empty/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_irq_mask_ignored "s/o_irq <= irq_enable and/o_irq <= '1' and/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_rs_always_data "s/o_push_rs <= '1' when i_address = DATA_ADDRESS else '0';/o_push_rs <= '1';/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_push_any_write "s/when i_write = '1' and (i_address = COMMAND_ADDRESS or i_address = DATA_ADDRESS) else/when i_write = '1' else/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_control_bit_swapped "s/lcd_on   <= i_data_in(CONTROL_LCD_ON);/lcd_on   <= i_data_in(CONTROL_BACKLIGHT);/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_lcd_on_reset "s/lcd_on      <= '1';/lcd_on      <= '0';/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '-DNORW' lcdr_poll_ignores_rw "s/if has_rw then\$/if true then/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}" -ghas_rw=false
mutant lcd_regs "$lrp" lcd_regs '' lcdr_busy_ignores_queue "s/i_phy_busy or i_init_busy or not i_fifo_empty/i_phy_busy or i_init_busy/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_delay_long_address "s/if i_write = '1' and i_address = DELAY_LONG_ADDRESS then/if i_write = '1' and i_address = DELAY_ADDRESS then/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"
mutant lcd_regs "$lrp" lcd_regs '' lcdr_level_dropped "s/to_unsigned(i_fifo_level, LEVEL_BITS)/to_unsigned(0, LEVEL_BITS)/" 14 "${lcdr_srcs[@]}" -- "${lcdr_gen[@]}"

mutant lcd_phy "$lpp" lcd_phy '' lcdp_hold_short "s/count <= phase_count(hold_cycles);/count <= phase_count(setup_cycles - 1);/" 40 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
mutant lcd_phy "$lpp" lcd_phy '' lcdp_oe_stays "s/oe_reg <= '0';/oe_reg <= '1';/" 40 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
mutant lcd_phy "$lpp" lcd_phy '' lcdp_pulse_short "s/count  <= phase_count(pulse_cycles);\$/count  <= phase_count(hold_cycles);/" 40 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
mutant lcd_phy "$lpp" lcd_phy '' lcdp_rs_not_latched "s/rs_reg    <= i_rs;/rs_reg    <= '0';/" 40 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
mutant lcd_phy "$lpp" lcd_phy '' lcdp_delay_off_by_one "s/count <= delay_reg - 1;/count <= delay_reg;/" 40 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
mutant lcd_phy "$lpp" lcd_phy '' lcdp_rw_stays "s/rw_reg    <= '0';\$/rw_reg    <= '1';/" 40 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
mutant lcd_phy "$lpp" lcd_phy '-DBUSY1' lcdp_no_timeout "s/if busy_seen = '1' and poll_left \/= 0 then/if busy_seen = '1' then/" 60 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"
mutant lcd_phy "$lpp" lcd_phy '-DBUSY0' lcdp_busy_inverted "s/busy_seen <= i_busy_flag;/busy_seen <= not i_busy_flag;/" 40 "${lcdp_srcs[@]}" -- "${lcdp_gen[@]}"

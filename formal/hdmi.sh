# Proofs of the HDMI output (timing generator, register block, I2C writer and initialization sequencer),
# sourced by formal/run.sh and so using its helpers (build, prove, expect, mutant) and variables.
path_of[video_consts]="$root/src/video/soc/video_consts.vhd"
path_of[video_timing]="$root/src/video/soc/video_timing.vhd"
for n in hdmi_consts hdmi_regs; do path_of[$n]="$root/src/HDMI/soc/$n.vhd"; done
for n in hdmi_i2c_writer hdmi_init_seq; do path_of[$n]="$root/src/HDMI/adv7513/$n.vhd"; done

echo "hdmi_timing"
tim_srcs=(video_timing)
tim_exp=(h_cnt:3 v_cnt:3 fb_x:0 x_sub:0 fb_y:0 y_sub:0)
tgen=(-gfb_width=2 -gfb_height=2 -gscale=2 -gh_visible=6 -gh_front_porch=2 -gh_sync=3 -gh_back_porch=4 -gv_visible=5 -gv_front_porch=1 -gv_sync=2 -gv_back_porch=3)
tp="$f/hdmi_timing_props.sv"
mut_expose=("${tim_exp[@]}"); mut_open=0
build video_timing hdmitim "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
expect "HS, VS, visible area, image, coordinates and the registered frame outputs follow the counters of the generics; the counters are the model (induction)" PASS "$(prove hdmitim.v "$tp" prove 3 '-DINVARIANT' hdmitim_safety)"
expect "measured on the outputs only: HS every line, VS every frame, HS and VS pulse widths, DE width and the visible lines per frame (bounded, 280 cycles)" PASS "$(prove hdmitim.v "$tp" bmc 280 '-DMEASURE' hdmitim_measure)"
expect "cover: the end of the VS pulse and the last pixel of the image are reachable" PASS "$(prove hdmitim.v "$tp" cover 140 '-DCOVER' hdmitim_cover)"
build video_timing hdmitim_neg "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=false -gv_sync_positive=false
expect "negative polarity of both syncs: the same model with the pulse at the low level (induction)" PASS "$(prove hdmitim_neg.v "$tp" prove 3 '-DINVARIANT -DHPOS=0 -DVPOS=0' hdmitim_neg_safety)"
expect "negative polarity, measured on the outputs only (bounded, 280 cycles)" PASS "$(prove hdmitim_neg.v "$tp" bmc 280 '-DMEASURE -DHPOS=0 -DVPOS=0' hdmitim_neg_measure)"

echo "hdmi_regs"
reg_srcs=(video_consts hdmi_consts hdmi_regs)
reg_exp=(irq_en:1 irq_pend:1 vblank_prev int_prev seq_start_q)
rgen=(-gaddr_width=11 -ginit_entries=4 -gmode_id=4 -gpixel_clock_khz=74250)
rp="$f/hdmi_regs_props.sv"
mut_expose=("${reg_exp[@]}")
build hdmi_regs hdmiregs "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
expect "mask, pending (events, write-one-to-clear, event wins), IRQ, restart pulse and the read of every word follow the contract (induction)" PASS "$(prove hdmiregs.v "$rp" prove 3 '' hdmiregs_safety)"
expect "cover: a frame interrupt, a pin interrupt, a clear, both pending and the restart pulse are reachable" PASS "$(prove hdmiregs.v "$rp" cover 12 '-DCOVER' hdmiregs_cover)"
build hdmi_regs hdmiregs_off "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=false
expect "without the sequencer the restart pulse never leaves and the status says so (induction)" PASS "$(prove hdmiregs_off.v "$rp" prove 3 '-DINITOFF' hdmiregs_off_safety)"

echo "hdmi_init_seq"
seq_srcs=(hdmi_consts hdmi_init_seq)
sgen=(-ginit_table=98030100AF16)
sp="$f/hdmi_init_seq_props.sv"
mut_expose=()
build hdmi_init_seq hdmiseq "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
expect "auto start: the table goes out in order, one request at a time, counters and done follow the ideal list, restart only when stopped (bounded, 40 cycles, 3 entries)" PASS "$(prove hdmiseq.v "$sp" bmc 40 '-DAUTO' hdmiseq_safety)"
expect "cover: a sequence ends with a NACK counted and a second one runs to the end" PASS "$(prove hdmiseq.v "$sp" cover 40 '-DAUTO -DCOVER' hdmiseq_cover)"
build hdmi_init_seq hdmiseq_audio "${seq_srcs[@]}" -- -ginit_table=9803 -gaudio_table=0100AF16 -gauto_start=true
expect "audio table: the entries of the init table go out first and those of the audio table right after, one list of three entries (bounded, 40 cycles)" PASS "$(prove hdmiseq_audio.v "$sp" bmc 40 '-DAUTO' hdmiseq_audio_safety)"
build hdmi_init_seq hdmiseq_manual "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=false
expect "manual start: nothing is requested until the start pulse, then the same list (bounded, 40 cycles)" PASS "$(prove hdmiseq_manual.v "$sp" bmc 40 '' hdmiseq_manual_safety)"

echo "hdmi_i2c_writer"
wr_srcs=(hdmi_i2c_writer)
wgen=(-gclk_freq=8 -gi2c_freq=1)
wp="$f/hdmi_i2c_writer_props.sv"
build hdmi_i2c_writer hdmii2c "${wr_srcs[@]}" -- "${wgen[@]}"
expect "open drain only, SDA changes with SCL high only at start and stop, SDA released in the three ACK pulses, 27 data pulses plus the stop pulse, one-cycle done (bounded, 250 cycles)" PASS "$(prove hdmii2c.v "$wp" bmc 250 '' hdmii2c_safety)"
expect "cover: a transaction ends with and without a missing ACK" PASS "$(prove hdmii2c.v "$wp" cover 250 '-DCOVER' hdmii2c_cover)"

# Mutants of the HDMI blocks: each defect must make a proof fail.
mut_expose=("${tim_exp[@]}")
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_hs_late "s/HS_BEGIN : natural := h_visible + h_front_porch;/HS_BEGIN : natural := h_visible + h_front_porch + 1;/" 30 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_vs_wide "s/v_cnt < VS_BEGIN + v_sync else/v_cnt < VS_BEGIN + v_sync + 1 else/" 150 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_line_short "s/next_h := pick(h_cnt = H_TOTAL - 1, 0, h_cnt + 1);/next_h := pick(h_cnt = H_TOTAL - 2, 0, h_cnt + 1);/" 30 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_vs_polarity "s/o_vs <= VS_LEVEL when vs_pulse = '1' else not VS_LEVEL;/o_vs <= not VS_LEVEL when vs_pulse = '1' else VS_LEVEL;/" 120 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_visible_wide "s/vis_x <= '1' when h_cnt < h_visible else '0';/vis_x <= '1' when h_cnt <= h_visible else '0';/" 30 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_vblank_late "s/vblank_q <= to_sl(v_cnt >= v_visible);/vblank_q <= to_sl(v_cnt > v_visible);/" 120 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_image_not_centered "s/X_OFF : natural := (h_visible - IMAGE_W) \/ 2;/X_OFF : natural := (h_visible - IMAGE_W) \/ 3;/" 30 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true
mutant video_timing "$tp" video_timing '-DINVARIANT' hdmitim_vsync_stuck "s/vsync_q <= vs_pulse;/vsync_q <= '0';/" 120 "${tim_srcs[@]}" -- "${tgen[@]}" -gh_sync_positive=true -gv_sync_positive=true

mut_expose=("${reg_exp[@]}")
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_event_loses_to_clear "s/irq_pend <= (irq_pend and not clear_mask) or events;/irq_pend <= (irq_pend or events) and not clear_mask;/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_mask_ignored "s/to_sl((irq_pend and irq_en) \/=/to_sl((irq_pend or irq_en) \/=/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '-DINITOFF' hdmiregs_start_without_sequencer "s/seq_start_q <= to_sl(init_enable) and i_data_in(0);/seq_start_q <= i_data_in(0);/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=false
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_start_wrong_bit "s/and i_data_in(0);/and i_data_in(1);/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_mask_shifted "s/irq_en <= i_data_in(IRQ_BITS - 1 downto 0);/irq_en <= i_data_in(IRQ_BITS downto 1);/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_frame_level "s/events(IRQ_FRAME_BIT) <= i_vblank and not vblank_prev;/events(IRQ_FRAME_BIT) <= i_vblank;/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_pin_level "s/events(IRQ_INT_BIT) <= i_int_active and not int_prev;/events(IRQ_INT_BIT) <= i_int_active;/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_clear_wrong_bit "s/clear_mask <= i_data_in(IRQ_BITS - 1 downto 0)/clear_mask <= i_data_in(IRQ_BITS downto 1)/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_status_swapped "s/o_data_out(STATUS_BUSY_BIT) <= i_seq_busy;/o_data_out(STATUS_BUSY_BIT) <= i_seq_done;/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_mask_not_reset "s/irq_en <= (others => '0');/null;/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true
mutant hdmi_regs "$rp" hdmi_regs '' hdmiregs_count_swapped "s/o_data_out(7 downto 0) <= i_seq_sent;/o_data_out(7 downto 0) <= i_seq_nacks;/" 8 "${reg_srcs[@]}" -- "${rgen[@]}" -ginit_enable=true

mut_expose=()
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_nack_ignored "s/if i_wr_nack = '1' then/if false then/" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_index_stuck "s/index <= index + 1;/index <= index;/" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_done_early "s/if index = COUNT - 1 then/if index = COUNT - 2 then/" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_done_never "s/done_q <= '1';/done_q <= '0';/" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_sent_not_counted "s/sent_q <= pick(sent_q = SAT, SAT, sent_q + 1);/sent_q <= sent_q;/" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_reissues "s/state <= S_WAIT;/state <= S_ISSUE;/" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_auto_ignored "/if auto_start and COUNT > 0 then/{n;s/state <= S_ISSUE;/state <= S_IDLE;/}" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_register_swapped "s/o_wr_reg <= ROM(index)(15 downto 8);/o_wr_reg <= ROM(index)(7 downto 0);/" 40 "${seq_srcs[@]}" -- "${sgen[@]}" -gauto_start=true

mutant hdmi_i2c_writer "$wp" hdmi_i2c_writer '' hdmii2c_ack_driven "/if bit_idx = 8 then/{n;s/sda_low <= '0';/sda_low <= '1';/}" 250 "${wr_srcs[@]}" -- "${wgen[@]}"
mutant hdmi_i2c_writer "$wp" hdmi_i2c_writer '' hdmii2c_two_bytes "s/if byte_idx = 2 then/if byte_idx = 1 then/" 250 "${wr_srcs[@]}" -- "${wgen[@]}"
mutant hdmi_i2c_writer "$wp" hdmi_i2c_writer '' hdmii2c_out_high "s/o_sda_out <= '0';/o_sda_out <= '1';/" 250 "${wr_srcs[@]}" -- "${wgen[@]}"
mutant hdmi_i2c_writer "$wp" hdmi_i2c_writer '' hdmii2c_busy_short "s/o_busy <= to_sl(state \/= S_IDLE);/o_busy <= to_sl(state = S_DATA);/" 250 "${wr_srcs[@]}" -- "${wgen[@]}"
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_audio_overwrites "s/rom(BASE_COUNT + i) := init_word(audio_table, i);/rom(i) := init_word(audio_table, i);/" 40 "${seq_srcs[@]}" -- -ginit_table=9803 -gaudio_table=0100AF16 -gauto_start=true
mutant hdmi_init_seq "$sp" hdmi_init_seq '-DAUTO' hdmiseq_audio_dropped "s/COUNT : natural := BASE_COUNT + init_count(audio_table);/COUNT : natural := BASE_COUNT;/" 40 "${seq_srcs[@]}" -- -ginit_table=9803 -gaudio_table=0100AF16 -gauto_start=true

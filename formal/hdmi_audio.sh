# Proofs of the HDMI audio output (hdmi_audio over the audio peripheral), sourced by formal/run.sh and so using its
# helpers (build, prove, expect, mutant) and variables. The clock of the system is twice the MCLK, so the master clock
# flips at every cycle and the counts of the three clocks are exact in cycles; the instance starts by itself (autostart).
ha_srcs=(config_pkg uart_fifo audio_consts audio_xck_gen audio_frame_clocks audio_i2s_tx audio_i2s_rx audio_tone audio hdmi_audio)
path_of[hdmi_audio]="$root/src/HDMI/soc/hdmi_audio.vhd"
for n in audio_consts audio_xck_gen audio_frame_clocks audio_i2s_tx audio_i2s_rx audio_tone audio; do path_of[$n]="$root/src/audio/soc/$n.vhd"; done
path_of[config_pkg]="$root/src/common/src/config_pkg.vhd"
path_of[uart_fifo]="$root/src/UART/serial/uart_fifo.vhd"
hap="$f/hdmi_audio_props.sv"

echo "hdmi_audio"
mut_expose=(); mut_open=0
hagen128=(-gclk_freq=8192000 -gsample_rate=32000 -gmclk_ratio=128 -gword_bits=16 -gtx_fifo_depth=2 -gautostart=true)
hagen256=(-gclk_freq=16384000 -gsample_rate=32000 -gmclk_ratio=256 -gword_bits=16 -gtx_fifo_depth=2 -gautostart=true)
build hdmi_audio hdmiaud128 "${ha_srcs[@]}" -- "${hagen128[@]}"
expect "MCLK/LRCLK = 128: per channel 64 MCLK rises, 32 SCLK rises and 128 cycles, 2 MCLK rises per SCLK rise, data only after an SCLK fall (bounded, 520 cycles)" PASS "$(prove hdmiaud128.v "$hap" bmc 520 '-DRATIO=128' hdmiaud128_safety)"
expect "cover: three LRCLK flips with an SCLK rise and a data change are reachable (ratio 128)" PASS "$(prove hdmiaud128.v "$hap" cover 520 '-DRATIO=128 -DCOVER' hdmiaud128_cover)"
build hdmi_audio hdmiaud256 "${ha_srcs[@]}" -- "${hagen256[@]}"
expect "MCLK/LRCLK = 256: per channel 128 MCLK rises, 32 SCLK rises and 256 cycles, 4 MCLK rises per SCLK rise, data only after an SCLK fall (bounded, 1030 cycles)" PASS "$(prove hdmiaud256.v "$hap" bmc 1030 '-DRATIO=256' hdmiaud256_safety)"
expect "cover: three LRCLK flips with an SCLK rise and a data change are reachable (ratio 256)" PASS "$(prove hdmiaud256.v "$hap" cover 1030 '-DRATIO=256 -DCOVER' hdmiaud256_cover)"

# Mutants of hdmi_audio: each defect must make a proof fail.
mutant hdmi_audio "$hap" hdmi_audio '-DRATIO=128' hdmiaud_slot_short "s/constant SLOT_BITS : positive := 32;/constant SLOT_BITS : positive := 24;/" 520 "${ha_srcs[@]}" -- "${hagen128[@]}"
mutant hdmi_audio "$hap" hdmi_audio '-DRATIO=128' hdmiaud_mclk_half "s/xck_freq => MCLK_FREQ,/xck_freq => MCLK_FREQ \/ 2,/" 520 "${ha_srcs[@]}" -- "${hagen128[@]}"
mutant hdmi_audio "$hap" hdmi_audio '-DRATIO=128' hdmiaud_clocks_swapped "s/o_xck => o_mclk,/o_xck => o_sclk,/;s/o_bclk => o_sclk,/o_bclk => o_mclk,/" 520 "${ha_srcs[@]}" -- "${hagen128[@]}"
mutant hdmi_audio "$hap" hdmi_audio '-DRATIO=256' hdmiaud_ratio_ignored "s/MCLK_FREQ : positive := mclk_ratio \* sample_rate;/MCLK_FREQ : positive := 128 * sample_rate;/" 1030 "${ha_srcs[@]}" -- "${hagen256[@]}"

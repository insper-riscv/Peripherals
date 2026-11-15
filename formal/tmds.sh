# Proofs of the TMDS encoder, sourced by formal/run.sh and so using its helpers (build, prove, expect, mutant) and
# variables.
path_of[tmds_consts]="$root/src/HDMI/tmds/tmds_consts.vhd"
path_of[tmds_encoder]="$root/src/HDMI/tmds/tmds_encoder.vhd"

echo "tmds_encoder"
tmds_srcs=(tmds_consts tmds_encoder)
mut_expose=(disparity:5)
tp="$f/tmds_encoder_props.sv"
build tmds_encoder tmdsenc "${tmds_srcs[@]}" --
expect "a reset gives the control token 00, blanking gives the token of C1 C0, a data token decodes back to the byte, and the running disparity is the sum of the tokens sent, never above 8 in modulus (induction)" PASS "$(prove tmdsenc.v "$tp" prove 3 '' tmdsenc_safety)"
expect "cover: an inverted and a plain data token, a control token and the return of the disparity to zero are reachable" PASS "$(prove tmdsenc.v "$tp" cover 8 '-DCOVER' tmdsenc_cover)"

# Mutants: each defect must make a proof fail.
mutant tmds_encoder "$tp" tmds_encoder '' tmdsenc_xor_flag_flipped "s/q_m(PIXEL_BITS) := '1';/q_m(PIXEL_BITS) := '0';/" 6 "${tmds_srcs[@]}" --
mutant tmds_encoder "$tp" tmds_encoder '' tmdsenc_no_inversion "s/q_out(7 downto 0) := not q_m(7 downto 0);/q_out(7 downto 0) := q_m(7 downto 0);/" 6 "${tmds_srcs[@]}" --
mutant tmds_encoder "$tp" tmds_encoder '' tmdsenc_blank_keeps_disparity "/elsif i_de = .0. then/{n;s/disparity <= 0;/null;/}" 6 "${tmds_srcs[@]}" --
mutant tmds_encoder "$tp" tmds_encoder '' tmdsenc_control_swapped "s/token <= TOKEN_CTRL_01;/token <= TOKEN_CTRL_10;/" 6 "${tmds_srcs[@]}" --
mutant tmds_encoder "$tp" tmds_encoder '' tmdsenc_count_wrong "s/cnt_nx := cnt_nx - 2;/cnt_nx := cnt_nx;/" 6 "${tmds_srcs[@]}" --

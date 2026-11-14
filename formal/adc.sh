# Proofs of the sequencer of the MAX 10 ADC peripheral, sourced by formal/run.sh and so using its helpers
# (build, prove, expect, mutant) and variables.
echo "max10_adc_sequencer"
for n in max10_adc_consts max10_adc_sequencer; do path_of[$n]="$root/src/ADC/soc/$n.vhd"; done
adc_srcs=(max10_adc_consts max10_adc_sequencer)
asp="$f/max10_adc_sequencer_props.sv"
mut_expose=(); mut_open=0
build max10_adc_sequencer adcseq "${adc_srcs[@]}" --
expect "busy is the scan of the model; a command is for the lowest channel still without a sample of the mask taken at the start, with no other command awaiting its response, startofpacket on the first and endofpacket on the last; the command holds until the ready; a sample comes only from the response of the requested channel to an accepted command, and every such response is taken; the end comes with every channel sampled (bounded, 22 cycles, any ready, response and mask)" PASS "$(prove adcseq.v "$asp" bmc 22 '' adcseq_safety)"
expect "cover: a scan of three channels ends, a response follows the ready, a wrong response is ignored and a command waits for its ready" PASS "$(prove adcseq.v "$asp" cover 30 '-DCOVER' adcseq_cover)"

# Mutants: each defect must make a proof fail.
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_eop_never "s/'1' when unsigned(rest) = 0/'1' when unsigned(pending) = 0/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_sop_stuck "s/first <= '0';/null;/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_highest_first "s/for i in mask'low to mask'high loop/for i in mask'high downto mask'low loop/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_channel_kept "s/pending(current) <= '0';/null;/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_any_channel "s/ and to_integer(unsigned(i_rsp_channel)) = current//" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_response_before_ready "s/(state = S_CMD and i_cmd_ready = '1') or/(state = S_CMD) or/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_done_each_pick "s/'1' when state = S_FINISH/'1' when state = S_PICK/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_skips_response "s/state <= S_RSP;/state <= S_PICK;/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_busy_drops_early "s/'0' when state = S_IDLE else '1'/'0' when state = S_IDLE or state = S_FINISH else '1'/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_mask_not_latched "s/lowest_set(pending)/lowest_set(pending and i_mask)/" 22 "${adc_srcs[@]}" --
mutant max10_adc_sequencer "$asp" max10_adc_sequencer '' adcseq_valid_drops "s/'1' when state = S_CMD else '0'/'1' when state = S_CMD and i_cmd_ready = '0' else '0'/" 22 "${adc_srcs[@]}" --

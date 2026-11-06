# Proofs of the PLIC (gateway, arbiter and the controller), sourced by formal/run.sh and so using its helpers
# (build, prove, expect, mutant) and variables.
echo "plic_gateway"
for n in plic_consts plic_gateway plic_arbiter plic; do path_of[$n]="$root/src/PLIC/soc/$n.vhd"; done
gw_srcs=(plic_gateway)
gwp="$f/plic_gateway_props.sv"
mut_expose=(); mut_open=0
build plic_gateway plicgw "${gw_srcs[@]}" --
expect "pending follows the ideal gateway: one request per service, the claim clears it, only the complete unmasks (bounded, 16 cycles)" PASS "$(prove plicgw.v "$gwp" bmc 16 '' plicgw_safety)"
expect "cover: a request, a claim and a new request after the complete are reachable" PASS "$(prove plicgw.v "$gwp" cover 12 '-DCOVER' plicgw_cover)"

echo "plic_arbiter"
arb_srcs=(plic_arbiter)
arb_gen=(-gn_sources=6 -gpriority_bits=3 -gid_width=3)
arp="$f/plic_arbiter_props.sv"
build plic_arbiter plicarb "${arb_srcs[@]}" -- "${arb_gen[@]}"
expect "o_id is the pending enabled source of highest priority above the threshold, lowest id on a tie; zero and not valid otherwise (6 sources, 3 bits, induction)" PASS "$(prove plicarb.v "$arp" prove 2 '' plicarb_safety)"
expect "cover: the first and the last source win, a pending source is below the threshold, and a tie goes to the lowest id" PASS "$(prove plicarb.v "$arp" cover 2 '-DCOVER' plicarb_cover)"

echo "plic"
plic_srcs=(plic_consts plic_gateway plic_arbiter plic)
plic_gen=(-gn_sources=4 -gpriority_bits=2 -gaddr_width=20)
pp="$f/plic_props.sv"
mut_expose=(pending:3 enable_reg:3 priorities:7 threshold:1)
build plic plic "${plic_srcs[@]}" -- "${plic_gen[@]}"
expect "MEIP exists exactly when there is a candidate; claim is the pending enabled source of highest priority above the threshold, lowest id on a tie, else zero; complete unmasks only the id written; every register reads as the model (bounded, 14 cycles, 4 sources, 2 bits)" PASS "$(prove plic.v "$pp" bmc 14 '' plic_safety)"
expect "cover: MEIP rises, the last source is claimed among all, a masked line stays quiet, a complete re-arms and a threshold hides a pending source" PASS "$(prove plic.v "$pp" cover 14 '-DCOVER' plic_cover)"

# Mutants of the arbiter, the gateway and the controller: each defect must make a proof fail.
mut_expose=()
mutant plic_gateway "$gwp" plic_gateway '' plicgw_no_mask "s/if i_source = '1' and inflight = '0' then/if i_source = '1' then/" 16 "${gw_srcs[@]}" --
mutant plic_gateway "$gwp" plic_gateway '' plicgw_claim_ignored "s/if i_claim = '1' then/if false then/" 16 "${gw_srcs[@]}" --
mutant plic_gateway "$gwp" plic_gateway '' plicgw_complete_ignored "s/if i_complete = '1' then/if false then/" 16 "${gw_srcs[@]}" --
mutant plic_gateway "$gwp" plic_gateway '' plicgw_reset_ignored "s/if i_rst = '1' then/if false then/" 16 "${gw_srcs[@]}" --

mutant plic_arbiter "$arp" plic_arbiter '' plicarb_tie_highest "s/pri > best_pri then/pri >= best_pri then/" 2 "${arb_srcs[@]}" -- "${arb_gen[@]}"
mutant plic_arbiter "$arp" plic_arbiter '' plicarb_threshold_not_strict "s/and pri > best_pri then/and (pri > best_pri or (best_id = 0 and pri = best_pri and pri \/= 0)) then/" 2 "${arb_srcs[@]}" -- "${arb_gen[@]}"
mutant plic_arbiter "$arp" plic_arbiter '' plicarb_enable_ignored "s/ and i_enable(n) = '1'//" 2 "${arb_srcs[@]}" -- "${arb_gen[@]}"
mutant plic_arbiter "$arp" plic_arbiter '' plicarb_pending_ignored "s/i_pending(n) = '1' and //" 2 "${arb_srcs[@]}" -- "${arb_gen[@]}"
mutant plic_arbiter "$arp" plic_arbiter '' plicarb_threshold_ignored "s/best_pri := unsigned(i_threshold);/best_pri := (others => '0');/" 2 "${arb_srcs[@]}" -- "${arb_gen[@]}"
mutant plic_arbiter "$arp" plic_arbiter '' plicarb_last_wins "s/for n in 1 to n_sources loop/for n in n_sources downto 1 loop/" 2 "${arb_srcs[@]}" -- "${arb_gen[@]}"

mut_expose=(pending:3 enable_reg:3 priorities:7 threshold:1)
mutant plic "$pp" plic '' plic_claim_not_clearing "s/claim_hit(n) <= '1' when claim_read/claim_hit(n) <= '0' when claim_read/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_complete_any_id "s/ and unsigned(i_data_in) = to_unsigned(n, 32) else/ else/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_complete_ignores_enable "s/compl_write = '1' and enable_reg(n) = '1' and/compl_write = '1' and/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_complete_any_address "s/compl_write <= '1' when i_write = '1' and addr = ADDR_CLAIM_COMPLETE else/compl_write <= '1' when i_write = '1' else/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_claim_any_address "s/claim_read  <= '1' when i_read = '1' and addr = ADDR_CLAIM_COMPLETE else/claim_read  <= '1' when i_read = '1' else/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_priority_address "s/if addr = n then/if addr = n + 1 then/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_pending_reads_enable "s/ADDR_PENDING_BASE + n \/ 32/ADDR_ENABLE_BASE + n \/ 32/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_meip_constant "s/o_meip <= winner_ok;/o_meip <= '1';/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_threshold_shifted "s/threshold <= i_data_in(priority_bits - 1 downto 0);/threshold <= i_data_in(priority_bits downto 1);/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_claim_reads_zero "s/o_data_out(ID_WIDTH - 1 downto 0) <= winner_id;/o_data_out(ID_WIDTH - 1 downto 0) <= (others => '0');/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_enable_not_reset "s/enable_reg <= (others => '0');/null;/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic "$pp" plic '' plic_enable_bit_shifted "s/enable_reg(n) <= i_data_in(n mod 32);/enable_reg(n) <= i_data_in((n + 1) mod 32);/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"
mutant plic_consts "$pp" plic '' plic_claim_address "s/ADDR_CLAIM_COMPLETE : natural := 16#80001#/ADDR_CLAIM_COMPLETE : natural := 16#80002#/" 14 "${plic_srcs[@]}" -- "${plic_gen[@]}"

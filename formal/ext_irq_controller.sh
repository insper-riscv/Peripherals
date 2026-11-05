# Proofs of the external interrupt controller (ext_irq_controller), sourced by formal/run.sh and so using its
# helpers (build, prove, expect, mutant) and variables.
echo "ext_irq_controller"
irq_srcs=(ext_irq_consts ext_irq_controller)
for n in "${irq_srcs[@]}"; do path_of[$n]="$root/src/intc/soc/$n.vhd"; done
irq_gen=(-girq_count=4 -gsync_stages=2)
ip="$f/ext_irq_controller_props.sv"
mut_expose=(); mut_open=0
build ext_irq_controller extirq "${irq_srcs[@]}" -- "${irq_gen[@]}"
expect "MEIP is exactly (pending and enable) != 0; each address reads its register; source id is the lowest active line plus one (bounded, 12 cycles, 4 lines)" PASS "$(prove extirq.v "$ip" bmc 12 '' extirq_safety)"
expect "cover: two active sources, one active source and a masked pending line are reachable" PASS "$(prove extirq.v "$ip" cover 12 '-DCOVER' extirq_cover)"

mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_mask_ignored "s/active_lines   <= pending_lines and enable_reg;/active_lines   <= pending_lines;/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"
mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_or_not_and "s/active_lines   <= pending_lines and enable_reg;/active_lines   <= pending_lines or enable_reg;/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"
mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_write_any_address "s/i_write = '1' and i_address = EXT_IRQ_ADDR_ENABLE/i_write = '1'/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"
mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_enable_not_reset "s/enable_reg <= (others => '0');/null;/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"
mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_highest_wins "s/for n in irq_count - 1 downto 0 loop/for n in 0 to irq_count - 1 loop/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"
mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_id_zero_based "s/winner := n + 1;/winner := n;/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"
mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_pending_is_enable "s/o_data_out(irq_count - 1 downto 0) <= pending_lines;/o_data_out(irq_count - 1 downto 0) <= enable_reg;/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"
mutant ext_irq_controller "$ip" ext_irq_controller '' extirq_reserved_reads_id "s/elsif i_address = EXT_IRQ_ADDR_SOURCE_ID then/else/" 12 "${irq_srcs[@]}" -- "${irq_gen[@]}"

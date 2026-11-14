# Proofs of the Ethernet MAC (CRC-32 register, asynchronous FIFO and register file), sourced by formal/run.sh and so
# using its helpers (build, prove, expect, mutant) and variables.
for n in eth_consts eth_crc32 eth_regs; do path_of[$n]="$root/src/ETH/mac/$n.vhd"; done
for n in eth_dpram eth_async_fifo; do path_of[$n]="$root/src/ETH/mac/$n.vhd"; done

echo "eth_crc32"
eth_crc_srcs=(eth_consts eth_crc32)
ecp="$f/eth_crc32_props.sv"
mut_expose=(); mut_open=0
build eth_crc32 ethcrc "${eth_crc_srcs[@]}" --
expect "the state mirrors an independent non-reflected CRC-32 model, o_residue_ok is exactly the residue, and the complement of any state leads to the residue (induction)" PASS "$(prove ethcrc.v "$ecp" prove 2 '' ethcrc_safety)"
expect "cover: the residue is reached and the register returns to its initial value" PASS "$(prove ethcrc.v "$ecp" cover 20 '-DCOVER' ethcrc_cover)"

echo "eth_async_fifo"
eth_fifo_srcs=(eth_dpram eth_async_fifo)
eth_fifo_gen=(-gdata_width=3 -gaddr_bits=2)
efp="$f/eth_async_fifo_props.sv"
mut_expose=(wbin:2 rbin:2 wgray:2 rgray:2)
multiclock=1
build eth_async_fifo ethfifo "${eth_fifo_srcs[@]}" -- "${eth_fifo_gen[@]}"
expect "occupancy within 0 and the depth, a write is never accepted when full nor a read when empty, the pointers are Gray codes that change one bit per edge (bounded, free clocks, 4 words)" PASS "$(prove ethfifo.v "$efp" bmc 30 '' ethfifo_safety)"
expect "cover: the queue fills up, holds one word, and empties after use" PASS "$(prove ethfifo.v "$efp" cover 40 '-DCOVER' ethfifo_cover)"

echo "eth_regs"
eth_regs_srcs=(eth_consts eth_regs)
erp="$f/eth_regs_props.sv"
mut_expose=(ctrl:6 irq_enable:4 irq_pending:3 mac_addr:47 tx_len:4 tx_ptr:2 tx_busy)
multiclock=0
eth_regs_gen=(-gtx_buffer_addr_bits=2 -grx_buffer_addr_bits=2)
build eth_regs ethregs "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
expect "control, mask, pending interrupts, MAC address, length, pointer and transmitter state follow the ideal model; the interrupt is pending AND enabled; the start pulse needs a free transmitter and a non-zero length (induction)" PASS "$(prove ethregs.v "$erp" prove 3 '' ethregs_safety)"
expect "cover: the interrupt rises, a transmission starts and a start is refused while busy" PASS "$(prove ethregs.v "$erp" cover 12 '-DCOVER' ethregs_cover)"

# Mutants: each defect must make a proof fail.
mut_expose=()
mutant eth_consts "$ecp" eth_crc32 '' ethcrc_poly "s/x\"EDB88320\"/x\"EDB88321\"/" 6 "${eth_crc_srcs[@]}" --
mutant eth_consts "$ecp" eth_crc32 '' ethcrc_residue "s/x\"DEBB20E3\"/x\"DEBB20E4\"/" 10 "${eth_crc_srcs[@]}" --
mutant eth_consts "$ecp" eth_crc32 '' ethcrc_bit_order "s/feedback := state(0) xor nibble(i);/feedback := state(0) xor nibble(3 - i);/" 6 "${eth_crc_srcs[@]}" --
mutant eth_crc32 "$ecp" eth_crc32 '' ethcrc_clear_ignored "s/if i_rst = '1' or i_clear = '1' then/if i_rst = '1' then/" 6 "${eth_crc_srcs[@]}" --

mut_expose=(wbin:2 rbin:2 wgray:2 rgray:2)
multiclock=1
mutant eth_async_fifo "$efp" eth_async_fifo '' ethfifo_write_when_full "s/wr_ok <= i_wr_en and not full;/wr_ok <= i_wr_en;/" 30 "${eth_fifo_srcs[@]}" -- "${eth_fifo_gen[@]}"
mutant eth_async_fifo "$efp" eth_async_fifo '' ethfifo_binary_pointer "s/wgray <= to_gray(wbin_next);/wgray <= std_logic_vector(wbin_next);/" 30 "${eth_fifo_srcs[@]}" -- "${eth_fifo_gen[@]}"
mutant eth_async_fifo "$efp" eth_async_fifo '' ethfifo_never_empty "s/empty <= '1' when rgray = wgray_sync else '0';/empty <= '0';/" 30 "${eth_fifo_srcs[@]}" -- "${eth_fifo_gen[@]}"
mutant eth_async_fifo "$efp" eth_async_fifo '' ethfifo_full_compare "s/(not rgray_sync(addr_bits) \& not rgray_sync(addr_bits - 1)/(rgray_sync(addr_bits) \& not rgray_sync(addr_bits - 1)/" 30 "${eth_fifo_srcs[@]}" -- "${eth_fifo_gen[@]}"
mutant eth_async_fifo "$efp" eth_async_fifo '' ethfifo_read_when_empty "s/rd_ok <= i_rd_en and not empty;/rd_ok <= i_rd_en;/" 30 "${eth_fifo_srcs[@]}" -- "${eth_fifo_gen[@]}"

mut_expose=(ctrl:6 irq_enable:4 irq_pending:3 mac_addr:47 tx_len:4 tx_ptr:2 tx_busy)
multiclock=0
mutant eth_regs "$erp" eth_regs '' ethregs_start_while_busy "s/and not tx_busy and to_sl(tx_len \/= 0);/and to_sl(tx_len \/= 0);/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
mutant eth_regs "$erp" eth_regs '' ethregs_start_zero_length "s/and not tx_busy and to_sl(tx_len \/= 0);/and not tx_busy;/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
mutant eth_regs "$erp" eth_regs '' ethregs_irq_or_enable "s/(irq_pending \& i_phy_int) and (irq_enable/(irq_pending \& i_phy_int) or (irq_enable/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
mutant eth_regs "$erp" eth_regs '' ethregs_ctrl_shift "s/ctrl <= i_data_in(6 downto 0);/ctrl <= i_data_in(5 downto 0) \& '0';/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
mutant eth_regs "$erp" eth_regs '' ethregs_length_while_busy "s/if wr_tx_len = '1' and tx_busy = '0' then/if wr_tx_len = '1' then/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
mutant eth_regs "$erp" eth_regs '' ethregs_busy_never_set "s/tx_busy <= '1';/tx_busy <= '0';/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
mutant eth_regs "$erp" eth_regs '' ethregs_error_not_pending "s/irq_pending(IRQ_ERROR) <= '1';/irq_pending(IRQ_ERROR) <= '0';/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
mutant eth_regs "$erp" eth_regs '' ethregs_reset_ctrl "s/ctrl <= \"0000100\";/ctrl <= \"0000000\";/" 8 "${eth_regs_srcs[@]}" -- "${eth_regs_gen[@]}"
multiclock=0

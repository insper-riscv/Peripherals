#!/usr/bin/env bash
# Formal verification of the CLINT, the PLIC, the timer (with its prescaler, overflow detector and comparator), the GPIO cell, the UART FIFO, the UART and the console with SymbiYosys. Needs
# ghdl, yosys, sby and the engine chosen by FORMAL_ENGINE (all in the ci-vhdl image). Run from the root of the
# repository:  FORMAL_ENGINE=bitwuzla bash formal/run.sh
#
# FORMAL_ENGINE is one of yices, bitwuzla (the default), boolector and abc-bmc3. The first three are SMT solvers
# of the smtbmc engine; abc-bmc3 is the bounded model checker of ABC, which has no induction and no cover, so it
# skips those proofs. FORMAL_TIMEOUT (seconds, 900 by default) bounds each proof.
#
# Besides the report, the run writes build/formal/result-<engine>.tsv, one line per proof with the columns
# id, wanted (pass or fail), verdict (pass, fail, error or skip), sby exit code, milliseconds and the label, which
# formal/aggregate.sh joins across engines.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$root/build/formal"
rm -rf "$out"; mkdir -p "$out"; cd "$out"

engine="${FORMAL_ENGINE:-bitwuzla}"
case "$engine" in
  yices|bitwuzla|boolector|abc-bmc3) ;;
  *) echo "FORMAL_ENGINE must be yices, bitwuzla, boolector or abc-bmc3, not '$engine'" >&2; exit 2 ;;
esac
timeout_s="${FORMAL_TIMEOUT:-900}"
results="$out/result-$engine.tsv"; : > "$results"

fail=0
warnings="$out/warnings.txt"; : > "$warnings"
# expect <label> <wanted: PASS|FAIL> <result: PASS|FAIL|SKIP|ERROR ...>. An ERROR (the tool did not reach a verdict)
# never matches, not even a wanted FAIL; a SKIP is a proof this engine does not do and is not a failure. The id,
# the exit code and the time of the proof come from the files prove left for its tag.
expect() {
  local tag verdict rc ms
  tag="$(cat "$out/.last")"
  IFS=$'\t' read -r verdict rc ms < "$out/$tag.res"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$tag" "${2,,}" "$verdict" "$rc" "$ms" "$1" >> "$results"
  case "$3" in
    SKIP*) printf '  skip  %-62s %s\n' "$1" "${3#SKIP }" ;;
    ERROR*) printf '  ERROR %-62s %s\n' "$1" "${3#ERROR }"; fail=1 ;;
    "$2") printf '  ok    %-62s %s (%s ms)\n' "$1" "$3" "$ms" ;;
    *) printf '  WRONG %-62s wanted %s, got %s\n' "$1" "$2" "$3"; fail=1 ;;
  esac
}

# Sources in dependency order. The file under proof, when it is a mutant, replaces the original in the list.
common=(utils_pkg flip_flop generic_register clearable_register synchronizer adder mux_2x1 mux_4x1 mux_8x1 tristate_buffer_1bit)
timer_srcs=(alu_ge_unsigned counter_overflow clock_prescaler timer_operation_decoder timer)
gpio_srcs=(gpio_operation_decoder gpio_cell gpio)
clint_srcs=(alu_ge_unsigned clint_consts config_pkg counter64 clint)
fifo_srcs=(uart_fifo)
flash_srcs=(flash_controller)
uart_srcs=(baudGen uartRx uartTx uart2BusTop_pkg uartTop uart_fifo uart)
declare -A path_of
for n in "${common[@]}"; do path_of[$n]="$root/src/common/src/$n.vhd"; done
for n in "${timer_srcs[@]}"; do path_of[$n]="$root/src/TIMER/soc/$n.vhd"; done
for n in "${gpio_srcs[@]}"; do path_of[$n]="$root/src/GPIO/soc/$n.vhd"; done
for n in baudGen uartRx uartTx uart2BusTop_pkg uartTop; do path_of[$n]="$root/src/UART/serial/vendor/opencores_uart2bus/$n.vhd"; done
for n in clint_consts clint; do path_of[$n]="$root/src/CLINT/soc/$n.vhd"; done
# The mtime counter of the CLINT is the counter64 of Common-Components, proved there on its own.
for n in config_pkg counter64; do path_of[$n]="$root/src/common/src/$n.vhd"; done
path_of[uart]="$root/src/UART/serial/uart.vhd"
path_of[uart_fifo]="$root/src/UART/serial/uart_fifo.vhd"
path_of[flash_controller]="$root/src/flash-controller/soc/flash_controller.vhd"
mut_from=""; mut_to=""

# A warning is an error. GHDL, Yosys and SymbiYosys print a warning for code that is out of the norm or at its
# limit, and the fix is in the code or in the proof, never in a flag that hides it (-Wno-* is not used).
# scan_warnings <log>: records in warnings.txt, and prints on stderr, every line of <log> that has the word
# "warning" (case-insensitive, as a whole word or its plural: ghdl ":warning:", yosys "Warning:", sby "warning").
# A name such as warning_count does not match, because the underscore is part of the word, and the summary
# "Warnings: 0 unique messages, 0 total" of yosys is skipped (a count of zero is not a warning). The files are scanned
# after the tool ends, in the main shell or in the subshell of prove, so the failure is decided at the end of the
# run, from warnings.txt.
# One exception, exact and only for the abc-bmc3 engine: ABC itself prints "Warning:" when it reads the AIGER
# file that SymbiYosys hands it, to announce how many outputs it reads as constraints (the assumptions, and the
# clock of the clk2ff step), or that there are none. They describe the tool's own file format, not the design or
# the proofs; see abc_notes below. The warnings about the clock as an undriven bit are gone: the script of the
# proof flattens the design and purges the aliases of the clock before the AIGER file is written. Yices, bitwuzla and boolector have no exception, and anything else, in any
# engine, still fails the run.
abc_notes='(engine_0: Warning: (The last (output is|[0-9]+ outputs are) interpreted as (a )?constraints?\.|The network has no constraints\.))$'
scan_warnings() {
  local line ignore='^$^'
  [ "$engine" = abc-bmc3 ] && [[ "$1" == *.log && "$1" != *.ghdl.log ]] && ignore="$abc_notes"
  { grep -inE '(^|[^[:alnum:]_])warnings?([^[:alnum:]_]|$)' "$1" || true; } \
    | { grep -viE 'warnings?: 0 (unique )?(messages|total)' || true; } \
    | { grep -vE "$ignore" || true; } \
    | while IFS= read -r line; do
        printf 'formal: WARNING treated as error: %s:%s\n' "${1#"$root"/}" "$line" | tee -a "$warnings" >&2
      done
}

# strip_vendor <source> <copy>: the copy of a source without the synthesis hints of Quartus (the attributes ramstyle
# and altera_attribute), keeping every line where it was so that the lines of the other messages still point to the
# source. GHDL does not know these attributes and warns about each one; they steer the Quartus fitter and have no
# effect on the logic that is proved. Any other attribute GHDL does not know is still a warning, and an error.
strip_vendor() {
  perl -0pe 's/^[ \t]*attribute[ \t]+(?:ramstyle|altera_attribute)\b(?:[^;"]|"(?:[^"]|"")*")*;[^\n]*(?:\n|\z)/"\n" x (($& =~ tr\/\n\/\/))/gme' "$1" > "$2"
}

# netlist <entity> <name> <sources of the entity...> -- [ghdl generics]: the Verilog netlist GHDL synthesizes for the entity.
netlist() {
  local ent="$1" name="$2"; shift 2
  local srcs=() gen=() n f
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do srcs+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  gen=("$@")
  local work="$out/work_$name"; mkdir -p "$work"
  local files=() copy
  for n in "${common[@]}" "${srcs[@]}"; do
    f="${path_of[$n]}"; [ "$f" = "$mut_from" ] && f="$mut_to"
    copy="$work/$(basename "$f")"; strip_vendor "$f" "$copy"; files+=("$copy")
  done
  # The messages of GHDL go to a log that scan_warnings reads; without a warning the log is empty.
  local log="$out/$name.ghdl.log"
  ghdl -a --std=08 --workdir="$work" "${files[@]}" 2> "$log" || { cat "$log" >&2; exit 1; }
  ghdl --synth --std=08 --workdir="$work" --out=verilog "${gen[@]}" "$ent" > "$name.v" 2>> "$log" || { cat "$log" >&2; exit 1; }
  scan_warnings "$log"
}

# expose <netlist> <signal[:high bit]>...: adds the wires of the last module (the top, GHDL writes it last) as
# the outputs dbg_<signal>. The logic is the same; the proof states the invariants over these registers.
expose() {
  local v="$1"; shift
  local ports="" assigns="" s w nm top
  # The text of the top module, the last one: a mutant can leave a signal without a reader, and GHDL then does not
  # write it. The proof still states its value, and an undeclared name would be an implicit wire without a driver
  # (a warning), so the output of a signal that is not there is the constant zero. The mutant is still caught by
  # the properties of the signals it does change.
  top="$(awk '/^module /{buf=""} {buf = buf $0 "\n"} END{printf "%s", buf}' "$v")"
  for s in "$@"; do
    nm="${s%%:*}"; w=""; [ "$s" != "$nm" ] && w="[${s#*:}:0] "
    ports+=",
   output ${w}dbg_$nm"
    if printf '%s' "$top" | grep -qE "(wire|reg)[^;]*[[:space:]]$nm;"; then
      assigns+="  assign dbg_$nm = $nm;
"
    else
      assigns+="  assign dbg_$nm = 0;
"
    fi
  done
  awk -v ports="$ports" -v assigns="$assigns" '
    { line[NR] = $0 }
    /^module / { m = NR }
    /^endmodule/ { e = NR }
    END {
      done = 0
      for (i = 1; i <= NR; i++) {
        l = line[i]
        if (i >= m && !done && l ~ /\);[ \t]*$/) { sub(/\);[ \t]*$/, ports ");", l); done = 1 }
        if (i == e) printf "%s", assigns
        print l
      }
    }' "$v" > "$v.tmp" && mv "$v.tmp" "$v"
  grep -q "dbg_${1%%:*}" "$v" || true
}

# open_pin <netlist>: the bidirectional pin of the GPIO cell becomes an input (what the pin is worth) and an
# output (what the cell drives), and a floating tristate output becomes zero. The logic is the same.
open_pin() {
  sed -i -e 's/inout  io_gpio_pin);/input  i_pin,\n   output o_pin_drv);/' \
         -e 's/^  assign io_gpio_pin = /  assign o_pin_drv = /' \
         -e 's/ = io_gpio_pin;/ = i_pin;/' \
         -e "s/1'bz/1'b0/" "$1"
  grep -q 'o_pin_drv' "$1" && grep -q 'i_pin' "$1" || { echo "open_pin: the pin of $1 was not found"; exit 1; }
}

# prove <netlist> <props> <mode: prove|bmc|cover> <depth> <defines> <tag>  ->  PASS, FAIL, SKIP or ERROR
# PASS is sby exit code 0, FAIL is 2 (a counterexample or a goal that cannot be covered) and any other code
# (4 unknown, 8 timeout, 16 error, 124 the FORMAL_TIMEOUT) is ERROR: the tool did not reach a verdict. The
# abc-bmc3 engine only checks bounded properties of designs with registers, so it answers SKIP for a proof by
# induction, for a cover and for a combinational design.
# The verdict, the exit code and the milliseconds go to <tag>.res, and the tag to .last, for expect.
# Four bounded proofs of the console (200 cycles over the whole UART) do not close in FORMAL_TIMEOUT with yices, while
# bitwuzla, boolector and abc-bmc3 answer them: yices is structurally slow on a design this deep. The yices run skips
# exactly these tags, as it skips what abc-bmc3 does not do, and formal/aggregate.sh still demands an answer from the
# other engines for each of them.
yices_slow=" console_pins console_inv mut_console_rx_polarity mut_console_read_strobe "
prove() {
  echo "$6" > "$out/.last"
  if [ "$engine" = yices ] && [[ "$yices_slow" == *" $6 "* ]]; then
    printf 'skip\t-\t0\n' > "$6.res"; echo "SKIP yices does not close this proof within FORMAL_TIMEOUT"; return
  fi
  local engine_lines script_lines options_lines="" rc=0 verdict began ended
  case "$engine" in
    abc-bmc3)
      if [ "$3" != bmc ]; then
        printf 'SKIP\t-\t0\n' > "$6.res"; echo "SKIP abc-bmc3 has no $3"; return
      fi
      engine_lines="abc bmc3"
      options_lines="aigsmt none"
      script_lines=$'flatten\nsetundef -undriven -zero\nopt_clean -purge\ntribuf -formal\nmemory_map\nsetundef -undriven -zero\ntechmap\nopt -fast\nsetundef -anyseq' ;;
    # memory_map turns the small queue memory of the UART into registers: the SMT engines (yices above all) take
    # far longer on a design with an array than on the same design with registers. A queue of 3 words has a read
    # multiplexer for 4 addresses, and the branch of the fourth has no driver (the pointers never reach it), which
    # SymbiYosys reports as a wire used with no driver: setundef gives that branch the value zero.
    *) engine_lines="smtbmc $engine"; script_lines=$'tribuf -formal\nmemory_map\nsetundef -undriven -zero' ;;
  esac
  cat > "$6.sby" <<EOS
[options]
mode $3
depth $4
$options_lines
[engines]
$engine_lines
[script]
read_verilog -formal -sv $5 $1 $2
prep -top props
$script_lines
[files]
$1
$2
EOS
  began=$(date +%s%N)
  timeout "$timeout_s" sby -f "$6.sby" > "$6.log" 2>&1 || rc=$?
  ended=$(date +%s%N)
  scan_warnings "$6.log"
  # ABC refuses a design without registers (the trap unit is combinational): that is a proof this engine does
  # not do, not a failure of the tool.
  if [ "$engine" = abc-bmc3 ] && [ "$rc" = 16 ] && grep -q 'Does not work for combinational networks' "$6.log"; then
    printf 'skip\t%s\t0\n' "$rc" > "$6.res"; echo "SKIP abc-bmc3 does not work for a combinational design"; return
  fi
  case "$rc" in
    0) verdict=PASS ;;
    2) verdict=FAIL ;;
    *) verdict=ERROR ;;
  esac
  printf '%s\t%s\t%s\n' "${verdict,,}" "$rc" "$(( (ended - began) / 1000000 ))" > "$6.res"
  case "$verdict" in
    ERROR) echo "ERROR sby exited with code $rc, not a verdict (see $6.log)" ;;
    *) echo "$verdict" ;;
  esac
}

src="$root/src"; f="$root/formal"
# Setup of the mutants of the block being proved: the sources, the generics, the signals exposed and whether the pin is opened.
mut_srcs=(); mut_gen=(); mut_expose=(); mut_open=0

# build <entity> <name> <sources...> -- [generics]: netlist plus the exposure and the pin opening of the block.
build() {
  netlist "$@"
  # A floating (tri-state) output has no value to prove and Yosys warns about it: it becomes zero, as the pin of the
  # GPIO cell does in open_pin. The properties look at the registers behind such an output, not at the output.
  sed -i "s/1'bz/1'b0/" "$2.v"
  [ "${#mut_expose[@]}" -gt 0 ] && expose "$2.v" "${mut_expose[@]}"
  [ "$mut_open" = 1 ] && open_pin "$2.v"
  return 0
}

echo "alu_ge_unsigned"
mut_expose=(); mut_open=0
build alu_ge_unsigned alu alu_ge_unsigned -- -gdata_width=8
expect "o_ge is exactly a >= b, unsigned, for every input (8 bits, induction)" PASS "$(prove alu.v "$f/alu_ge_unsigned_props.sv" prove 2 '-DWIDTH=8' alu_safety)"
expect "cover: greater, equal and less are reachable" PASS "$(prove alu.v "$f/alu_ge_unsigned_props.sv" cover 2 '-DWIDTH=8 -DCOVER' alu_cover)"

echo "counter_overflow"
build counter_overflow ovf alu_ge_unsigned counter_overflow -- -gdata_width=8
expect "overflow exactly when the counter reached the top (8 bits, induction)" PASS "$(prove ovf.v "$f/counter_overflow_props.sv" prove 2 '-DWIDTH=8' ovf_safety)"
expect "cover: overflow at the top and above it, and no overflow, are reachable" PASS "$(prove ovf.v "$f/counter_overflow_props.sv" cover 2 '-DWIDTH=8 -DCOVER' ovf_cover)"

echo "clock_prescaler"
build clock_prescaler presc alu_ge_unsigned clock_prescaler -- -gdata_width=3
expect "a tick exactly every prescaler + 1 cycles, none lost or doubled (bounded, 40 cycles, 3 bits)" PASS "$(prove presc.v "$f/clock_prescaler_props.sv" bmc 40 '-DWIDTH=3' presc_safety)"
expect "cover: the first tick and a tick at every cycle are reachable" PASS "$(prove presc.v "$f/clock_prescaler_props.sv" cover 24 '-DWIDTH=3 -DCOVER' presc_cover)"

echo "timer"
timer_exp=(counter:31 top_reg:31 duty_reg:31 prescaler_reg:31 config_reg:3 overflow_status overflow_prev tick pwm_inverted)
mut_expose=("${timer_exp[@]}")
build timer timer "${timer_srcs[@]}" --
expect "registers follow the bus writes, counter, overflow status, IRQ, PWM and readback (induction)" PASS "$(prove timer.v "$f/timer_props.sv" prove 3 '' timer_safety)"
expect "cover: an overflow raises the IRQ, the status read clears it, the counter advances with a tick" PASS "$(prove timer.v "$f/timer_props.sv" cover 20 '-DCOVER' timer_cover)"

echo "clint"
cgen=(-gtick_cycles=3)
clint_exp=(msip cmp_lo:31 cmp_hi:31 mtime_lo:31 mtime_hi:31 gen_tick_divided_phase:1)
mut_expose=("${clint_exp[@]}")
build clint clint "${clint_srcs[@]}" -- "${cgen[@]}"
expect "MTIP, MSIP and the read of every address follow the ideal model, with a tick every 3 cycles (induction)" PASS "$(prove clint.v "$f/clint_props.sv" prove 3 '-DTICK=3' clint_safety)"
expect "port write sequence: MTIP never rises in the middle unless the old or the final mtimecmp is reached (induction)" PASS "$(prove clint.v "$f/clint_props.sv" prove 3 '-DTICK=3 -DSEQ' clint_sequence)"
expect "the same two properties, bounded from reset (bounded, 20 cycles; the only form the abc-bmc3 engine answers)" PASS "$(prove clint.v "$f/clint_props.sv" bmc 20 '-DTICK=3' clint_bounded)"
expect "the same port write sequence, bounded from reset (bounded, 20 cycles)" PASS "$(prove clint.v "$f/clint_props.sv" bmc 20 '-DTICK=3 -DSEQ' clint_sequence_bounded)"
expect "cover: MTIP rises and falls, MSIP is raised and the high half advances" PASS "$(prove clint.v "$f/clint_props.sv" cover 20 '-DTICK=3 -DCOVER' clint_cover)"
expect "cover: the port sequence ends with the mtime above the old value" PASS "$(prove clint.v "$f/clint_props.sv" cover 20 '-DTICK=3 -DSEQ -DCOVER' clint_seq_cover)"

echo "gpio_cell"
mut_expose=(); mut_open=1
build gpio_cell cell gpio_cell -- 
expect "direction, output and masks change only by writes; pin read is the synchronized pin; status (bounded, 16 cycles)" PASS "$(prove cell.v "$f/gpio_cell_props.sv" bmc 16 '' cell_safety)"
expect "cover: a rise and a fall interrupt and a stable output are reachable" PASS "$(prove cell.v "$f/gpio_cell_props.sv" cover 14 '-DCOVER' cell_cover)"
build gpio_cell cell_low gpio_cell -- -gactive_low=true
expect "active low: the pin read is the inverted pin and the cell drives the inverted output (bounded, 16 cycles)" PASS "$(prove cell_low.v "$f/gpio_cell_props.sv" bmc 16 '-DACTIVE_LOW' cell_low_safety)"
expect "active low cover: a rise and a fall interrupt and a stable output are reachable" PASS "$(prove cell_low.v "$f/gpio_cell_props.sv" cover 14 '-DACTIVE_LOW -DCOVER' cell_low_cover)"
mut_open=0

echo "uart_fifo"
mut_expose=()
fgen=(-gdepth=3)
build uart_fifo fifo "${fifo_srcs[@]}" -- "${fgen[@]}"
expect "level, flags and acceptances follow a shifting reference queue; the oldest word is the first one in (bounded, 14 cycles, 3 words)" PASS "$(prove fifo.v "$f/uart_fifo_props.sv" bmc 14 '' fifo_safety)"
expect "cover: a push and a pop on a full queue, a push refused when full, and a push with a pop on an empty queue are reachable" PASS "$(prove fifo.v "$f/uart_fifo_props.sv" cover 14 '-DCOVER' fifo_cover)"

echo "flash_controller"
mut_expose=()
build flash_controller flashc "${flash_srcs[@]}" -- -gpage_bytes=16
expect "command pulse, registers, status read and page buffer follow the reference (bounded, 14 cycles, 4 words)" PASS "$(prove flashc.v "$f/flash_controller_props.sv" bmc 14 '' flashc_safety)"
expect "cover: a program command, a status with busy and refused, a write at the last word and a buffer read are reachable" PASS "$(prove flashc.v "$f/flash_controller_props.sv" cover 14 '-DCOVER' flashc_cover)"

echo "jtag_uart"
jtag_srcs=(synchronizer jtag_uart)
path_of[jtag_uart]="$root/src/UART/jtag/jtag_uart.vhd"
mut_expose=(); mut_open=0
build jtag_uart jtagu "${jtag_srcs[@]}" -- -glog2_depth=2
expect "CONTROL reads back its three bits; the interrupt is transmit-empty or error, each with its enable (bounded, 14 cycles, 4-byte queues)" PASS "$(prove jtagu.v "$f/jtag_uart_props.sv" bmc 14 '' jtagu_safety)"
expect "cover: a transmit-empty and an error interrupt, and a queue with bytes that holds the line low, are reachable" PASS "$(prove jtagu.v "$f/jtag_uart_props.sv" cover 14 '-DCOVER' jtagu_cover)"

echo "uart"
uart_exp=(rx_overrun tx_dropped rx_irq_enable tx_irq_enable err_irq_enable phy_new_rx_data phy_tx_busy phy_new_tx_data phy_rx_data:7 phy_tx_data:7 rx_fifo_data:7 rx_fifo_level:1 tx_fifo_level:1)
mut_expose=("${uart_exp[@]}")
ugen=(-gbaud_freq=0 -gbaud_limit=0 -grx_fifo_depth=3 -gtx_fifo_depth=3)
build uart uart "${uart_srcs[@]}" -- "${ugen[@]}"
expect "queue levels, overrun, dropped, mask, interrupt and readback follow the contract (induction)" PASS "$(prove uart.v "$f/uart_props.sv" prove 3 '-DREGS' uart_regs)"
expect "from any state: the same, with the PHY, the queues and the wrapper in any state (induction)" PASS "$(prove uart.v "$f/uart_props.sv" prove 3 '-DREGS -DANYSTATE' uart_regs_any)"
expect "cover: a dropped write, a write that starts a frame and a full transmit queue are reachable" PASS "$(prove uart.v "$f/uart_props.sv" cover 30 '-DREGS -DCOVER' uart_regs_cover)"
expect "cover: from any state, an overrun and a full receive queue that is read while a byte arrives are reachable" PASS "$(prove uart.v "$f/uart_props.sv" cover 200 '-DREGS -DANYSTATE -DCOVER' uart_regs_any_cover)"
expect "transmit frame: start, 8 data bits LSB first, stop, 16 cycles per bit (bounded, 200 cycles)" PASS "$(prove uart.v "$f/uart_props.sv" bmc 200 '-DTXF' uart_tx)"
expect "cover: a frame of 5A is transmitted" PASS "$(prove uart.v "$f/uart_props.sv" cover 100 '-DTXF -DCOVER' uart_tx_cover)"
expect "receive: the byte is sampled mid-bit despite noise at the edges, once, none lost (bounded, 200 cycles)" PASS "$(prove uart.v "$f/uart_props.sv" bmc 200 '-DRXF' uart_rx)"
expect "cover: a frame of A5 is received" PASS "$(prove uart.v "$f/uart_props.sv" cover 200 '-DRXF -DCOVER' uart_rx_cover)"

echo "sd_spi"
path_of[sd_spi_phy]="$root/src/SD/spi/sd_spi_phy.vhd"
path_of[sd_spi]="$root/src/SD/spi/sd_spi.vhd"
sd_srcs=(config_pkg uart_fifo sd_spi_phy sd_spi)
sd_exp=(phy_busy phy_done tx_fifo_empty rx_fifo_empty done_flag rx_overrun tx_dropped cs_assert divider:15)
sdgen=(-gclock_hz=2 -ginit_sclk_hz=1 -grx_fifo_depth=3 -gtx_fifo_depth=3)
mut_expose=("${sd_exp[@]}"); mut_open=0
build sd_spi sdspi "${sd_srcs[@]}" -- "${sdgen[@]}"
expect "CONTROL, DIVIDER, chip select, interrupt, sticky flags, STATUS and reset follow the contract (bounded, 24 cycles, 3-byte queues)" PASS "$(prove sdspi.v "$f/sd_spi_props.sv" bmc 24 '' sdspi_regs)"
expect "a byte has exactly 8 rising edges of SCLK, SCLK moves only while busy and MOSI idles high (bounded, 40 cycles)" PASS "$(prove sdspi.v "$f/sd_spi_props.sv" bmc 40 '-DBYTE' sdspi_byte)"
expect "cover: the done interrupt, the receive interrupt and a dropped write are reachable" PASS "$(prove sdspi.v "$f/sd_spi_props.sv" cover 40 '-DCOVER' sdspi_cover)"
expect "cover: a complete byte of 8 rising edges is reachable" PASS "$(prove sdspi.v "$f/sd_spi_props.sv" cover 40 '-DBYTE -DCOVER' sdspi_byte_cover)"

echo "sd_native"
path_of[sd_native_pkg]="$root/src/SD/native/sd_native_pkg.vhd"
path_of[sd_crc7]="$root/src/SD/native/sd_crc7.vhd"
path_of[sd_crc16]="$root/src/SD/native/sd_crc16.vhd"
path_of[sd_cmd]="$root/src/SD/native/sd_cmd.vhd"
mut_expose=(); mut_open=0
cp7="$f/sd_crc_props.sv"; cmdp="$f/sd_cmd_props.sv"
sdcmd_srcs=(sd_native_pkg sd_crc7 sd_cmd)
sdcmdgen=(-gncr_clocks=4 -ggap_clocks=2)
build sd_crc7 sdcrc7 sd_crc7 --
expect "CRC7 register is the remainder of the long division of the message by x^7 + x^3 + 1 (bounded, 52 cycles, 48-bit messages)" PASS "$(prove sdcrc7.v "$cp7" bmc 52 '' sdcrc7_ref)"
expect "CRC7: a message followed by its own CRC7 leaves the register at zero (bounded, 56 cycles)" PASS "$(prove sdcrc7.v "$cp7" bmc 56 '-DRESIDUE' sdcrc7_residue)"
expect "CRC7 of the 40 bits of CMD0 is 0x4A (bounded, 44 cycles)" PASS "$(prove sdcrc7.v "$cp7" bmc 44 '-DVEC' sdcrc7_vec)"
expect "cover: a message of 5 bits with a zero and a non-zero CRC7 is reachable" PASS "$(prove sdcrc7.v "$cp7" cover 12 '-DCOVER' sdcrc7_cover)"
expect "cover: the CRC7 residue check is reachable" PASS "$(prove sdcrc7.v "$cp7" cover 24 '-DRESIDUE -DCOVER' sdcrc7_residue_cover)"
build sd_crc16 sdcrc16 sd_crc16 --
expect "CRC16 register is the remainder of the long division of the message by x^16 + x^12 + x^5 + 1 (bounded, 52 cycles, 48-bit messages)" PASS "$(prove sdcrc16.v "$cp7" bmc 52 '-DCRC16' sdcrc16_ref)"
expect "CRC16: a message followed by its own CRC16 leaves the register at zero (bounded, 70 cycles)" PASS "$(prove sdcrc16.v "$cp7" bmc 70 '-DCRC16 -DRESIDUE' sdcrc16_residue)"
expect "CRC16 of the 72 bits of 123456789 is 0x31C3 (bounded, 76 cycles)" PASS "$(prove sdcrc16.v "$cp7" bmc 76 '-DCRC16 -DVEC' sdcrc16_vec)"
expect "cover: a message of 5 bits with a zero and a non-zero CRC16 is reachable" PASS "$(prove sdcrc16.v "$cp7" cover 12 '-DCRC16 -DCOVER' sdcrc16_cover)"
expect "cover: the CRC16 residue check is reachable" PASS "$(prove sdcrc16.v "$cp7" cover 40 '-DCRC16 -DRESIDUE -DCOVER' sdcrc16_residue_cover)"
build sd_cmd sdcmd "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
expect "with a free start and any strobe spacing, outputs move on falling edges only, the header bits are those of the accepted command and errors clear on start (bounded, 56 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 56 '' sdcmd_frame_free)"
expect "command frame is exactly 48 bits (start, transmission, index, argument, CRC7, end) at one strobe per cycle (bounded, 106 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 106 '-DFAST' sdcmd_frame)"
expect "without a response the timeout error comes after exactly ncr_clocks + gap_clocks rises, with no other error (bounded, 124 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 124 '-DTIMEOUT' sdcmd_timeout)"
expect "a valid short response (R1, R6, R7) is accepted with its index and argument and no error (bounded, 208 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 208 '-DFAST -DRESP' sdcmd_resp_short)"
expect "a short response without CRC7 and index checks (R3) is accepted whatever its CRC7 and index (bounded, 208 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 208 '-DFAST -DRESP -DNOCRC -DRSP=2' sdcmd_resp_nocrc)"
expect "a wrong CRC7 in a short response is reported as a CRC error and never as a valid response (bounded, 208 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 208 '-DFAST -DRESP -DBADCRC' sdcmd_resp_badcrc)"
expect "a wrong index in a short response is reported as an index error and never as a valid response (bounded, 208 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 208 '-DFAST -DRESP -DBADIDX' sdcmd_resp_badidx)"
expect "a short response whose end bit is low is reported as a frame error and never as a valid response (bounded, 208 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 208 '-DFAST -DRESP -DBADEND' sdcmd_resp_badend)"
expect "after a response the command waits for DAT0 high or the timeout before it ends (bounded, 216 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 216 '-DFAST -DRESP -DBUSY' sdcmd_resp_busy)"
expect "abort returns the command to idle on the next cycle, with no end of command (bounded, 24 cycles)" PASS "$(prove sdcmd.v "$cmdp" bmc 24 '-DABORT' sdcmd_abort)"
expect "cover: the frame is sent and a command ends" PASS "$(prove sdcmd.v "$cmdp" cover 110 '-DFAST -DCOVER' sdcmd_frame_cover)"
expect "cover: a command ends in a timeout" PASS "$(prove sdcmd.v "$cmdp" cover 124 '-DTIMEOUT -DCOVER' sdcmd_timeout_cover)"
expect "cover: a valid response is accepted and the command ends" PASS "$(prove sdcmd.v "$cmdp" cover 208 '-DFAST -DRESP -DCOVER' sdcmd_resp_cover)"

echo "console"
path_of[console]="$root/src/UART/console/console.vhd"
path_of[console_equiv]="$root/tests/vhdl/console_equiv.vhd"
console_srcs=(baudGen uartRx uartTx uart2BusTop_pkg uartTop uart_fifo uart synchronizer jtag_uart console console_equiv)
cp_="$f/console_props.sv"
mut_expose=(); mut_open=0
cgen_pins=(-gbackend=pinos -gbaud_freq=0 -gbaud_limit=0 -grx_fifo_depth=3 -gtx_fifo_depth=3)
cgen_inv=(-gbackend=pinos -gbaud_freq=0 -gbaud_limit=0 -grx_fifo_depth=3 -gtx_fifo_depth=3 -gtx_invert=true -grx_invert=true)
cgen_jtag=(-gbackend=jtag -glog2_depth=2)
build console_equiv console_pins "${console_srcs[@]}" -- "${cgen_pins[@]}"
expect "backend pinos: data read, interrupt, line and JTAG output equal those of the uart on the same inputs (bounded, 200 cycles)" PASS "$(prove console_pins.v "$cp_" bmc 200 '' console_pins)"
expect "cover: the pinos console returns data and raises the interrupt" PASS "$(prove console_pins.v "$cp_" cover 30 '-DCOVER' console_pins_cover)"
build console_equiv console_inv "${console_srcs[@]}" -- "${cgen_inv[@]}"
expect "backend pinos with TX and RX inverted: equal to the uart with an explicit inversion on each pin (bounded, 200 cycles)" PASS "$(prove console_inv.v "$cp_" bmc 200 '' console_inv)"
build console_equiv console_jtag "${console_srcs[@]}" -- "${cgen_jtag[@]}"
expect "backend jtag: data read, interrupt, line and JTAG output equal those of the jtag_uart on the same inputs (bounded, 30 cycles)" PASS "$(prove console_jtag.v "$cp_" bmc 30 '' console_jtag)"
expect "cover: the jtag console returns data and raises the interrupt" PASS "$(prove console_jtag.v "$cp_" cover 30 '-DCOVER' console_jtag_cover)"

# Mutants of the VHDL: each defect must make a proof fail.
# mutant <source name> <props> <entity> <defines> <name> <sed expression> <bmc depth> <sources...> -- [generics]
mutant() {
  local sname="$1" props="$2" ent="$3" defs="$4" name="$5" expr="$6" depth="$7"; shift 7
  local copy="$out/mut_$name.vhd"
  # The mutant is cut from the source with every run of blanks (spaces and tabs) squeezed to one space, and the sed
  # expression is squeezed the same way, so the edit does not depend on the column alignment that the formatter
  # (vsg --fix) owns. VHDL ignores the blanks, so the mutant means the same.
  expr="$(printf '%s' "$expr" | sed 's/[[:space:]]\+/ /g')"
  sed 's/[[:space:]]\+/ /g' "${path_of[$sname]}" | sed "$expr" > "$copy"
  sed 's/[[:space:]]\+/ /g' "${path_of[$sname]}" | cmp -s - "$copy" && { echo "mutant $name: the edit did not change the file"; exit 1; }
  mut_from="${path_of[$sname]}"; mut_to="$copy"
  build "$ent" "mut_$name" "$@"
  mut_from=""; mut_to=""
  expect "mutant $name is caught" FAIL "$(prove "mut_$name.v" "$props" bmc "$depth" "$defs" "mut_$name")"
}

mut_expose=(); mut_open=0
ap="$f/alu_ge_unsigned_props.sv"
mutant alu_ge_unsigned "$ap" alu_ge_unsigned '-DWIDTH=8' alu_strict "s/c(0)  <= '1';/c(0)  <= '0';/" 2 alu_ge_unsigned -- -gdata_width=8
mutant alu_ge_unsigned "$ap" alu_ge_unsigned '-DWIDTH=8' alu_no_invert "s/b_inv <= not i_source_2;/b_inv <= i_source_2;/" 2 alu_ge_unsigned -- -gdata_width=8
mutant counter_overflow "$f/counter_overflow_props.sv" counter_overflow '-DWIDTH=8' ovf_swapped "s/i_source_1 => i_counter_value,/i_source_1 => i_top_value,/;s/i_source_2 => i_top_value, /i_source_2 => i_counter_value,/" 2 alu_ge_unsigned counter_overflow -- -gdata_width=8
mutant alu_ge_unsigned "$f/counter_overflow_props.sv" counter_overflow '-DWIDTH=8' ovf_strict "s/c(0)  <= '1';/c(0)  <= '0';/" 2 alu_ge_unsigned counter_overflow -- -gdata_width=8
pp="$f/clock_prescaler_props.sv"
mutant clock_prescaler "$pp" clock_prescaler '-DWIDTH=3' presc_unregistered "s/o_tick <= tick_out;/o_tick <= comp_result;/" 40 alu_ge_unsigned clock_prescaler -- -gdata_width=3
mutant alu_ge_unsigned "$pp" clock_prescaler '-DWIDTH=3' presc_strict "s/c(0)  <= '1';/c(0)  <= '0';/" 40 alu_ge_unsigned clock_prescaler -- -gdata_width=3
mutant clock_prescaler "$pp" clock_prescaler '-DWIDTH=3' presc_no_clear "s/counter_clear <= i_rst or comp_result;/counter_clear <= i_rst;/" 40 alu_ge_unsigned clock_prescaler -- -gdata_width=3

mut_expose=("${timer_exp[@]}")
tp="$f/timer_props.sv"
mutant timer "$tp" timer '' timer_top_enable "s/i_enable => wr_en(3),/i_enable => wr_en(4),/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_prescaler_enable "s/i_enable => wr_en(6),/i_enable => wr_en(5),/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_top_reset "s/clear_value => '1'/clear_value => '0'/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_mode_inverted "s/(overflow and not mode_signal)/(overflow and mode_signal)/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_start_ignored "s/start_signal and tick and not/tick and not/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_mask_ignored "s/i_sel => irq_mask,/i_sel => '1',/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_status_not_cleared "s/ovf_clear      <= i_rst or wr_en(5);/ovf_clear      <= i_rst;/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_level_not_edge "s/overflow_pulse <= overflow and not overflow_prev;/overflow_pulse <= overflow;/" 8 "${timer_srcs[@]}" --
mutant timer "$tp" timer '' timer_pwm_inverted "s/pwm_inverted   <= not pwm_alu;/pwm_inverted   <= pwm_alu;/" 8 "${timer_srcs[@]}" --
mutant timer_operation_decoder "$tp" timer '' timer_read_select "s/\"000\" when ADDR_TIMER_LOAD,/\"001\" when ADDR_TIMER_LOAD,/" 8 "${timer_srcs[@]}" --
mutant timer_operation_decoder "$tp" timer '' timer_write_address "s/o_wr_en(WR_LOAD_TOP_I)   <= i_write when i_address = ADDR_TOP /o_wr_en(WR_LOAD_TOP_I)   <= i_write when i_address = ADDR_DUTY_CYCLE /" 8 "${timer_srcs[@]}" --

mut_expose=("${clint_exp[@]}")
cp_="$f/clint_props.sv"
mutant clint "$cp_" clint '-DTICK=3' clint_msip_bit "s/i_d      => i_data_in(0 downto 0),/i_d      => i_data_in(1 downto 1),/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant clint "$cp_" clint '-DTICK=3' clint_cmp_reset_zero "s/clear_value => '1'/clear_value => '0'/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant clint "$cp_" clint '-DTICK=3' clint_cmp_hi_address "s/wr_cmp_hi   <= i_write when i_address = ADDR_MTIMECMP_HI/wr_cmp_hi   <= i_write when i_address = ADDR_MTIMECMP_LO/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant clint "$cp_" clint '-DTICK=3' clint_mtip_unregistered "s/o_irq_timer    <= timer_irq;/o_irq_timer    <= timer_ge;/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant clint "$cp_" clint '-DTICK=3' clint_read_swapped "s/mtime_lo                   when ADDR_MTIME_LO,/mtime_hi                   when ADDR_MTIME_LO,/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant clint "$cp_" clint '-DTICK=3' clint_tick_early "s/tick <= '1' when phase = tick_cycles - 1/tick <= '1' when phase = 0/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant clint "$cp_" clint '-DTICK=3' clint_mtime_hi_address "s/wr_mtime_hi <= i_write when i_address = ADDR_MTIME_HI /wr_mtime_hi <= i_write when i_address = ADDR_MTIME_LO /" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant counter64 "$cp_" clint '-DTICK=3' mtime_carry_lost "s/lo = LO_ALL_ONES/lo(lo'high) = '1'/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant counter64 "$cp_" clint '-DTICK=3' mtime_hi_incoherent "s/unsigned(hi_inc), word_t'length)) when carry = '1' else/unsigned(hi), word_t'length)) when carry = '1' else/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant counter64 "$cp_" clint '-DTICK=3' mtime_write_loses "s/lo_nxt <= i_wdata(LO_WIDTH - 1 downto 0) when i_we_lo = '1' else lo_inc;/lo_nxt <= lo_inc;/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant alu_ge_unsigned "$cp_" clint '-DTICK=3' clint_strict_compare "s/c(0)  <= '1';/c(0)  <= '0';/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"
mutant clint "$cp_" clint '-DTICK=3 -DSEQ' clint_seq_cmp_clear_not_ones "s/clear_value => '1'/clear_value => '0'/" 20 "${clint_srcs[@]}" -- "${cgen[@]}"

mut_expose=()
fp="$f/flash_controller_props.sv"
mutant flash_controller "$fp" flash_controller '' flashc_ptr_stuck "s/ptr <= ptr + 1;/ptr <= ptr;/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_cmd_any_write "s/wr_cmd      <= i_write when i_address = REG_CMD else '0';/wr_cmd      <= i_write;/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_status_swapped "s/o_data_out(0) <= i_busy;/o_data_out(0) <= i_wel;/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_addr_any_write "s/if i_write = '1' and i_address = REG_ADDR then/if i_write = '1' then/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_op_shifted "s/o_cmd_op    <= i_data_in(2 downto 0);/o_cmd_op    <= i_data_in(3 downto 1);/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_word_misplaced "s/page(to_integer(ptr)) <= i_data_in;/page(to_integer(ptr + 1)) <= i_data_in;/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_read_ungated "s/if i_read = '1' then/if true then/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_ptr_write_ignored "s/if i_write = '1' and i_address = REG_BUF_PTR then/if false then/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_done_on_busy_rising "s/ev_done    <= busy_prev and not i_busy;/ev_done    <= i_busy and not busy_prev;/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_refused_level "s/ev_refused <= i_refused and not refused_prev;/ev_refused <= i_refused;/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_irq_mask_ignored "s/o_irq      <= '1' when (irq_status and irq_enable) \/= \"00\" else '0';/o_irq      <= '1' when irq_status \/= \"00\" else '0';/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_w1c_clears_all "s/irq_status <= irq_status and not i_data_in(1 downto 0);/irq_status <= (others => '0');/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_event_loses_to_clear "s/        if ev_done = '1' then/        if ev_done = '1' and not (i_write = '1' and i_address = REG_IRQ_STATUS) then/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16
mutant flash_controller "$fp" flash_controller '' flashc_status_bit_lost "s/o_data_out(2) <= i_refused;/o_data_out(2) <= '0';/" 14 "${flash_srcs[@]}" -- -gpage_bytes=16

mut_expose=(); mut_open=1
gp="$f/gpio_cell_props.sv"
mutant gpio_cell "$gp" gpio_cell '' cell_dir_always "s/i_enable => i_wr_signals(0),/i_enable => '1',/" 10 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_no_set_clear "s/out_enable    <= i_wr_signals(1) or (i_wr_signals(2) and i_data_in);/out_enable    <= i_wr_signals(1);/" 10 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_toggle_is_load "s/i_d3  => toggle_vector,/i_d3  => load_vector,/" 10 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_mask_ignored "s/irq_set       <= interrupt_logic and irq_mask;/irq_set       <= interrupt_logic;/" 10 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_fall_uses_rise "s/(irq_fall_mask and (not pin_input and prev_pin_input))/(irq_rise_mask and (not pin_input and prev_pin_input))/" 10 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_status_not_cleared "s/irq_clear     <= i_rst or i_wr_signals(6);/irq_clear     <= i_rst;/" 10 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_level_ignored "s/interrupt_logic <= level_logic when irq_level_mode = '1' else edge_logic;/interrupt_logic <= edge_logic;/" 16 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_level_fall_is_high "s/(irq_fall_mask and not pin_input)/(irq_fall_mask and pin_input)/" 16 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '' cell_level_mode_write "s/i_enable => i_wr_signals(7),/i_enable => i_wr_signals(3),/" 16 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '-DACTIVE_LOW' cell_low_drive_not_inverted "s/drive_logic <= not out_reg when active_low else out_reg;/drive_logic <= out_reg;/" 10 gpio_cell -- -gactive_low=true
mutant gpio_cell "$gp" gpio_cell '-DACTIVE_LOW' cell_low_input_not_inverted "s/pin_logic   <= not io_gpio_pin when active_low else io_gpio_pin;/pin_logic   <= io_gpio_pin;/" 10 gpio_cell -- -gactive_low=true
mutant gpio_cell "$gp" gpio_cell '' cell_pin_not_driven "s/i_enable => dir_reg,/i_enable => '0',/" 10 gpio_cell --
mut_open=0

mut_expose=()
fp="$f/uart_fifo_props.sv"
mutant uart_fifo "$fp" uart_fifo '' fifo_no_wrap "s/return 0;/return pointer;/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"
mutant uart_fifo "$fp" uart_fifo '' fifo_overwrite_when_full "s/(count < depth or pop_accepted = '1')/true/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"
mutant uart_fifo "$fp" uart_fifo '' fifo_no_reuse_on_pop "s/(count < depth or pop_accepted = '1')/(count < depth)/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"
mutant uart_fifo "$fp" uart_fifo '' fifo_pop_not_counted "s/count <= count - 1;/count <= count;/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"
mutant uart_fifo "$fp" uart_fifo '' fifo_push_not_counted "s/count <= count + 1;/count <= count;/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"
mutant uart_fifo "$fp" uart_fifo '' fifo_pop_keeps_head "s/read_pointer <= next_pointer(read_pointer);/read_pointer <= 0;/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"
mutant uart_fifo "$fp" uart_fifo '' fifo_empty_shows_data "s/else (others => '0');/else memory(read_pointer);/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"
mutant uart_fifo "$fp" uart_fifo '' fifo_pop_when_empty "s/i_pop = '1' and count > 0/i_pop = '1'/" 14 "${fifo_srcs[@]}" -- "${fgen[@]}"

mut_expose=(); jp="$f/jtag_uart_props.sv"
mutant jtag_uart "$jp" jtag_uart '' jtagu_tx_empty_inverted "s/(tx_empty and tx_irq_enable)/((not tx_empty) and tx_irq_enable)/" 14 "${jtag_srcs[@]}" -- -glog2_depth=2
mutant jtag_uart "$jp" jtag_uart '' jtagu_error_mask_ignored "s/(lost and err_irq_enable)/lost/" 14 "${jtag_srcs[@]}" -- -glog2_depth=2
mutant jtag_uart "$jp" jtag_uart '' jtagu_control_bit_swapped "s/tx_irq_enable  <= i_wdata(1);/tx_irq_enable  <= i_wdata(2);/" 14 "${jtag_srcs[@]}" -- -glog2_depth=2
mutant jtag_uart "$jp" jtag_uart '' jtagu_lost_stays "s/            lost <= '0';/            null;/" 14 "${jtag_srcs[@]}" -- -glog2_depth=2
mut_expose=("${uart_exp[@]}")
up="$f/uart_props.sv"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_overrun_ignored "s/rx_overrun <= '1';/null;/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_drop_not_flagged "s/tx_dropped <= '1';/null;/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_w1c_wrong_bit "s/if i_data_in(2) = '1' then/if i_data_in(3) = '1' then/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_tx_pops_when_busy "s/when phy_tx_busy = '0' and tx_fifo_empty = '0'/when tx_fifo_empty = '0'/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_rx_pops_on_any_read "s/when i_read = '1' and i_address = RX_DATA_ADDRESS/when i_read = '1'/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_irq_mask_ignored "s/((not rx_fifo_empty) and rx_irq_enable)/(not rx_fifo_empty)/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_irq_tx_empty_inverted "s/or (tx_fifo_empty and tx_irq_enable)/or ((not tx_fifo_empty) and tx_irq_enable)/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_irq_error_ignores_drop "s/((rx_overrun or tx_dropped) and err_irq_enable)/(rx_overrun and err_irq_enable)/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_irq_error_mask_ignored "s/((rx_overrun or tx_dropped) and err_irq_enable)/(rx_overrun or tx_dropped)/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_control_bit_swapped "s/tx_irq_enable  <= i_data_in(1);/tx_irq_enable  <= i_data_in(2);/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_status_ready_inverted "s/value(1) := not tx_fifo_full;/value(1) := tx_fifo_full;/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_idle_ignores_phy "s/value(6) := tx_fifo_empty and not phy_tx_busy;/value(6) := tx_fifo_empty;/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uart "$up" uart '-DREGS -DANYSTATE' uart_levels_swapped "s/to_unsigned(rx_fifo_level, 8)/to_unsigned(tx_fifo_level, 8)/" 4 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uartTx "$up" uart '-DTXF' uart_tx_stop_low "s/dataBuf <= '1' \& dataBuf(8 downto 1);/dataBuf <= '0' \& dataBuf(8 downto 1);/" 200 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uartTx "$up" uart '-DTXF' uart_tx_start_high "s/dataBuf <= txData \& '0';/dataBuf <= txData \& '1';/" 200 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uartTx "$up" uart '-DTXF' uart_tx_short_frame "s/bitCount = \"1001\"/bitCount = \"1000\"/" 200 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uartRx "$up" uart '-DRXF' uart_rx_early_sample "s/count16 = \"0111\"/count16 = \"0000\"/" 200 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uartRx "$up" uart '-DRXF' uart_rx_late_sample "s/count16 = \"0111\"/count16 = \"1110\"/" 200 "${uart_srcs[@]}" -- "${ugen[@]}"
mutant uartRx "$up" uart '-DRXF' uart_rx_msb_first "s/dataBuf <= inSync(1) \& dataBuf(7 downto 1);/dataBuf <= dataBuf(6 downto 0) \& inSync(1);/" 200 "${uart_srcs[@]}" -- "${ugen[@]}"

mut_expose=()
cp_="$f/console_props.sv"
mutant console "$cp_" console_equiv '' console_tx_polarity "s/o_tx    <= not uart_tx when tx_invert else uart_tx;/o_tx    <= uart_tx;/" 200 "${console_srcs[@]}" -- "${cgen_inv[@]}"
mutant console "$cp_" console_equiv '' console_rx_polarity "s/uart_rx <= not i_rx when rx_invert else i_rx;/uart_rx <= i_rx;/" 200 "${console_srcs[@]}" -- "${cgen_inv[@]}"
mutant console "$cp_" console_equiv '' console_address_bits "s/i_address  => i_addr(1 downto 0),/i_address  => i_addr(2 downto 1),/" 200 "${console_srcs[@]}" -- "${cgen_pins[@]}"
mutant console "$cp_" console_equiv '' console_read_strobe "s/i_read     => i_re,/i_read     => i_we,/" 200 "${console_srcs[@]}" -- "${cgen_pins[@]}"
mutant console "$cp_" console_equiv '' console_jtag_write_strobe "s/i_we        => i_we,/i_we        => i_re,/" 30 "${console_srcs[@]}" -- "${cgen_jtag[@]}"


mut_expose=("${sd_exp[@]}")
sp="$f/sd_spi_props.sv"
mutant sd_spi "$sp" sd_spi '' sdspi_cs_bit "s/cs_assert <= i_data_in(0);/cs_assert <= i_data_in(1);/" 24 "${sd_srcs[@]}" -- "${sdgen[@]}"
mutant sd_spi "$sp" sd_spi '' sdspi_done_enable_bit "s/done_irq_enable <= i_data_in(3);/done_irq_enable <= i_data_in(4);/" 24 "${sd_srcs[@]}" -- "${sdgen[@]}"
mutant sd_spi "$sp" sd_spi '' sdspi_divider_address "s/if i_write = '1' and i_address = DIVIDER_ADDRESS then/if i_write = '1' and i_address = CONTROL_ADDRESS then/" 24 "${sd_srcs[@]}" -- "${sdgen[@]}"
mutant sd_spi "$sp" sd_spi '' sdspi_done_not_cleared "s/done_flag <= done_flag and not i_data_in(5);/done_flag <= done_flag;/" 24 "${sd_srcs[@]}" -- "${sdgen[@]}"
mutant sd_spi "$sp" sd_spi '' sdspi_rx_valid_inverted "s/value(0) := not rx_fifo_empty;/value(0) := rx_fifo_empty;/" 24 "${sd_srcs[@]}" -- "${sdgen[@]}"
mutant sd_spi "$sp" sd_spi '' sdspi_busy_ignores_done "s/value(3) := phy_busy or phy_done or not tx_fifo_empty;/value(3) := phy_busy or not tx_fifo_empty;/" 24 "${sd_srcs[@]}" -- "${sdgen[@]}"
mutant sd_spi_phy "$sp" sd_spi '-DBYTE' sdspi_phy_short_byte "s/if bits_left = 1 then/if bits_left = 2 then/" 40 "${sd_srcs[@]}" -- "${sdgen[@]}"
mutant sd_spi_phy "$sp" sd_spi '-DBYTE' sdspi_phy_mosi_low "s/tx_shift <= tx_shift(6 downto 0) \& '1';/tx_shift <= tx_shift(6 downto 0) \& '0';/" 40 "${sd_srcs[@]}" -- "${sdgen[@]}"


mut_expose=()
c7="$f/sd_crc_props.sv"; cm="$f/sd_cmd_props.sv"
mutant sd_crc7 "$c7" sd_crc7 '' sdcrc7_poly "s/:= \"0001001\";/:= \"0001011\";/" 52 sd_crc7 --
mutant sd_crc7 "$c7" sd_crc7 '-DVEC' sdcrc7_poly_vec "s/:= \"0001001\";/:= \"0001101\";/" 44 sd_crc7 --
mutant sd_crc7 "$c7" sd_crc7 '' sdcrc7_no_feedback_input "s/feedback := crc(6) xor i_bit;/feedback := crc(6);/" 52 sd_crc7 --
mutant sd_crc7 "$c7" sd_crc7 '' sdcrc7_clear_ignored "s/if i_rst = '1' or i_clear = '1' then/if i_rst = '1' then/" 52 sd_crc7 --
mutant sd_crc7 "$c7" sd_crc7 '' sdcrc7_enable_ignored "s/elsif i_enable = '1' then/elsif true then/" 52 sd_crc7 --
mutant sd_crc7 "$c7" sd_crc7 '-DRESIDUE' sdcrc7_shift_right "s/crc <= crc(5 downto 0) \& '0';/crc <= '0' \& crc(6 downto 1);/" 56 sd_crc7 --
mutant sd_crc16 "$c7" sd_crc16 '-DCRC16' sdcrc16_poly "s/:= \"0001000000100001\";/:= \"0001000000100011\";/" 52 sd_crc16 --
mutant sd_crc16 "$c7" sd_crc16 '-DCRC16 -DVEC' sdcrc16_poly_vec "s/:= \"0001000000100001\";/:= \"0001000000100101\";/" 76 sd_crc16 --
mutant sd_crc16 "$c7" sd_crc16 '-DCRC16' sdcrc16_no_feedback_input "s/feedback := crc(15) xor i_bit;/feedback := crc(15);/" 52 sd_crc16 --
mutant sd_crc16 "$c7" sd_crc16 '-DCRC16' sdcrc16_clear_ignored "s/if i_rst = '1' or i_clear = '1' then/if i_rst = '1' then/" 52 sd_crc16 --
mutant sd_crc16 "$c7" sd_crc16 '-DCRC16' sdcrc16_enable_ignored "s/elsif i_enable = '1' then/elsif true then/" 52 sd_crc16 --
mutant sd_crc16 "$c7" sd_crc16 '-DCRC16 -DRESIDUE' sdcrc16_shift_right "s/crc <= crc(14 downto 0) \& '0';/crc <= '0' \& crc(15 downto 1);/" 70 sd_crc16 --

mutant sd_cmd "$cm" sd_cmd '-DFAST' sdcmd_end_bit_low "s/state <= S_SEND_END;/state <= S_SEND_END; cmd_out <= '0';/" 106 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST' sdcmd_crc_bit_order "s/cmd_out <= crc_value(CMD_LAST_POS - 1 - pos);/cmd_out <= crc_value(pos - CMD_HEADER_BITS);/" 106 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST' sdcmd_short_header "s/if pos < CMD_HEADER_BITS then/if pos < CMD_HEADER_BITS - 1 then/" 106 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST' sdcmd_crc_wrong_bit "s/crc_bit <= frame(CMD_HEADER_BITS - 1);/crc_bit <= frame(CMD_HEADER_BITS - 2);/" 106 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST' sdcmd_launch_on_rise "s/if i_fall = '1' then/if i_rise = '1' then/" 106 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DTIMEOUT' sdcmd_timeout_late "s/elsif wait_cnt = ncr_clocks - 1 then/elsif wait_cnt = ncr_clocks then/" 124 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DTIMEOUT' sdcmd_gap_short "s/if wait_cnt = gap_clocks - 1 then/if wait_cnt = gap_clocks - 2 then/" 124 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP' sdcmd_crc_check_inverted "s/and rx_crc \/= crc_value then/and rx_crc = crc_value then/" 208 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP -DBADIDX' sdcmd_index_check_off "s/if response_r = RSP_SHORT and rsp_shift(37 downto 32) \/= index_r then/if response_r = RSP_NONE and rsp_shift(37 downto 32) \/= index_r then/" 208 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP' sdcmd_body_first_late "s/if pos >= body_first and pos <= body_last then/if pos > body_first and pos <= body_last then/" 208 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP' sdcmd_crc_range_short "s/bit_cnt <= SHORT_HEAD_LAST then/bit_cnt < SHORT_HEAD_LAST then/" 208 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP' sdcmd_rx_crc_range "s/if pos > body_last and pos <= crc_last then/if pos >= body_last and pos <= crc_last then/" 208 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP -DBADEND' sdcmd_end_check_off "s/if i_cmd \/= '1' then/if i_cmd \/= '1' and false then/" 208 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP -DBADCRC' sdcmd_ok_on_error "s/resp_ok <= not (crc_bad or index_bad or frame_bad);/resp_ok <= '1';/" 208 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DFAST -DRESP -DBUSY' sdcmd_busy_polarity "s/if i_dat0 = '1' then/if i_dat0 = '0' then/" 216 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"
mutant sd_cmd "$cm" sd_cmd '-DABORT' sdcmd_abort_ignored "s/if i_rst = '1' or i_abort = '1' then/if i_rst = '1' then/" 24 "${sdcmd_srcs[@]}" -- "${sdcmdgen[@]}"


# PLIC (own file, like the external interrupt controller).
source "$root/formal/plic.sh"

[ -s "$warnings" ] && { echo "formal: $(wc -l < "$warnings") warning(s) found; a warning is an error (see above)"; fail=1; }
[ "$fail" -eq 0 ] && echo "formal: all expectations met" || { echo "formal: FAILED (logs in build/formal)"; exit 1; }

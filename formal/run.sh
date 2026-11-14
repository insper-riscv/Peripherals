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
gpio_srcs=(gpio_operation_decoder gpio_cell)
gpio_block_srcs=(config_pkg gpio_pkg gpio_operation_decoder gpio_cell gpio_group gpio)
clint_srcs=(alu_ge_unsigned clint_consts config_pkg counter64 clint)
fifo_srcs=(uart_fifo)
flash_srcs=(config_pkg flash_controller)
uart_srcs=(baudGen uartRx uartTx uart2BusTop_pkg uartTop uart_fifo uart)
declare -A path_of
for n in "${common[@]}"; do path_of[$n]="$root/src/common/src/$n.vhd"; done
for n in "${timer_srcs[@]}"; do path_of[$n]="$root/src/TIMER/soc/$n.vhd"; done
for n in gpio_pkg gpio_operation_decoder gpio_cell gpio_group gpio; do path_of[$n]="$root/src/GPIO/soc/$n.vhd"; done
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
# Setup of the mutants of the block being proved: the sources, the generics, the signals exposed and.
mut_srcs=(); mut_gen=(); mut_expose=(); mut_pins=0

# open_pins <netlist>: the bidirectional pin vector of the GPIO block becomes an input (what each pin is worth) and an
# output (what the block drives; a floating pin is zero, as build turns 1'bz into zero). The logic is the same.
open_pins() {
  sed -i -E -e 's/inout  \[([0-9]+):0\] io_gpio_pins\);/input  [\1:0] i_pins,\n   output [\1:0] o_pins_drv);/' \
         -e 's/^  assign io_gpio_pins = /  assign o_pins_drv = /' \
         -e '/o_pins_drv|i_pins,/! s/io_gpio_pins/i_pins/g' "$1"
  grep -q 'o_pins_drv' "$1" && grep -q 'i_pins' "$1" || { echo "open_pins: the pins of $1 were not found"; exit 1; }
}

# build <entity> <name> <sources...> -- [generics]: netlist plus the exposure of the block.
build() {
  netlist "$@"
  # A floating (tri-state) output has no value to prove and Yosys warns about it: it becomes zero, as the pin of the
  # pin of the GPIO tristate does. The properties look at the registers behind such an output, not at the output.
  sed -i "s/1'b[zZ]/1'b0/g" "$2.v"
  [ "${#mut_expose[@]}" -gt 0 ] && expose "$2.v" "${mut_expose[@]}"
  [ "$mut_pins" = 1 ] && open_pins "$2.v"
  return 0
}

echo "alu_ge_unsigned"
mut_expose=()
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
mut_expose=()
build gpio_cell cell gpio_cell -- 
expect "direction, output and masks change only by writes; pin read is the synchronized pin; status (bounded, 16 cycles)" PASS "$(prove cell.v "$f/gpio_cell_props.sv" bmc 16 '' cell_safety)"
expect "cover: a rise and a fall interrupt and a stable output are reachable" PASS "$(prove cell.v "$f/gpio_cell_props.sv" cover 14 '-DCOVER' cell_cover)"
build gpio_cell cell_low gpio_cell -- -gactive_low=true
expect "active low: the pin read is the inverted pin and the cell drives the inverted output (bounded, 16 cycles)" PASS "$(prove cell_low.v "$f/gpio_cell_props.sv" bmc 16 '-DACTIVE_LOW' cell_low_safety)"
expect "active low cover: a rise and a fall interrupt and a stable output are reachable" PASS "$(prove cell_low.v "$f/gpio_cell_props.sv" cover 14 '-DACTIVE_LOW -DCOVER' cell_low_cover)"
build gpio_cell cell_in gpio_cell -- -gdir_mode=1
expect "fixed input: DIR reads zero whatever is written, the pin is never driven (bounded, 16 cycles)" PASS "$(prove cell_in.v "$f/gpio_cell_props.sv" bmc 16 '-DFIXED_IN' cell_in_safety)"
expect "fixed input cover: a rise and a fall interrupt on the input are reachable" PASS "$(prove cell_in.v "$f/gpio_cell_props.sv" cover 14 '-DFIXED_IN -DCOVER' cell_in_cover)"
build gpio_cell cell_out gpio_cell -- -gdir_mode=2
expect "fixed output: DIR reads one whatever is written, the pin is always driven (bounded, 16 cycles)" PASS "$(prove cell_out.v "$f/gpio_cell_props.sv" bmc 16 '-DFIXED_OUT' cell_out_safety)"
expect "fixed output cover: a rise and a fall interrupt and a stable output are reachable" PASS "$(prove cell_out.v "$f/gpio_cell_props.sv" cover 14 '-DFIXED_OUT -DCOVER' cell_out_cover)"

echo "gpio"
# Partition A: 9 pins, groups [[0,1,2,3],[5,6],[7]]; pin 4 (output only, active low) and pin 8 are off; pins 1 and 4
# are output only, 3 and 6 input only, 1, 4 and 5 active low. Partition B: 6 pins, groups [[3,2,1,0],[4,5]], all free.
mut_expose=(); mut_pins=1
gpio_a=(-gpin_count=9 -ggroup_count=3 -gmember_count=7 -ggroup_sizes=000000010000001000000100
        -ggroup_members=00000111000001100000010100000011000000100000000100000000
        -gpin_dirs=000001001001001000 -gpin_active_low=000110010)
gpio_b=(-gpin_count=6 -ggroup_count=2 -gmember_count=6 -ggroup_sizes=0000001000000100
        -ggroup_members=000001010000010000000000000000010000001000000011
        -gpin_dirs=000000000000 -gpin_active_low=000000)
build gpio gpio_a "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
expect "partition A: DIR and OUT read as the model per group, the other words and groups read zero, each pin is driven as its group bit says, off pins hold (bounded, 8 cycles)" PASS "$(prove gpio_a.v "$f/gpio_props.sv" bmc 8 '-DPART_A' gpio_a_safety)"
expect "cover: partition A drives a pin of each group, a held pin and a fixed output" PASS "$(prove gpio_a.v "$f/gpio_props.sv" cover 8 '-DPART_A -DCOVER' gpio_a_cover)"
build gpio gpio_b "${gpio_block_srcs[@]}" -- "${gpio_b[@]}"
expect "partition B: the same, with a group that lists its pins in reverse order (bounded, 8 cycles)" PASS "$(prove gpio_b.v "$f/gpio_props.sv" bmc 8 '-DPART_B' gpio_b_safety)"
expect "cover: partition B drives every pin of the first group" PASS "$(prove gpio_b.v "$f/gpio_props.sv" cover 8 '-DPART_B -DCOVER' gpio_b_cover)"
mut_pins=0

echo "seg_display"
path_of[hex_to_seg7]="$root/src/display/soc/hex_to_seg7.vhd"
path_of[seg_display]="$root/src/display/soc/seg_display.vhd"
display_srcs=(config_pkg gpio_pkg hex_to_seg7 seg_display)
# Partition A: 8 digits, groups [[0,1,2,3],[5,6]]; digits 4 and 7 are off. Partition B: 6 digits, one group [[1]].
disp_a=(-gdigits=8 -ggroup_count=2 -gmember_count=6 -ggroup_sizes=0000001000000100
        -ggroup_members=000001100000010100000011000000100000000100000000)
disp_b=(-gdigits=6 -ggroup_count=1 -gmember_count=1 -ggroup_sizes=00000001 -ggroup_members=00000001)
build seg_display disp_a "${display_srcs[@]}" -- "${disp_a[@]}"
expect "partition A: the digit k of a group is the nibble k of its word 0, other words and groups read zero, the digits that are off stay blank (bounded, 8 cycles)" PASS "$(prove disp_a.v "$f/seg_display_props.sv" bmc 8 '-DPART_A' disp_a_safety)"
expect "cover: partition A writes the two groups and reads a group back" PASS "$(prove disp_a.v "$f/seg_display_props.sv" cover 8 '-DPART_A -DCOVER' disp_a_cover)"
build seg_display disp_b "${display_srcs[@]}" -- "${disp_b[@]}"
expect "partition B: a single digit in a group, the other five digits blank (bounded, 8 cycles)" PASS "$(prove disp_b.v "$f/seg_display_props.sv" bmc 8 '-DPART_B' disp_b_safety)"
expect "cover: partition B writes the digit and reads it back" PASS "$(prove disp_b.v "$f/seg_display_props.sv" cover 8 '-DPART_B -DCOVER' disp_b_cover)"

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
jtag_srcs=(synchronizer config_pkg jtag_uart)
path_of[jtag_uart]="$root/src/UART/jtag/jtag_uart.vhd"
mut_expose=()
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

echo "console"
path_of[console]="$root/src/UART/console/console.vhd"
path_of[console_equiv]="$root/tests/vhdl/console_equiv.vhd"
console_srcs=(baudGen uartRx uartTx uart2BusTop_pkg uartTop uart_fifo uart synchronizer config_pkg jtag_uart console console_equiv)
cp_="$f/console_props.sv"
mut_expose=()
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

mut_expose=()
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

mut_expose=()
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
mutant gpio_cell "$gp" gpio_cell '-DACTIVE_LOW' cell_low_input_not_inverted "s/pin_logic <= not i_pin when active_low else i_pin;/pin_logic <= i_pin;/" 10 gpio_cell -- -gactive_low=true
mutant gpio_cell "$gp" gpio_cell '' cell_pin_not_driven "s/o_pin_en <= dir_reg;/o_pin_en <= '0';/" 10 gpio_cell --
mutant gpio_cell "$gp" gpio_cell '-DFIXED_IN' cell_fixed_in_follows_write "s/dir_reg <= dir_written when dir_mode = 0 else '0' when dir_mode = 1 else '1';/dir_reg <= dir_written;/" 10 gpio_cell -- -gdir_mode=1
mutant gpio_cell "$gp" gpio_cell '-DFIXED_OUT' cell_fixed_out_follows_write "s/dir_reg <= dir_written when dir_mode = 0 else '0' when dir_mode = 1 else '1';/dir_reg <= dir_written;/" 10 gpio_cell -- -gdir_mode=2

mut_expose=(); mut_pins=1
gb="$f/gpio_props.sv"
mutant gpio "$gb" gpio '-DPART_A' gpio_block_all_groups_hit "s/hit <= '1' when group_sel = g else '0';/hit <= '1';/" 8 "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
mutant gpio "$gb" gpio '-DPART_B' gpio_block_pin_reversed "s/constant PIN : natural := field_value(group_members, FIRST + k);/constant PIN : natural := field_value(group_members, FIRST + SIZE - 1 - k);/" 8 "${gpio_block_srcs[@]}" -- "${gpio_b[@]}"
mutant gpio "$gb" gpio '-DPART_A' gpio_block_hold_active_high "s/io_gpio_pins(p) <= pin_active_low(p);/io_gpio_pins(p) <= '0';/" 8 "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
mutant gpio "$gb" gpio '-DPART_A' gpio_block_float_off_output "s/io_gpio_pins(p) <= 'Z';/io_gpio_pins(p) <= '1';/" 8 "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
mutant gpio "$gb" gpio '-DPART_A' gpio_block_read_last_wins "s/acc := acc or group_rdata(g);/acc := group_rdata(g);/" 8 "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
mutant gpio_pkg "$gb" gpio '-DPART_A' gpio_pkg_polarity_by_bit "s/result(k) := l(field_value(members, first + k));/result(k) := l(k);/" 8 "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
mutant gpio_pkg "$gb" gpio '-DPART_A' gpio_pkg_dir_by_bit "s/result(2 \* k + 1 downto 2 \* k) := d(2 \* p + 1 downto 2 \* p);/result(2 * k + 1 downto 2 * k) := d(2 * k + 1 downto 2 * k);/" 8 "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
mutant gpio_group "$gb" gpio '-DPART_A' gpio_group_fixed_ignored "s/dir_mode => to_mode(dir_modes(2 \* i + 1 downto 2 \* i)),/dir_mode => 0,/" 8 "${gpio_block_srcs[@]}" -- "${gpio_a[@]}"
mut_pins=0

mut_expose=()
sp="$f/seg_display_props.sv"
mutant seg_display "$sp" seg_display '-DPART_A' disp_read_by_position "s/o_rdata(4 \* k + 3 downto 4 \* k) <= value(4 \* m + 3 downto 4 \* m);/o_rdata(4 * k + 3 downto 4 * k) <= value(4 * k + 3 downto 4 * k);/" 8 "${display_srcs[@]}" -- "${disp_a[@]}"
mutant seg_display "$sp" seg_display '-DPART_A' disp_write_by_position "s/value(4 \* m + 3 downto 4 \* m) <= i_data_in(4 \* k + 3 downto 4 \* k);/value(4 * k + 3 downto 4 * k) <= i_data_in(4 * k + 3 downto 4 * k);/" 8 "${display_srcs[@]}" -- "${disp_a[@]}"
mutant seg_display "$sp" seg_display '-DPART_A' disp_off_digit_lit "s/seg_low(7 \* n + 6 downto 7 \* n) <= (others => '1');/seg_low(7 * n + 6 downto 7 * n) <= (others => '0');/" 8 "${display_srcs[@]}" -- "${disp_a[@]}"
mutant seg_display "$sp" seg_display '-DPART_A' disp_group_zero "s/if sel = g then/if sel = 0 then/" 8 "${display_srcs[@]}" -- "${disp_a[@]}"
mutant seg_display "$sp" seg_display '-DPART_B' disp_any_word_writes "s/elsif i_write = '1' and digits > 0 and i_address(3 downto 0) = \"0000\" then/elsif i_write = '1' and digits > 0 then/" 8 "${display_srcs[@]}" -- "${disp_b[@]}"

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


# PLIC (own file, like the external interrupt controller).
source "$root/formal/plic.sh"

[ -s "$warnings" ] && { echo "formal: $(wc -l < "$warnings") warning(s) found; a warning is an error (see above)"; fail=1; }
[ "$fail" -eq 0 ] && echo "formal: all expectations met" || { echo "formal: FAILED (logs in build/formal)"; exit 1; }

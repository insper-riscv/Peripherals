# OpenCores uart2bus source

- Project: `uart2bus`
- Upstream page: <https://opencores.org/projects/uart2bus>
- Authors/copyright holders: Steve Muller and Moti Litochevski
- Local source package: `PFE/uartCheck/uart2bus/trunk/vhdl/rtl`
- Imported into this repository: 2026-10-15
- License: see `LICENSE` in this directory

This directory contains only the physical UART layer used by the RV32
memory-mapped peripheral: baud generator, receiver, transmitter, their package
declarations and `uartTop`. The upstream parser and UART-to-bus master are not
included.

The archive downloaded from OpenCores did not contain revision metadata. The
logic of the physical blocks is preserved as downloaded, apart from the local
changes listed at the end of this file. Line endings and
trailing whitespace were normalized, and unused `uartParser`/`uart2BusTop`
component declarations were removed from `uart2BusTop_pkg.vhd`; no physical
UART behavior was changed. Project-specific behavior lives in `UART/UART.vhd`.

Local change in `baudGen.vhd`: the comparison between the two `std_logic_vector`
values (`counter >= baudLimit`) is made between `unsigned(counter)` and
`unsigned(baudLimit)`, because GHDL warns that comparing a non-numeric vector is
unexpected, and a warning is an error in this repository. For vectors of `'0'`
and `'1'` of equal length the result is the same, and the change is noted in the
header of the file. The authors and the license are unchanged.
Local change in `uartTx.vhd`, `uartRx.vhd`, `uartTop.vhd` and `uart2BusTop_pkg.vhd`: the
frame format is configurable. `uartTx` takes `cfgParityEn`, `cfgParityOdd` and
`cfgStop2` (parity bit after the data and a second stop bit); `uartRx` takes
`cfgParityEn` and `cfgParityOdd` and gives the pulses `frameErr` (stop bit sampled
at zero) and `parityErr` (parity bit that does not match the byte); `uartTop` passes
them through. The data shift register of `uartRx` takes only the eight data bits.
The configuration inputs default to `'0'`, and with them at `'0'` the frame, the
byte and its timing are the 8N1 of the upstream modules, bit for bit. The authors
and the license are unchanged.


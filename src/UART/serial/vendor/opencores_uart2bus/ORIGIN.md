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
logic of the physical blocks is preserved as downloaded. Line endings and
trailing whitespace were normalized, and unused `uartParser`/`uart2BusTop`
component declarations were removed from `uart2BusTop_pkg.vhd`; no physical
UART behavior was changed. Project-specific behavior lives in `UART/UART.vhd`.

Local change in `baudGen.vhd`: the comparison between the two `std_logic_vector`
values (`counter >= baudLimit`) is made between `unsigned(counter)` and
`unsigned(baudLimit)`, because GHDL warns that comparing a non-numeric vector is
unexpected, and a warning is an error in this repository. For vectors of `'0'`
and `'1'` of equal length the result is the same, and the change is noted in the
header of the file. The authors and the license are unchanged.

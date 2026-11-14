# MAX 10 internal ADC

🌐 [Português](../../pt-br/ADC/max10_adc.md) · [English](../../en/ADC/max10_adc.md)

## 1. What it is

A peripheral (`max10_adc`) that gives the processor the 12-bit analog-to-digital converter inside the MAX 10, through the Quartus `altera_modular_adc` core. On the DE10-Lite the converter reads the six analog inputs of the Arduino connector (A0 to A5) and the two inputs of the 1x2 header that is not mounted, and the core also reads the temperature sensor of the chip.

The peripheral wraps the Avalon-ST interface of the core, command and response per channel, with registers. A sequencer walks the channels of a mask, one register per channel keeps the last sample with the conversion flags, a configurable period repeats the scan and an interrupt reports the end of each scan.

The converter core is vendor IP, and GHDL has no model of it. The entity tests use a behavioral model of the core, in `tests/vhdl`, and the board uses the IP that the generation script produces.

## 2. Interface

### 2.1. Generics

| Generic | Default | Description |
| :--- | ---: | :--- |
| `clk_freq` | 100000000 | Frequency of `i_clk` in Hz |
| `scan_freq` | 1000 | Scan frequency in Hz that the period has coming out of reset |

### 2.2. Ports

| Port | Direction | Description |
| :--- | :--- | :--- |
| `i_clk`, `i_rst` | input | Clock and synchronous reset, active at 1 |
| `i_write`, `i_read` | input | Write and read pulses of the bus |
| `i_address` | input, 5 bits | Word address of the register |
| `i_data_in`, `o_data_out` | input and output, `word_t` | Bus data; the output is zero outside a read |
| `o_irq` | output | Level interrupt |
| `o_cmd_valid`, `o_cmd_channel`, `o_cmd_sop`, `o_cmd_eop`, `i_cmd_ready` | output and input | Avalon-ST command interface of the core: 5-bit channel, start and end of the scan packet |
| `i_rsp_valid`, `i_rsp_channel`, `i_rsp_data` | input | Avalon-ST response interface of the core: 5-bit channel and 12-bit sample |

## 3. Registers

The address is a 5-bit word address. An address outside the table reads zero and ignores writes.

| Word | Name | Access | Reset | Description |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `CTRL` | read and write | 0 | Bit 0 `ENABLE`, bit 1 `CONTINUOUS`, bit 2 `IRQ`; bit 3 `START` is a write pulse and reads as zero |
| 1 | `MASK` | read and write | 0 | Channels of the scan, one bit per channel, bits 0 to 17 |
| 2 | `PERIOD` | read and write | `clk_freq / scan_freq` | Cycles of `i_clk` between two scan starts in continuous mode |
| 3 | `STATUS` | read and write 1 to clear | 0 | State, see the bit table |
| 8 to 25 | `CH0` to `CH17` | read | 0 | Result of the channel, see the bit table |

### 3.1. Bits of `CTRL`

| Bit | Name | Effect |
| ---: | :--- | :--- |
| 0 | `ENABLE` | Turns the sequencer on; when off, no start is accepted (the scan in progress finishes) |
| 1 | `CONTINUOUS` | Repeats the scan every `PERIOD` cycles |
| 2 | `IRQ` | Enables the end-of-scan interrupt |
| 3 | `START` | Asks for a single scan, accepted with `ENABLE` on and the sequencer free |

### 3.2. Bits of `STATUS`

| Bit | Name | Description |
| ---: | :--- | :--- |
| 0 | `BUSY` | Scan in progress |
| 1 | `DONE` | Scan finished; stays on until cleared |
| 2 | `LATE` | A start, manual or by period, arrived while the previous scan was still running and was dropped; stays on until cleared |

Writing 1 to bit 1 or bit 2 clears that bit. An event in the cycle of the write wins. When `BUSY` returns to 0, `DONE` is already 1.

### 3.3. Channel register

| Bit | Name | Description |
| ---: | :--- | :--- |
| 11:0 | `DATA` | Last sample of the channel, from 0 to 4095 |
| 12 | `VALID` | There is a new result that has not been read |
| 13 | `OVERRUN` | A new sample replaced a result that had not been read |

Reading the register returns the sample and the two flags and clears the flags. A sample that arrives in the cycle of the read stays as a new result, with `OVERRUN` at 0.

## 4. Behavior

### 4.1. Channel numbering

The channel number is that of the command of the `altera_modular_adc` core of one ADC block.

| Channel | Input |
| ---: | :--- |
| 0 | Dedicated analog input (`ANAIN1` in the first block) |
| 1 to 8 | Dual-function pins (`ADC1IN1` to `ADC1IN8` in the first block) |
| 9 to 16 | Exist only in devices with more ADC pins; the DE10-Lite manual does not use them |
| 17 | Temperature sensor of the chip |

The number 17 of the temperature sensor and the recalibration (command 31, not used) come from the source code of the core installed with Quartus. Reading the sensor switches the sampling clock of the converter to 50 kHz during the conversion, so channel 17 takes longer than the others.

### 4.2. Scan

A start with the sequencer free latches the mask of `MASK` and walks the marked channels, from the lowest number to the highest. For each channel the sequencer holds the command valid until the core raises ready, waits for the response with the requested channel number and hands the sample to the register of the channel. The first command of the scan carries `startofpacket` and the last carries `endofpacket`.

The core raises ready for one cycle at the end of the conversion, together with the response or before it. A response with no accepted command, or with another channel number, is ignored. A scan with an empty mask ends with no command, with `DONE` on.

A scan in progress is not interrupted. Changing `MASK` during a scan counts only for the next one, and a core that never answers leaves `BUSY` at 1 until the peripheral is reset.

### 4.3. Scan rate

With `CONTINUOUS` and `ENABLE` on, a scan starts every `PERIOD` cycles of `i_clk`, that is, at the frequency

$$f_{\text{scan}} = \frac{f_{\text{clk}}}{\text{PERIOD}}$$

The first start comes as soon as continuous mode is turned on. With a period shorter than the duration of the scan, scans follow each other with no gap and `LATE` stays on. A `PERIOD` of 0 or 1 has the same effect. The reset period is `clk_freq / scan_freq`, never below 1.

### 4.4. Interrupt

`o_irq` is a level and equals `DONE` and `IRQ`. Writing 1 to the `DONE` bit of `STATUS` lowers it.

## 5. The converter core in Quartus

### 5.1. Files

| File | Role |
| :--- | :--- |
| `src/ADC/soc/max10_adc.vhd` | Registers, period and interrupt |
| `src/ADC/soc/max10_adc_sequencer.vhd` | Scan sequencer, with the Avalon-ST interface |
| `src/ADC/soc/max10_adc_consts.vhd` | Addresses, bits and number of channels |
| `src/ADC/max10/max10_adc_ip.vhd` | Thin instance of the generated IP, as a `component` |
| `src/ADC/max10/max10_adc_pll.v` | 10 MHz PLL of the converter, `altpll` megafunction |
| `src/ADC/max10/max10_adc_shell.vhd` | Structural top of the board: PLL, IP and peripheral |
| `src/ADC/max10/ip/max10_adc_core.tcl` | Platform Designer script that creates the system of the IP |
| `src/ADC/max10/ip/generate.sh` | Generates the IP with `qsys-script` and `qsys-generate` |

### 5.2. Generating the IP

The IP is the `altera_modular_adc` core in the standalone variant (`CORE_VAR` 3), which exposes only the Avalon-ST command and response interfaces, plus the clock, the reset and the PLL clock with the lock signal. The script uses the first ADC block, the 10 MHz converter clock, a 1 MHz sample rate, channels 1 to 8 and the temperature sensor.

```bash
QUARTUS_ROOTDIR=/opt/altera_lite/25.1std/quartus src/ADC/max10/ip/generate.sh build/adc-ip
```

The output is `build/adc-ip/max10_adc_core/synthesis/max10_adc_core.qip`, which the Quartus project includes with `QIP_FILE`. Quartus Prime Lite 25.1 generates the IP in VHDL at the top and Verilog in the submodules.

### 5.3. Vendor primitives

The generated IP and the `altpll` megafunction have no entity visible to the VHDL of the project, and enter as a `component`, following the pattern of `sld_virtual_jtag`. `max10_adc_ip.vhd` declares and instantiates the `max10_adc_core` component, with the name and ports that the generator writes. `max10_adc_pll.v` instantiates `altpll` in Verilog, because the same instantiation in VHDL leaves the PLL counters at zero in `quartus_map` 25.1 (error 14024), and `max10_adc_shell.vhd` instantiates it as a `component`.

The names `max10_adc_core` and `max10_adc_pll` are not in the `vendor_primitives.yaml` list of `riscv-tools` (today `altsyncram`, `sld_virtual_jtag` and `sdram_platform_pll`), so the files of the `max10/` folder stay out of the GHDL analysis and out of the style rules for components.

### 5.4. Synthesis check

The script `tests/quartus/check_max10_adc_synthesis.sh` generates the IP and runs the synthesis of `max10_adc_shell` for the `10M50DAF484C7G`, with no pin assignments.

```bash
tests/quartus/check_max10_adc_synthesis.sh /tmp/max10-adc-synth
```

The synthesis uses one ADC block and one PLL. The fitter also completes, with the caveat that no pin has an assignment.

## 6. Connection to the DE10-Lite

### 6.1. Analog inputs

The DE10-Lite manual (section 3.7, figure 3-20) connects the analog inputs to the ADC1 block of the MAX 10 through the `ADC1IN[8..1]` bus, coming from the analog front end that reduces the 5.0 V of the Arduino to the 2.5 V of the converter. The `ADC1IN` pins are dedicated analog pins of the device, the manual gives them no FPGA pin number and they have no assignment in the `.qsf`.

| Arduino input | Manual bus | Device pin | Core channel | Mapping |
| :--- | :--- | :--- | ---: | :--- |
| A0 (`ADC_IN0`) | `ADC_IN[0]` | `ADC1IN1` | 1 | Inferred from the order of the `ADC_IN[7..0]` and `ADC1IN[8..1]` buses of figure 3-20 |
| A1 (`ADC_IN1`) | `ADC_IN[1]` | `ADC1IN2` | 2 | same |
| A2 (`ADC_IN2`) | `ADC_IN[2]` | `ADC1IN3` | 3 | same |
| A3 (`ADC_IN3`) | `ADC_IN[3]` | `ADC1IN4` | 4 | same |
| A4 (`ADC_IN4`) | `ADC_IN[4]` | `ADC1IN5` | 5 | same |
| A5 (`ADC_IN5`) | `ADC_IN[5]` | `ADC1IN6` | 6 | same |
| 1x2 header, not mounted | `ADC_IN[6]`, `ADC_IN[7]` | `ADC1IN7`, `ADC1IN8` | 7, 8 | same |

The core generated for the DE10-Lite that ships with Quartus (university program, six channels, pin mask 63) uses channels 1 to 6 for these six inputs, which confirms the mapping. The dedicated input `ANAIN1` (channel 0) is not listed in the board manual as connected to anything, and the use of channel 0 is not confirmed.

The converter clock is `ADC_CLK_10`, pin `N5`, 3.3-V LVTTL, 10 MHz (section 3.2, table 3-2), connected to PLL1 and PLL3 of the FPGA. The reference source of the converter (`refsel`) is that of the university-program core, and the manual does not specify it; not confirmed.

### 6.2. Conversion to voltage

The 12-bit result represents 0 to 2.5 V at the converter input, and the front end divides the Arduino voltage by 2 (section 5.6 of the manual). The voltage at the Arduino pin is

$$V_{\text{pin}} = \frac{\text{DATA}}{4095} \times 5.0\ \text{V}$$

## 7. C example

The program scans A0 to A5 once, waits for the end and prints the voltage of each pin in millivolts. The base of the peripheral window comes from the platform.

```c
#include <stdint.h>
#include <stdio.h>

#define ADC_BASE       0x10003000u  /* base of the peripheral window on the platform */
#define ADC_REG(n)     (*(volatile uint32_t *)(ADC_BASE + 4u * (n)))
#define ADC_CTRL       ADC_REG(0)
#define ADC_MASK       ADC_REG(1)
#define ADC_PERIOD     ADC_REG(2)
#define ADC_STATUS     ADC_REG(3)
#define ADC_CHANNEL(n) ADC_REG(8u + (n))

#define CTRL_ENABLE    (1u << 0)
#define CTRL_START     (1u << 3)
#define ST_BUSY        (1u << 0)
#define ST_DONE        (1u << 1)
#define CH_DATA        0xFFFu
#define CH_VALID       (1u << 12)

#define FIRST_CHANNEL  1u            /* A0 is channel 1 of the core (ADC1IN1) */
#define ARDUINO_PINS   6u
#define SCAN_TRIES     100000u

static uint32_t arduino_mask(void) {
    return ((1u << ARDUINO_PINS) - 1u) << FIRST_CHANNEL;
}

static int scan_once(void) {
    ADC_MASK = arduino_mask();
    ADC_CTRL = CTRL_ENABLE;
    ADC_STATUS = ST_DONE;                 /* clears the end of the previous scan */
    ADC_CTRL = CTRL_ENABLE | CTRL_START;

    for (uint32_t i = 0; i < SCAN_TRIES; i++) {
        uint32_t status = ADC_STATUS;
        if (!(status & ST_BUSY) && (status & ST_DONE)) {
            return 0;
        }
    }
    return -1;
}

int main(void) {
    if (scan_once() != 0) {
        puts("the ADC did not answer");
        return 1;
    }

    for (uint32_t pin = 0; pin < ARDUINO_PINS; pin++) {
        uint32_t word = ADC_CHANNEL(FIRST_CHANNEL + pin);
        if (!(word & CH_VALID)) {
            continue;
        }
        /* 12 bits for 0 to 2.5 V at the converter, twice that at the Arduino pin. */
        uint32_t millivolts = (word & CH_DATA) * 5000u / 4095u;
        printf("A%u = %u mV\n", (unsigned)pin, (unsigned)millivolts);
    }
    return 0;
}
```

To sample continuously, write `PERIOD` with `clk_freq / frequency` and `CTRL` with `ENABLE`, `CONTINUOUS` and `IRQ`; the interrupt routine reads the channel registers, which clear `VALID`, and writes `ST_DONE` to `STATUS`. To read the chip temperature, set bit 17 in `MASK`; the conversion of the sensor value to degrees Celsius comes from the MAX 10 converter guide, which is not in `Docs` (not confirmed).

## 8. Verification

The entity tests run the peripheral against a behavioral model of the core, with the response together with ready and one cycle after it, and the sequencer alone against responses driven by hand. They cover the reset values, the register read-back, the order of the channels with `startofpacket` and `endofpacket`, the `VALID` and `OVERRUN` flags, the read that clears them, the exact period between scans, `LATE`, the scan of an empty mask, the start without `ENABLE` and the interrupt.

The formal proof of the sequencer leaves ready and the response free and proves that each command is for the lowest channel still without a sample of the mask latched at the start, that the command stays valid until ready, that a sample only comes from the response of the requested channel to an accepted command and that the end of the scan comes with every channel sampled, with mutants of each rule. The detail is in [formal.md](../formal/formal.md).

---

Copyright 2026 Insper. Licensed under the [Apache License, Version 2.0](../../../LICENSE).

# Platform-selected C and Rust drivers

This branch adds 17 C drivers and their safe Rust/sys pairs, plus a Rust driver
for the existing USB HPI bridge. Existing GPIO, TIMER, UART, CLINT, PLIC,
DISPLAY and FLASH APIs remain available. GPIO also gains logical group selection
for boards such as the MKR Vidor: `GPIO::group(2)?.get(0)?` selects pin zero of
group two; physical pin numbers and group register strides come from the map.
The old low-level C constructors retain their names and signatures.

| Driver | Under `src/` | Canonical kinds |
| --- | --- | --- |
| SPI | `SPI/master/driver` | spi |
| SD_SPI | `SD/spi/driver` | sd_spi |
| I2C | `I2C/soc/driver` | i2c |
| IR | `IR/soc/driver` | ir |
| LCD | `LCD/soc/driver` | lcd |
| KEYBOARD | `PS2/keyboard/driver` | ps2 |
| MOUSE | `PS2/mouse/driver` | ps2 |
| AUDIO | `audio/soc/driver` | audio, hdmi_audio |
| ADXL345 | `ADXL345/driver` | adxl345 |
| ADC | `ADC/soc/driver` | adc |
| ETH | `ETH/mac/driver` | eth |
| TV | `TV/soc/driver` | tv |
| MIPI | `MIPI/soc/driver` | mipi |
| SD | `SD/native/driver` | sd_native |
| VIDEO | `video/soc/driver` | video |
| HDMI | `HDMI/soc/driver` | hdmi, hdmi_tmds |
| WIFI | `WIFI/nina/driver` | wifi |
| USB | `USB/soc/driver` | usb |

Each driver's README describes capabilities and points to C templates and
Rust function documentation. The SDK 0.10.0 reads `driver.yaml`, generates
platform tables and vendors only mapped drivers. Rust applications depend on
the safe crate, which links the C implementation through generated bindings.
No base address is passed by application code. Placeholder addresses are zero
and unavailable until configured; constructors never access hardware.

Safe Rust handles have private state and validated logical indices. Operations
that cannot fail after validation return values directly. Busy queues, bounded
polling, unsupported backend features and hardware errors remain explicit.
Callers must serialize configuration with interrupt handlers and other handles.

These are controller drivers, not networking/filesystem/device protocol stacks.
USB wraps the FPGA HPI bridge without relying on the existing unverified BIOS
constants. Ethernet exposes MAC/MDIO/frame buffers; Wi-Fi exposes NINA transports;
SD exposes the controller. PHY/card/codec/sensor startup and higher protocols are
application-specific. Generated smoke examples only inspect non-consuming
status and do not prove attached-device operation.

## Reproduce validation

Use the project's pinned CI development image, with at most 8 GiB and no swap.
`make driver-test new-driver-test usb-driver-test` runs strict C compilation,
existing driver regressions and side-effect-aware bus models (W1C, consuming
reads, write-only buffers, bounds, byte packing and busy paths).
`bash tests/c/check-rust-drivers.sh` checks formatting, native tests,
compile-fail/no-run documentation, Clippy and RV32I/RV32IM builds.
Rust 1.85.1 was used for native and target builds; current nightly Clippy was
used for lint validation because the installed MSRV toolchain lacks Clippy.
The SDK has additional generation/ownership and complete-project build tests.

RTL regressions use the existing `tests/python/runner.py` catalog. Driver bus
models and peripheral RTL tests are separate layers; physical device testing
and an end-to-end board SoC/device simulation have not been performed.

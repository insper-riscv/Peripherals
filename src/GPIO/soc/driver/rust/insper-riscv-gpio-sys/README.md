# insper-riscv-gpio-sys

Raw `no_std` bindings to the sibling `driver/c/rv32_gpio.h` API. Your
`insper-riscv-gpio` crate can build its Rust abstraction on top of this crate.
No safe GPIO wrapper, allocation, ownership policy or interrupt handler is
provided here.

## Requirements

- Rust 1.85+ (edition 2024). Rust 1.85.1 matches the SDK toolchain.
- Host Clang 18+ and its shared libclang library. If library discovery fails,
  set `LIBCLANG_PATH` to the directory containing `libclang.so`/`.dylib`/`.dll`.
- For bare-metal builds, install the matching Rust target component.

The crate is tested on the native Linux host, `riscv32i-unknown-none-elf` and
`riscv32im-unknown-none-elf`. Other cross targets are rejected explicitly.
No nightly Cargo features, `libc` runtime dependency or doxygen tool is needed.
Build dependencies (including libclang) execute on the host, not on the FPGA.

## Generate and test

Run these commands from the `driver/rust` workspace:

```sh
cargo test -p insper-riscv-gpio-sys

rustup target add --toolchain 1.85.1 riscv32i-unknown-none-elf
rustup target add --toolchain 1.85.1 riscv32im-unknown-none-elf

cargo +1.85.1 build -p insper-riscv-gpio-sys --target riscv32i-unknown-none-elf
cargo +1.85.1 build -p insper-riscv-gpio-sys --target riscv32im-unknown-none-elf
```

Install `1.85.1` first if needed with
`rustup toolchain install 1.85.1 --profile minimal`. No default toolchain or
workspace target is changed by this crate. Use `-j 2` to bound parallel builds.
Native tests use RAM as mock MMIO; they test the actual linked C functions but
do not simulate pin propagation, SET/CLEAR/TOGGLE effects or IRQ read-to-clear.
Do not run native binaries against real FPGA addresses.

`build.rs` runs automatically on `cargo build`, `test`, `check` and `doc`:

1. Bindgen reads `wrapper.h`, which includes the original C API.
2. Clang parses it for the selected Cargo target. Bare-metal bindings use
   RV32 ILP32, not the host's 64-bit pointers.
   The C compiler also gets an explicit `-march=rv32i` or `-march=rv32im`;
   generic bare-metal compiler defaults must not introduce unsupported A/C.
3. Rust declarations go into Cargo's `OUT_DIR/bindings.rs`. `src/lib.rs`
   includes/reexports them using `core`, without `std`.
4. `cc` compiles the original `../../c/rv32_gpio.c` for that same target and
   links the resulting `librv32_gpio.a` automatically.

Changes to the C source, header and included headers trigger regeneration.
Generated bindings and archives belong in `target/`, not in Git.
Inspect the exported API with `cargo doc -p insper-riscv-gpio-sys --no-deps`.

Clang is the default C compiler; `CLANG_PATH` can select a different executable.
The standard cc-rs overrides `CC_<target>`, `CC_<target_with_underscores>`,
`TARGET_CC`/`HOST_CC` and `CC` remain available. A replacement compiler must
support C23, use the same target ABI and retain the default enum ABI. Bindgen
still requires host libclang. Do not force host include paths/sysroots into
bare-metal builds through `BINDGEN_EXTRA_CLANG_ARGS` or `CFLAGS`.

## Use from your wrapper

Add this dependency yourself to `insper-riscv-gpio/Cargo.toml`:

```toml
[dependencies]
insper-riscv-gpio-sys = { path = "../insper-riscv-gpio-sys" }
```

Then import the raw layer:

```rust
use insper_riscv_gpio_sys as sys;
```

The exported names follow C, for example `sys::rv32_gpio_t`,
`sys::rv32_gpio_new`, `sys::rv32_gpio_pin_write`,
`sys::RV32_GPIO_OUTPUT_PIN` and `sys::RV32_GPIO_IRQ_BOTH_EDGES`.
C `size_t`/`uintptr_t` map to pointer-sized Rust types; the pin argument uses
`usize`. C enum typedefs remain integer types and their values are constants,
so bindings do not invent a Rust enum validity invariant.

Calling these functions requires `unsafe`. Your wrapper should decide how to
validate the MMIO base and pin count, guarantee device/buffer lifetimes and
serialize shared access. GPIO direction/IRQ configuration uses RMW; pin
set/clear/toggle uses hardware registers. Reading IRQ status clears events for
the whole instance. Neither `-sys` nor its constructors map memory or install
CPU interrupts. Platform addresses are not hardcoded in this crate.

This crate already owns compilation/linking of the C GPIO driver. Do not also
add that C source to the final application's SDK sources. For a Rust project
using this crate, enable `generate_drivers = true`: the SDK generates headers
but does not add the C source to its runtime objects. It passes the generated
GPIO directory through `RV32_GPIO_CONFIG_DIR`. Without that configuration,
`rv32_gpio_platform_new` safely returns an invalid handle. For direct Cargo
builds, export the absolute generated directory yourself. The build tracks
changes to both `rv32_gpio_platform.h` and its parent `rv32_platform.h`.

`publish = false` is intentional: the build currently uses sibling C sources
from this checkout. A future crates.io package would need to bundle those
sources or provide a reviewed packaging mechanism.

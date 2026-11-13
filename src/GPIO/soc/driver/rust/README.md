# GPIO Rust driver

`insper-riscv-gpio` is the allocation-free, `no_std` interface. It preserves the
`GPIO` → borrowed `Pin` abstraction; `insper-riscv-gpio-sys` generates the raw
bindings and compiles the C implementation. Both crates require Rust 1.85+.

```rust,no_run
use insper_riscv_gpio::{Direction, GPIO, Instance};

let gpio = GPIO::from_platform(Instance::Switches)?;
let mut pin = gpio.get(0)?;
pin.set_direction(Direction::Output);
pin.set_high()?;
let high = pin.read()?;
pin.toggle()?;
# Ok::<(), insper_riscv_gpio::GPIOError>(())
```

`GPIO::new(4)` retains the initial interface: use the first platform GPIO and
expose only its first four pins. `GPIO::new_for(Instance::Keys, 4)` selects keys.
`from_platform` exposes the full generated width. Constructors do not allocate,
reset registers or change directions. Pin indices are always zero-based and
must be strictly smaller than `pin_count()`.

## Platform configuration

Set `generate_drivers = true` in the Rust project's `[project]` in `rv32.toml`.
Add this crate as a Cargo path dependency at its installed SDK path. The normal
SDK build/simulate/run commands generate `vendor/GPIO/rv32_gpio_platform.h`, then
pass its directory to bindgen's build script as `RV32_GPIO_CONFIG_DIR`.
There are no physical addresses in the Rust API or application source.

The C source includes `<rv32_gpio_platform.h>`. The source tree's header contains
zero-valued `BASE`/`PIN_COUNT` placeholders. The generator replaces these values
using the canonical platform map and instantiated RTL width/generic overrides.
It configures the default instance and the named SWITCHES/KEYS independently.
An absent instance or an unconfigured standalone build fails construction safely.
Do not edit generated headers; select another platform/profile and regenerate.
The old explicit-address C constructor is retained for compatibility/raw tests;
new C applications use `rv32_gpio_platform_new(RV32_GPIO_SWITCHES_INSTANCE)`.

For Cargo outside the SDK, first run the SDK's `drivers` command and export
`RV32_GPIO_CONFIG_DIR` as the absolute path to the generated `vendor/GPIO`.
The build script tracks both this header and its parent platform header, so
changing mappings rebuilds the C archive. Cross builds need host libclang and a
C compiler supporting the target. The script uses RV32I/IM, without A or C.

## Pin and interrupt behavior

`set_high`, `set_low`, `write` and `toggle` require output direction. Direction is
read from hardware rather than cached in a `Pin`, so another handle cannot make
that state stale. `read`/`is_high`/`is_low` return the synchronized input value;
it may lag an output write by two peripheral clocks. There is no arbitrary busy
wait inside the driver; applications that need loopback confirmation can poll
with a bounded timeout.

`configure_interrupt` accepts Disabled, RisingEdge, FallingEdge, BothEdges,
HighLevel or LowLevel. This only configures GPIO event generation: enable the
corresponding CPU interrupt-controller source separately. `take_interrupts()`
reads and clears **all** pending GPIO events once; inspect the returned snapshot
with `contains(pin_index)` for each pin. Persistent level events can reassert.

GPIO and Pin are intentionally neither Send nor Sync. Set/clear/toggle use
atomic device registers; direction and IRQ configuration use read/modify/write.
Serialize accesses to the same instance, including interrupt handlers. Do not
create a second handle to bypass that requirement. No interrupt handler or
critical-section implementation is installed by this crate.

## Checks

From this workspace:

```sh
cargo +1.85.1 test --workspace --locked -j 2
cargo +1.85.1 build --workspace --release --target riscv32i-unknown-none-elf --locked -j 2
cargo +1.85.1 build --workspace --release --target riscv32im-unknown-none-elf --locked -j 2
```

Native tests use eleven words to represent the register bank, **not eleven
pins**. They check FFI linkage, pin 31, bounds, direction aliasing, output writes,
input reads, all interrupt modes and snapshot filtering. RAM does not emulate
read-to-clear or the synchronizer; the SDK's RTL integration exercises hardware
behavior separately.

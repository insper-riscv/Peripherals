# Rust driver invariants and migration

The safe wrappers validate platform availability in their constructors and keep raw C handles private. C ABI validation remains intact for C and `-sys` users. Safe Rust operations no longer report failure merely because the already-validated peripheral or index could theoretically be invalid in C.

## GPIO

`GPIO::get(index)` validates the immutable index once. `Pin::set_direction` and `Pin::configure_interrupt` now return `()`. `read`, `is_high`, and `is_low` return `bool`. Remove their old `?`, `unwrap`, or `expect` calls. The enum arguments exclude invalid direction and interrupt-mode constants. `OperationFailed` is removed.

`write`, `set_high`, `set_low`, and `toggle` still return `Result<(), GPIOError>` with `NotOutput`. This is a real hardware-state condition: the API permits multiple handles for one pin, and another handle can reconfigure its direction. An output typestate or cached direction would be unsound as a promise about that hardware state under the current aliasing model. The wrapper checks the current hardware direction and never caches it. Access from interrupts, C or raw bindings must still be serialized with Rust configuration operations; `NotOutput` is not a lock.

## TIMER

`set_divider` accepts `core::num::NonZeroU32` and returns `()`. Convert external numeric input to `NonZeroU32` once at its boundary. A zero value cannot reach the operation. TIMER errors now describe only unavailable hardware.

## DISPLAY

Use `display.digit(index)?` (or `Digit::new`) to obtain a validated handle borrowing its originating display. Use `HexDigit::new(value)?` to validate 0 through 15 once. `digit.write(value)` returns `()` and `digit.read()` returns `HexDigit`; `.value()` exposes its number. These replace `write_digit(index, raw_value)` and `read_digit(index)`.

## PLIC

Use `plic.source(id)?` (or `Source::new`) to bind a validated source to its controller. `source.enable(bool)` and `source.pending()` are infallible. `source.set_priority(new_value)` and `plic.set_threshold(new_value)` still validate newly supplied numeric input against the platform-dependent maximum and report `InvalidPriority`; they do not revalidate a handle in Rust.

`plic.claim()` returns an optional non-cloneable claim token. Service the interrupt, then call `claim.complete()`, which consumes that token. The safe interface no longer accepts arbitrary source numbers for completion. A claim exclusively borrows its controller, preventing another claim through that handle until it is completed or released. Dropping a claim does not complete hardware, so callers must service/complete it explicitly. Handles do not provide global ownership against independent C/raw access or separately constructed controller handles; such accesses must be serialized.

## FLASH

`flash.buffer_word(index)?` (or `BufferWord::new`) validates a page-buffer slot once. Its `.write(value)` returns only `Busy` if hardware is occupied. The same slot can be retried when busy clears. `submit` also retains `Busy`: construction cannot predict the progress of an asynchronous flash operation. Invalid slots have their own constructor error, `InvalidWord`. Flash examples remain read-only on attached hardware.

## CLINT and UART

Their operations already had appropriate infallible/readiness semantics. The unused catch-all `Rejected` errors are removed. UART's `false`, `None`, and partial writes continue to represent actual queue availability, not invalid handles.

All seven safe crates move to 0.2.0 for the breaking API changes; the C ABI and sys crate versions remain unchanged. The SDK's generated examples and standalone Rust peripheral project use the new interfaces. Documentation tests include compiler-rejected examples for forging a hexadecimal value, outliving a display, supplying a raw zero divider, and completing one interrupt twice.

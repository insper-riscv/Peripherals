# USB HPI C and Rust driver

The safe Rust crate `insper-riscv-usb` wraps the C HPI bridge. `Usb::new()` and
`Usb::instance(index)` select platform-generated instances. `ChipWord::new(index)`
accepts a logical 16-bit word index and handles byte-address conversion. Slice
operations reject address-space overflow; all waiting has a nonzero poll budget.
See `cargo doc --no-deps` for function examples. Configuration must be serialized.

The C instance factory is `rv32_usb_instance_new(index)`. Existing explicit
C profile APIs remain compatible. `rv32_usb_profile_new()` initializes all
fields without assuming a particular chip BIOS. The safe crate does not use
unverified BIOS register defaults or implement USB host enumeration.

`c/examples/main.c.in` and `main.rs.in` inspect bridge status only: no chip reset,
chip RAM consumption or attached-device operation occurs. SDK 0.10.0 turns them
into complete vendor example projects with Dev Container and editor files.

# HDMI driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-hdmi-sys` and a `no_std` safe API in
`rust/insper-riscv-hdmi`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_hdmi_new(instance)` or `Hdmi::instance(instance)`;
`Hdmi::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/HDMI`.
For Rust it adds only the safe crate as a direct Cargo dependency; the sys
crate builds and links the same C implementation. Do not edit generated files
in place: regeneration refuses to overwrite hand edits.

C operations validate their handle/arguments. Rust validates handles and
bounded values at construction, then uses private fields and borrowing handles
for pins, channels and buffer words. Register accesses with no runtime failure
are infallible; FIFO readiness, busy devices and bounded polling remain
fallible. Serialize configuration with other handles and interrupt handlers;
these wrappers do not provide a system-wide lock or an interrupt dispatcher.

The `c/examples/main.c.in` and `main.rs.in` templates become independent
projects in `vendor/HDMI/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_hdmi_enable`: Enable the framebuffer display; mode timing comes from the hardware profile.
- `rv32_hdmi_vertical_sync`: Current synchronized vertical-sync level.
- `rv32_hdmi_vertical_blank`: Current synchronized vertical-blank interval.
- `rv32_hdmi_frame_count`: Frame counter increments at the start of vertical blanking.
- `rv32_hdmi_width`: Immutable framebuffer width.
- `rv32_hdmi_height`: Immutable framebuffer height.
- `rv32_hdmi_pixel_bits`: Framebuffer storage bits per pixel.
- `rv32_hdmi_channel_bits`: Stored bits per color channel.
- `rv32_hdmi_indexed`: Whether this hardware provides an indexed palette.
- `rv32_hdmi_word_count`: Frame capacity checked against both immutable geometry and the platform window.
- `rv32_hdmi_write_word`: Write one numbered framebuffer word; never read back write-only framebuffer memory.
- `rv32_hdmi_palette_write`: Write a palette entry using eight-bit RGB components scaled to the hardware channel width.
- `rv32_hdmi_framebuffer_word`: Validate one framebuffer position once and borrow its display.
- `rv32_hdmi_palette`: Obtain palette operations only for a validated indexed display.
- `rv32_hdmi_mode`: Read the hardware video mode and sync-polarity information.
- `rv32_hdmi_pixel_clock_khz`: Read the declared mode clock; this is not a measured FPGA clock.
- `rv32_hdmi_transmitter_interrupt`: External transmitter interrupt, or HPD for direct TMDS.
- `rv32_hdmi_initializing`: Whether the transmitter initialization sequencer is active.
- `rv32_hdmi_initialized`: Whether the initialization table completed.
- `rv32_hdmi_initialization_nack`: Whether a transmitter table write was not acknowledged.
- `rv32_hdmi_has_initialization`: Whether this hardware includes a transmitter initialization sequencer.
- `rv32_hdmi_frame_interrupt`: Enable end-of-frame interrupts.
- `rv32_hdmi_transmitter_irq_enable`: Enable external interrupt or hot-plug edge interrupts.
- `rv32_hdmi_clear_events`: Clear only frame and transmitter edge interrupt events.
- `rv32_hdmi_restart_initialization`: Restart the platform-provided table; direct TMDS has no external transmitter to initialize.

External codec/sensor/transmitter setup remains board/device specific. No undocumented initialization sequence is assumed.

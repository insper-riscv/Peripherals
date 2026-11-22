# VIDEO driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-video-sys` and a `no_std` safe API in
`rust/insper-riscv-video`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_video_new(instance)` or `Video::instance(instance)`;
`Video::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/VIDEO`.
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
projects in `vendor/VIDEO/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_video_enable`: Enable the framebuffer display; mode timing comes from the hardware profile.
- `rv32_video_vertical_sync`: Current synchronized vertical-sync level.
- `rv32_video_vertical_blank`: Current synchronized vertical-blank interval.
- `rv32_video_frame_count`: Frame counter increments at the start of vertical blanking.
- `rv32_video_width`: Immutable framebuffer width.
- `rv32_video_height`: Immutable framebuffer height.
- `rv32_video_pixel_bits`: Framebuffer storage bits per pixel.
- `rv32_video_channel_bits`: Stored bits per color channel.
- `rv32_video_indexed`: Whether this hardware provides an indexed palette.
- `rv32_video_word_count`: Frame capacity checked against both immutable geometry and the platform window.
- `rv32_video_write_word`: Write one numbered framebuffer word; never read back write-only framebuffer memory.
- `rv32_video_palette_write`: Write a palette entry using eight-bit RGB components scaled to the hardware channel width.
- `rv32_video_framebuffer_word`: Validate one framebuffer position once and borrow its display.
- `rv32_video_palette`: Obtain palette operations only for a validated indexed display.

External codec/sensor/transmitter setup remains board/device specific. No undocumented initialization sequence is assumed.

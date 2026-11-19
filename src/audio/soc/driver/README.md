# AUDIO driver

The C implementation is in `c/`. Rust uses bindgen in
`rust/insper-riscv-audio-sys` and a `no_std` safe API in
`rust/insper-riscv-audio`. Run `cargo doc --no-deps` in the workspace
for examples of every public operation.

Construct with `rv32_audio_new(instance)` or `Audio::instance(instance)`;
`Audio::new()` selects instance zero. The index selects a platform instance,
not a physical address. Construction performs no MMIO or reset. Unconfigured
placeholder headers deliberately report no available hardware.

The SDK discovers `c/driver.yaml`, matches `kind` (and PS/2 `device`) in
`platform.yaml`, and generates address/variant tables under `vendor/AUDIO`.
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
projects in `vendor/AUDIO/example/`, including `rv32.toml`, editor tasks and
Dev Container files. They only inspect non-consuming status/capability state;
they are compile/API smoke examples, not external-device functional tests.

## C operations

- `rv32_audio_playback`: Enable this audio function; codec setup and clock policy remain explicit.
- `rv32_audio_recording`: Enable this audio function; codec setup and clock policy remain explicit.
- `rv32_audio_transmit_interrupt`: Enable this audio function; codec setup and clock policy remain explicit.
- `rv32_audio_receive_interrupt`: Enable this audio function; codec setup and clock policy remain explicit.
- `rv32_audio_error_interrupt`: Enable this audio function; codec setup and clock policy remain explicit.
- `rv32_audio_clocks`: Enable this audio function; codec setup and clock policy remain explicit.
- `rv32_audio_tone`: Enable this audio function; codec setup and clock policy remain explicit.
- `rv32_audio_tx_ready`: Whether the playback queue can accept a sample.
- `rv32_audio_rx_ready`: Whether the recording queue contains a sample.
- `rv32_audio_try_write`: Queue one signed sample; left and right alternate.
- `rv32_audio_try_read`: Pop one sign-extended sample from the recording queue.
- `rv32_audio_clear_errors`: Clear only playback underflow, recording overflow and dropped write.
- `rv32_audio_playback_depth`: Read hardware-reported playback capacity.
- `rv32_audio_recording_depth`: Read hardware-reported recording capacity.
- `rv32_audio_set_xck_step`: Configure the master-clock accumulator with clocks disabled.
- `rv32_audio_set_xck_modulus`: Configure the master-clock accumulator with clocks disabled.
- `rv32_audio_set_bit_divider`: Configure this audio parameter with playback/clocks stopped.
- `rv32_audio_set_slot_bits`: Configure this audio parameter with playback/clocks stopped.
- `rv32_audio_set_tone_half_period`: Configure this audio parameter with playback/clocks stopped.
- `rv32_audio_set_tone_amplitude`: Configure this audio parameter with playback/clocks stopped.
- `rv32_audio_set_sample_width`: Select a typed sample width; hardware state changes should be serialized.

External codec/sensor/transmitter setup remains board/device specific. No undocumented initialization sequence is assumed.

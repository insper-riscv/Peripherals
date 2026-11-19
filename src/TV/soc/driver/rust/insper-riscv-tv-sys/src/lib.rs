// SPDX-License-Identifier: Apache-2.0
//! Raw bindings to `driver/c/rv32_gpio.h` and its compiled C implementation.
//!
//! This crate deliberately provides no ownership model, synchronization or safe
//! Rust GPIO abstraction. Its foreign functions require `unsafe`: callers must
//! provide a valid MMIO base, the actual pin count and valid output pointers, and
//! serialize register read/modify/write operations. IRQ reads clear all events
//! for the instance. See the C header for the complete hardware contract.
#![no_std]

#[allow(non_camel_case_types, non_snake_case, non_upper_case_globals)]
mod bindings {
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
}

pub use bindings::*;

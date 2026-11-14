//! GPIO and numbered pins backed by the C driver and generated platform map.
//! No heap, standard library, addresses or register offsets are needed.
#![no_std]

pub mod error;
pub mod gpio;
pub mod pin;

pub use error::GPIOError;
pub use gpio::{GPIO, Instance, Interrupts};
pub use pin::{Direction, InterruptMode, Pin};

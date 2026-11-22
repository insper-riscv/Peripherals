//! Platform-selected KEYBOARD; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_keyboard_sys as sys;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Unavailable,
    Unsupported,
    OutOfRange,
    WouldBlock,
    Timeout,
    Hardware,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Unavailable => "Peripheral unavailable on this platform.",
            Self::Unsupported => "Operation unsupported by this hardware variant.",
            Self::OutOfRange => "Value outside the supported range.",
            Self::WouldBlock => "Hardware cannot accept this operation yet.",
            Self::Timeout => "The bounded polling budget expired.",
            Self::Hardware => "Hardware reported an operation error.",
        })
    }
}

impl core::error::Error for Error {}

#[derive(Debug)]
pub struct Keyboard {
    inner: sys::rv32_keyboard_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Keyboard {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// let _device = Keyboard::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// let _device = Keyboard::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_keyboard_new(index) };

        if !unsafe { sys::rv32_keyboard_valid(inner) } {
            return Err(Error::Unavailable);
        }

        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }

    /// Count the instances generated from the platform map.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// let _count = Keyboard::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_keyboard_instance_count() }
    }

    /// Pop one set-2 scan-code byte; None means no queued byte.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// if let Some(value) = device.try_read() {
    ///     let _ = value;
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_read(&mut self) -> Option<u8> {
        let mut value = 0;

        if unsafe { sys::rv32_keyboard_try_read(self.inner, &mut value) } {
            Some(value)
        } else {
            None
        }
    }

    /// Send a keyboard command only when the transmitter is ready.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// let _result = device.try_command(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_command(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_keyboard_try_command(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queued scan-code bytes.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// let _value = device.queue_level();
    /// # Ok(())
    /// # }
    /// ```
    pub fn queue_level(&mut self) -> u8 {
        unsafe { sys::rv32_keyboard_queue_level(self.inner) }
    }

    /// Whether a scan-code byte is available.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// let _state = device.ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn ready(&mut self) -> bool {
        unsafe { sys::rv32_keyboard_ready(self.inner) }
    }

    /// Enable scan-code receive interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// device.receive_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_keyboard_receive_interrupt(self.inner, enabled) };
    }

    /// Enable framing and overflow interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_keyboard_error_interrupt(self.inner, enabled) };
    }

    /// Clear only receive overflow, receive error and dropped command.
    ///
    /// ```no_run
    /// use insper_riscv_keyboard::{Keyboard, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Keyboard::new()?;
    /// device.clear_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_errors(&mut self) {
        unsafe { sys::rv32_keyboard_clear_errors(self.inner) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Keyboard::instance_count();

        if count == 0 {
            assert!(matches!(Keyboard::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Keyboard::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            Keyboard::instance(usize::MAX),
            Err(Error::Unavailable)
        ));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_keyboard_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_keyboard_valid(inner) });
        let mut device = Keyboard {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.ready());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(u32::MAX) };
        assert!(device.ready());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(0) };
        assert!(!device.ready());
    }
}

//! Platform-selected DISPLAY. No heap, raw addresses or register offsets.
//! Handles are not Send/Sync. Serialize configuration, including interrupt handlers.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_display_sys as sys;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Unavailable,
    Rejected,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Unavailable => "Peripheral unavailable on this platform/profile.",
            Self::Rejected => "Peripheral rejected the argument or is busy.",
        })
    }
}
impl core::error::Error for Error {}

#[derive(Debug)]
pub struct Display {
    inner: sys::rv32_display_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Display {
    /// Construct using generated platform metadata; does not reset the hardware.
    /// ```no_run
    /// use insper_riscv_display::{Display, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let available = Display::new();
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_display_platform_new() };
        if !unsafe { sys::rv32_display_valid(inner) } {
            return Err(Error::Unavailable);
        }
        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }
    /// Return the hardware digit count.
    /// ```no_run
    /// use insper_riscv_display::{Display, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let count = display.digit_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn digit_count(&mut self) -> usize {
        self.inner.digit_count
    }
    /// Write a numbered digit (zero is least significant), with a value 0 through 15.
    /// ```no_run
    /// use insper_riscv_display::{Display, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// display.write_digit(0, 10)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn write_digit(&mut self, digit: usize, value: u8) -> Result<(), Error> {
        checked(unsafe { sys::rv32_display_write_digit(self.inner, digit, value) })
    }
    /// Read a numbered hexadecimal digit.
    /// ```no_run
    /// use insper_riscv_display::{Display, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let value = display.read_digit(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn read_digit(&mut self, digit: usize) -> Result<u8, Error> {
        let mut value = 0;
        checked(unsafe { sys::rv32_display_read_digit(self.inner, digit, &mut value) })?;
        Ok(value)
    }
    /// Write the complete logical display word.
    /// ```no_run
    /// use insper_riscv_display::{Display, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// display.write(0x123456);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write(&mut self, value: u32) {
        unsafe { sys::rv32_display_write(self.inner, value) };
    }
    /// Read the complete logical display word.
    /// ```no_run
    /// use insper_riscv_display::{Display, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let value = display.read();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read(&mut self) -> u32 {
        unsafe { sys::rv32_display_read(self.inner) }
    }
}

fn checked(accepted: bool) -> Result<(), Error> {
    if accepted {
        Ok(())
    } else {
        Err(Error::Rejected)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unconfigured_factory_is_safe() {
        assert!(matches!(Display::new(), Err(Error::Unavailable)));
    }

    #[test]
    fn ffi_registers_boundaries_and_side_effect_contracts() {
        let mut words = [0_u32; 1];
        let mut display = Display {
            inner: unsafe { sys::rv32_display_new(words.as_mut_ptr() as usize, 6) },
            _single_thread: PhantomData,
        };
        display.write(0xff123456);
        assert_eq!(display.read(), 0x123456);
        assert_eq!(display.digit_count(), 6);
        display.write_digit(0, 10).unwrap();
        assert_eq!(display.read_digit(0), Ok(10));
        assert_eq!(display.write_digit(6, 1), Err(Error::Rejected));
        assert_eq!(display.read_digit(6), Err(Error::Rejected));
        assert_eq!(display.write_digit(0, 16), Err(Error::Rejected));
        assert_eq!(words[0], 0x12345a);
    }
}

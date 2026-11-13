//! Validated display digits. Hardware indices and hexadecimal values are checked once.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_display_sys as sys;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Unavailable,
    InvalidDigit,
    InvalidValue,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Unavailable => "Display unavailable on this platform.",
            Self::InvalidDigit => "Digit index out of bounds.",
            Self::InvalidValue => "Hexadecimal digits are between 0 and 15.",
        })
    }
}

impl core::error::Error for Error {}

/// A hexadecimal value whose private representation is always in 0..=15.
///
/// ```compile_fail
/// let invalid = insper_riscv_display::HexDigit(16);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HexDigit(u8);

impl HexDigit {
    /// Validate an external value before using it in a digit write.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let value = HexDigit::new(10)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(value: u8) -> Result<Self, Error> {
        if value > 15 {
            return Err(Error::InvalidValue);
        }
        Ok(Self(value))
    }

    /// Return the validated hexadecimal value.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let value = HexDigit::new(10)?;
    /// assert_eq!(value.value(), 10);
    /// # Ok(())
    /// # }
    /// ```
    pub fn value(self) -> u8 {
        self.0
    }
}

/// A display selected by generated platform metadata. Not Send/Sync.
#[derive(Debug)]
pub struct Display {
    inner: sys::rv32_display_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Display {
    /// Validate the generated platform metadata without accessing MMIO.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let display = Display::new()?;
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

    /// Return the generated hardware width.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let display = Display::new()?;
    /// let count = display.digit_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn digit_count(&self) -> usize {
        self.inner.digit_count
    }

    /// Validate an index and exclusively borrow its display until the digit is released.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let mut digit = display.digit(0)?;
    /// digit.write(HexDigit::new(10)?);
    /// # Ok(())
    /// # }
    /// ```
    pub fn digit(&mut self, index: usize) -> Result<Digit<'_>, Error> {
        Digit::new(self, index)
    }

    /// Write the complete logical display word.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
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
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let word = display.read();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read(&self) -> u32 {
        unsafe { sys::rv32_display_read(self.inner) }
    }
}

/// A valid digit tied to the display which validated its index.
///
/// ```compile_fail
/// use insper_riscv_display::Display;
/// let digit = {
///     let mut display = Display::new().unwrap();
///     display.digit(0).unwrap()
/// };
/// let value = digit.read();
/// ```
#[derive(Debug)]
pub struct Digit<'a> {
    display: &'a mut Display,
    index: usize,
}

impl<'a> Digit<'a> {
    /// Construct a validated digit. Zero is the least significant digit.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let digit = insper_riscv_display::Digit::new(&mut display, 0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(display: &'a mut Display, index: usize) -> Result<Self, Error> {
        if index >= display.digit_count() {
            return Err(Error::InvalidDigit);
        }
        Ok(Self { display, index })
    }

    /// Return the already validated index.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// assert_eq!(display.digit(0)?.index(), 0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn index(&self) -> usize {
        self.index
    }

    /// Write a valid digit; neither its index nor its value can be invalid.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let mut digit = display.digit(0)?;
    /// digit.write(HexDigit::new(10)?);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write(&mut self, value: HexDigit) {
        unsafe { sys::rv32_display_write_digit(self.display.inner, self.index, value.0) };
    }

    /// Read a hexadecimal value; the hardware field is exactly four bits.
    ///
    /// ```no_run
    /// use insper_riscv_display::{Display, Error, HexDigit};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Display::new()?;
    /// let value = display.digit(0)?.read();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read(&self) -> HexDigit {
        let mut value = 0;
        unsafe { sys::rv32_display_read_digit(self.display.inner, self.index, &mut value) };
        HexDigit(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn constructor_rejects_absent_hardware_and_invalid_values() {
        assert!(matches!(Display::new(), Err(Error::Unavailable)));
        assert_eq!(HexDigit::new(16), Err(Error::InvalidValue));
        assert_eq!(HexDigit::new(u8::MAX), Err(Error::InvalidValue));
    }

    #[test]
    fn validated_digit_access_preserves_other_digits() {
        let mut words = [0_u32; 1];
        let mut display = Display {
            inner: unsafe { sys::rv32_display_new(words.as_mut_ptr() as usize, 6) },
            _single_thread: PhantomData,
        };
        display.write(0xff123456);
        assert_eq!(display.read(), 0x123456);
        assert_eq!(display.digit_count(), 6);
        assert!(matches!(display.digit(6), Err(Error::InvalidDigit)));
        assert!(matches!(
            display.digit(usize::MAX),
            Err(Error::InvalidDigit)
        ));
        {
            let mut digit = display.digit(0).unwrap();
            assert_eq!(digit.index(), 0);
            digit.write(HexDigit::new(10).unwrap());
            assert_eq!(digit.read().value(), 10);
            digit.write(HexDigit::new(15).unwrap());
            assert_eq!(digit.read().value(), 15);
        }
        assert_eq!(words[0], 0x12345f);
    }
}

//! Platform-selected LCD; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_lcd_sys as sys;

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
pub struct Lcd {
    inner: sys::rv32_lcd_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Lcd {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _device = Lcd::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _device = Lcd::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_lcd_new(index) };

        if !unsafe { sys::rv32_lcd_valid(inner) } {
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
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _count = Lcd::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_lcd_instance_count() }
    }

    /// Whether initialization or a queued LCD operation is active.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _state = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_lcd_busy(self.inner) }
    }

    /// Whether the hardware initialization is active.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _state = device.initializing();
    /// # Ok(())
    /// # }
    /// ```
    pub fn initializing(&mut self) -> bool {
        unsafe { sys::rv32_lcd_initializing(self.inner) }
    }

    /// Queued commands and data bytes.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _value = device.queue_level();
    /// # Ok(())
    /// # }
    /// ```
    pub fn queue_level(&mut self) -> u8 {
        unsafe { sys::rv32_lcd_queue_level(self.inner) }
    }

    /// Enable queue-empty interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// device.empty_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn empty_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_lcd_empty_interrupt(self.inner, enabled) };
    }

    /// Use the LCD busy line when this backend provides it.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// device.busy_polling(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy_polling(&mut self, enabled: bool) {
        unsafe { sys::rv32_lcd_busy_polling(self.inner, enabled) };
    }

    /// Control the LCD power output.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// device.power(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn power(&mut self, enabled: bool) {
        unsafe { sys::rv32_lcd_power(self.inner, enabled) };
    }

    /// Control the LCD backlight output.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// device.backlight(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn backlight(&mut self, enabled: bool) {
        unsafe { sys::rv32_lcd_backlight(self.inner, enabled) };
    }

    /// Clear only dropped-write and timeout flags (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// device.clear_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_errors(&mut self) {
        unsafe { sys::rv32_lcd_clear_errors(self.inner) };
    }

    /// Queue a controller command without waiting.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _result = device.try_command(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_command(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_lcd_try_command(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queue one character without waiting.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _result = device.try_write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_write(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_lcd_try_write(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queue clear-display; hardware supplies the required execution delay.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// let _result = device.clear();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear(&mut self) -> Result<(), Error> {
        self.try_command(1)
    }

    /// Queue a position validated for the 16-by-2 display.
    ///
    /// ```no_run
    /// use insper_riscv_lcd::{Lcd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Lcd::new()?;
    /// device.set_cursor(insper_riscv_lcd::Cursor::new(0, 0)?)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_cursor(&mut self, position: Cursor) -> Result<(), Error> {
        if unsafe {
            sys::rv32_lcd_cursor(self.inner, position.row as usize, position.column as usize)
        } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }
}

/// A validated position on the 16-by-2 LCD.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cursor {
    row: u8,
    column: u8,
}

impl Cursor {
    /// Validate a logical row and column, without hexadecimal addresses.
    /// ```
    /// use insper_riscv_lcd::Cursor;
    /// assert!(Cursor::new(1, 15).is_ok());
    /// assert!(Cursor::new(2, 0).is_err());
    /// ```
    pub const fn new(row: usize, column: usize) -> Result<Self, Error> {
        if row < 2 && column < 16 {
            Ok(Self {
                row: row as u8,
                column: column as u8,
            })
        } else {
            Err(Error::OutOfRange)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Lcd::instance_count();

        if count == 0 {
            assert!(matches!(Lcd::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Lcd::instance(count), Err(Error::Unavailable)));
        assert!(matches!(Lcd::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_lcd_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_lcd_valid(inner) });
        let mut device = Lcd {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.busy());
        unsafe { registers.as_mut_ptr().add(2).write_volatile(u32::MAX) };
        assert!(device.busy());
        unsafe { registers.as_mut_ptr().add(2).write_volatile(0) };
        assert!(!device.busy());
    }
}

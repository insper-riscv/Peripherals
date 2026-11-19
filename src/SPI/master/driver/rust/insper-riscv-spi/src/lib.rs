//! Platform-selected SPI; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_spi_sys as sys;

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
pub struct Spi {
    inner: sys::rv32_spi_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Spi {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _device = Spi::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _device = Spi::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_spi_new(index) };

        if !unsafe { sys::rv32_spi_valid(inner) } {
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
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _count = Spi::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_spi_instance_count() }
    }

    /// Whether queued or active transfers are still pending.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _state = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_spi_busy(self.inner) }
    }

    /// Whether the transmit queue accepts another word.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _state = device.tx_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn tx_ready(&mut self) -> bool {
        unsafe { sys::rv32_spi_tx_ready(self.inner) }
    }

    /// Whether the receive queue contains data.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _state = device.rx_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn rx_ready(&mut self) -> bool {
        unsafe { sys::rv32_spi_rx_ready(self.inner) }
    }

    /// Receive queue occupancy.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _value = device.receive_level();
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_level(&mut self) -> u8 {
        unsafe { sys::rv32_spi_receive_level(self.inner) }
    }

    /// Transmit queue occupancy.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _value = device.transmit_level();
    /// # Ok(())
    /// # }
    /// ```
    pub fn transmit_level(&mut self) -> u8 {
        unsafe { sys::rv32_spi_transmit_level(self.inner) }
    }

    /// Pop one received word, or return no data.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// if let Some(value) = device.try_read() {
    ///     let _ = value;
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_read(&mut self) -> Option<u32> {
        let mut value = 0;

        if unsafe { sys::rv32_spi_try_read(self.inner, &mut value) } {
            Some(value)
        } else {
            None
        }
    }

    /// Queue one word without waiting.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _result = device.try_write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_write(&mut self, value: u32) -> Result<(), Error> {
        if unsafe { sys::rv32_spi_try_write(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Clock a word while releasing MOSI.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// let _result = device.try_listen(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_listen(&mut self, value: u32) -> Result<(), Error> {
        if unsafe { sys::rv32_spi_try_listen(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Clear only DONE, RX_OVERRUN and TX_DROPPED (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_spi_clear_events(self.inner) };
    }

    /// Set the hardware half-clock divider.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// device.set_divider(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_divider(&mut self, value: u16) {
        unsafe { sys::rv32_spi_set_divider(self.inner, value) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// device.receive_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_spi_receive_interrupt(self.inner, enabled) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// device.empty_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn empty_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_spi_empty_interrupt(self.inner, enabled) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// device.done_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn done_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_spi_done_interrupt(self.inner, enabled) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_spi_error_interrupt(self.inner, enabled) };
    }

    /// Configure mode and width while idle; preserve chip select and IRQ masks.
    ///
    /// ```no_run
    /// use insper_riscv_spi::{Spi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Spi::new()?;
    /// device.configure(insper_riscv_spi::Mode::new(0)?, insper_riscv_spi::WordBits::new(8)?, false)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn configure(&mut self, mode: Mode, bits: WordBits, lsb_first: bool) -> Result<(), Error> {
        if u32::from(bits.value()) > self.inner.word_bits {
            return Err(Error::OutOfRange);
        }

        if unsafe { sys::rv32_spi_configure(self.inner, mode.value(), bits.value(), lsb_first) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_spi::WordBits(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WordBits(u8);

impl WordBits {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_spi::WordBits::new(1).unwrap();
    /// assert_eq!(value.value(), 1);
    /// ```
    pub const fn new(value: u8) -> Result<Self, Error> {
        if value >= 1 && value <= 32 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_spi::WordBits::new(1).unwrap();
    /// assert_eq!(value.value(), 1);
    /// ```
    pub const fn value(self) -> u8 {
        self.0
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_spi::Mode(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Mode(u8);

impl Mode {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_spi::Mode::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn new(value: u8) -> Result<Self, Error> {
        if value <= 3 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_spi::Mode::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn value(self) -> u8 {
        self.0
    }
}

/// A chip-select index tied to its originating controller.
pub struct ChipSelect<'a> {
    device: &'a mut Spi,
    index: usize,
}

impl<'a> ChipSelect<'a> {
    /// Validate a chip-select index once.
    /// ```no_run
    /// use insper_riscv_spi::{Spi, ChipSelect, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut spi = Spi::new()?;
    /// let mut cs = ChipSelect::new(&mut spi, 0)?;
    /// cs.set_asserted(false)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(device: &'a mut Spi, index: usize) -> Result<Self, Error> {
        if index >= device.inner.select_count as usize {
            return Err(Error::OutOfRange);
        }

        Ok(Self { device, index })
    }

    /// Assert or release this line; a busy transfer remains a real error.
    /// ```no_run
    /// use insper_riscv_spi::{Spi, ChipSelect, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut spi = Spi::new()?;
    /// let mut cs = ChipSelect::new(&mut spi, 0)?;
    /// cs.set_asserted(true)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_asserted(&mut self, asserted: bool) -> Result<(), Error> {
        if unsafe { sys::rv32_spi_select(self.device.inner, self.index, asserted) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Spi::instance_count();

        if count == 0 {
            assert!(matches!(Spi::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Spi::instance(count), Err(Error::Unavailable)));
        assert!(matches!(Spi::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_spi_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;
        inner.select_count = 1;
        inner.word_bits = 32;
        assert!(unsafe { sys::rv32_spi_valid(inner) });
        let mut device = Spi {
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

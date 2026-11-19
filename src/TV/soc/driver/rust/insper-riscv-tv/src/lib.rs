//! Platform-selected TV; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_tv_sys as sys;

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
pub struct Tv {
    inner: sys::rv32_tv_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Tv {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _device = Tv::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _device = Tv::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_tv_new(index) };

        if !unsafe { sys::rv32_tv_valid(inner) } {
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
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _count = Tv::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_tv_instance_count() }
    }

    /// Release the external receiver reset and enable its clock domain.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// device.enable(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_tv_enable(self.inner, enabled) };
    }

    /// Enable frame-ready interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// device.frame_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn frame_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_tv_frame_interrupt(self.inner, enabled) };
    }

    /// Enable receiver-error interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_tv_error_interrupt(self.inner, enabled) };
    }

    /// Whether a capture is in progress.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _state = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_tv_busy(self.inner) }
    }

    /// Whether a completed frame is available.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _state = device.ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn ready(&mut self) -> bool {
        unsafe { sys::rv32_tv_ready(self.inner) }
    }

    /// Whether a capture error is pending.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _state = device.has_error();
    /// # Ok(())
    /// # }
    /// ```
    pub fn has_error(&mut self) -> bool {
        unsafe { sys::rv32_tv_has_error(self.inner) }
    }

    /// Acknowledge frame-ready and error flags with W1C writes.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_tv_clear_events(self.inner) };
    }

    /// Number of completed frames.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _value = device.frame_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn frame_count(&mut self) -> u32 {
        unsafe { sys::rv32_tv_frame_count(self.inner) }
    }

    /// Frame width (TV pixels or MIPI bytes per line).
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _value = device.width();
    /// # Ok(())
    /// # }
    /// ```
    pub fn width(&mut self) -> u16 {
        unsafe { sys::rv32_tv_width(self.inner) }
    }

    /// Frame height in lines.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _value = device.height();
    /// # Ok(())
    /// # }
    /// ```
    pub fn height(&mut self) -> u16 {
        unsafe { sys::rv32_tv_height(self.inner) }
    }

    /// Request one capture; disabled/busy receiver state can block it.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _result = device.start();
    /// # Ok(())
    /// # }
    /// ```
    pub fn start(&mut self) -> Result<(), Error> {
        if unsafe { sys::rv32_tv_start(self.inner) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Read the immutable frame-memory capacity in 32-bit words.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let _words = device.word_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn word_count(&mut self) -> usize {
        unsafe { sys::rv32_tv_word_count(self.inner) }
    }

    /// Read a bounded frame range while capture is idle; no invented settle delay.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let mut words = [0; 4];
    /// let _result = device.read_words(0, &mut words);
    /// # Ok(())
    /// # }
    /// ```
    pub fn read_words(&mut self, first: usize, words: &mut [u32]) -> Result<(), Error> {
        let capacity = self.word_count();

        if first > capacity || words.len() > capacity - first {
            return Err(Error::OutOfRange);
        }

        if unsafe { sys::rv32_tv_read_words(self.inner, first, words.as_mut_ptr(), words.len()) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Set nonzero X/Y decimation factors while idle.
    ///
    /// ```no_run
    /// use insper_riscv_tv::{Tv, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Tv::new()?;
    /// let one = core::num::NonZeroU8::new(1).unwrap();
    /// device.set_decimation(one, one)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_decimation(
        &mut self,
        x: core::num::NonZeroU8,
        y: core::num::NonZeroU8,
    ) -> Result<(), Error> {
        if unsafe { sys::rv32_tv_set_decimation(self.inner, x.get(), y.get()) } {
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
        let count = Tv::instance_count();

        if count == 0 {
            assert!(matches!(Tv::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Tv::instance(count), Err(Error::Unavailable)));
        assert!(matches!(Tv::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_tv_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_tv_valid(inner) });
        let mut device = Tv {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.busy());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(u32::MAX) };
        assert!(device.busy());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(0) };
        assert!(!device.busy());
    }
}

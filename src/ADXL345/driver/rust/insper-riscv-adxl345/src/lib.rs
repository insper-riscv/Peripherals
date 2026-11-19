//! Platform-selected ADXL345; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_adxl345_sys as sys;

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
pub struct Adxl345 {
    inner: sys::rv32_adxl345_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Adxl345 {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _device = Adxl345::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _device = Adxl345::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_adxl345_new(index) };

        if !unsafe { sys::rv32_adxl345_valid(inner) } {
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
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _count = Adxl345::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_adxl345_instance_count() }
    }

    /// Read the signed raw axis sample; scaling depends on range/resolution.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _value = device.x();
    /// # Ok(())
    /// # }
    /// ```
    pub fn x(&mut self) -> i32 {
        unsafe { sys::rv32_adxl345_x(self.inner) }
    }

    /// Read the signed raw axis sample; scaling depends on range/resolution.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _value = device.y();
    /// # Ok(())
    /// # }
    /// ```
    pub fn y(&mut self) -> i32 {
        unsafe { sys::rv32_adxl345_y(self.inner) }
    }

    /// Read the signed raw axis sample; scaling depends on range/resolution.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _value = device.z();
    /// # Ok(())
    /// # }
    /// ```
    pub fn z(&mut self) -> i32 {
        unsafe { sys::rv32_adxl345_z(self.inner) }
    }

    /// Whether a transaction is active or pending.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _state = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_adxl345_busy(self.inner) }
    }

    /// Whether a new sample arrived since acknowledgement.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _state = device.sample_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn sample_ready(&mut self) -> bool {
        unsafe { sys::rv32_adxl345_sample_ready(self.inner) }
    }

    /// Whether any sample has arrived since reset.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _state = device.valid_sample();
    /// # Ok(())
    /// # }
    /// ```
    pub fn valid_sample(&mut self) -> bool {
        unsafe { sys::rv32_adxl345_valid_sample(self.inner) }
    }

    /// Whether device configuration has completed.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _state = device.configured();
    /// # Ok(())
    /// # }
    /// ```
    pub fn configured(&mut self) -> bool {
        unsafe { sys::rv32_adxl345_configured(self.inner) }
    }

    /// Clear SAMPLE and I2C NACK/arbitration flags without read-modify-write.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_adxl345_clear_events(self.inner) };
    }

    /// Enable automatic device configuration and sampling.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.enable(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_adxl345_enable(self.inner, enabled) };
    }

    /// Enable sample-available interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.enable_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_adxl345_enable_interrupt(self.inner, enabled) };
    }

    /// Select full-resolution operation on the next configuration.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.full_resolution(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn full_resolution(&mut self, enabled: bool) {
        unsafe { sys::rv32_adxl345_full_resolution(self.inner, enabled) };
    }

    /// Use the external data-ready line instead of periodic sampling.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.interrupt_triggered(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn interrupt_triggered(&mut self, enabled: bool) {
        unsafe { sys::rv32_adxl345_interrupt_triggered(self.inner, enabled) };
    }

    /// Read the identifier returned by the chip.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// let _value = device.device_id();
    /// # Ok(())
    /// # }
    /// ```
    pub fn device_id(&mut self) -> u8 {
        unsafe { sys::rv32_adxl345_device_id(self.inner) }
    }

    /// Set the serial clock divider; I2C hardware clamps values below two.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.set_divider(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_divider(&mut self, value: u16) {
        unsafe { sys::rv32_adxl345_set_divider(self.inner, value) };
    }

    /// Apply a validated accelerometer configuration value.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.set_range(insper_riscv_adxl345::Range::new(0)?);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_range(&mut self, value: Range) {
        unsafe { sys::rv32_adxl345_set_range(self.inner, value.value()) };
    }

    /// Apply a validated accelerometer configuration value.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.set_rate(insper_riscv_adxl345::Rate::new(0)?);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_rate(&mut self, value: Rate) {
        unsafe { sys::rv32_adxl345_set_rate(self.inner, value.value()) };
    }

    /// Apply a validated accelerometer configuration value.
    ///
    /// ```no_run
    /// use insper_riscv_adxl345::{Adxl345, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adxl345::new()?;
    /// device.set_period(insper_riscv_adxl345::Period::new(1)?);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_period(&mut self, value: Period) {
        unsafe { sys::rv32_adxl345_set_period(self.inner, value.value()) };
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_adxl345::Range(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Range(u8);

impl Range {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_adxl345::Range::new(0).unwrap();
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
    /// let value = insper_riscv_adxl345::Range::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn value(self) -> u8 {
        self.0
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_adxl345::Rate(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rate(u8);

impl Rate {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_adxl345::Rate::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn new(value: u8) -> Result<Self, Error> {
        if value <= 15 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_adxl345::Rate::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn value(self) -> u8 {
        self.0
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_adxl345::Period(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Period(u32);

impl Period {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_adxl345::Period::new(1).unwrap();
    /// assert_eq!(value.value(), 1);
    /// ```
    pub const fn new(value: u32) -> Result<Self, Error> {
        if value >= 1 && value <= 16777215 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_adxl345::Period::new(1).unwrap();
    /// assert_eq!(value.value(), 1);
    /// ```
    pub const fn value(self) -> u32 {
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Adxl345::instance_count();

        if count == 0 {
            assert!(matches!(Adxl345::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Adxl345::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            Adxl345::instance(usize::MAX),
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
        let mut inner = unsafe { sys::rv32_adxl345_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_adxl345_valid(inner) });
        let mut device = Adxl345 {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.busy());
        unsafe { registers.as_mut_ptr().add(3).write_volatile(u32::MAX) };
        assert!(device.busy());
        unsafe { registers.as_mut_ptr().add(3).write_volatile(0) };
        assert!(!device.busy());
    }
}

//! Platform-selected ADC; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_adc_sys as sys;

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
pub struct Adc {
    inner: sys::rv32_adc_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Adc {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _device = Adc::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _device = Adc::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_adc_new(index) };

        if !unsafe { sys::rv32_adc_valid(inner) } {
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
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _count = Adc::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_adc_instance_count() }
    }

    /// Number of channels of this converter backend.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _count = device.channel_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn channel_count(&self) -> usize {
        self.inner.channels as usize
    }

    /// Whether a conversion sweep is active.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _busy = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_adc_busy(self.inner) }
    }

    /// Whether a sweep completed since acknowledgement.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _done = device.done();
    /// # Ok(())
    /// # }
    /// ```
    pub fn done(&mut self) -> bool {
        unsafe { sys::rv32_adc_done(self.inner) }
    }

    /// Enable or stop continuous sweeps; an active conversion completes normally.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// device.continuous(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn continuous(&mut self, enabled: bool) {
        unsafe { sys::rv32_adc_continuous(self.inner, enabled) };
    }

    /// Enable the backend-specific sweep-done interrupt.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// device.enable_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_adc_enable_interrupt(self.inner, enabled) };
    }

    /// Start one sweep without waiting; busy hardware can block the request.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _result = device.start();
    /// # Ok(())
    /// # }
    /// ```
    pub fn start(&mut self) -> Result<(), Error> {
        if unsafe { sys::rv32_adc_start(self.inner) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Acknowledge only backend-defined W1C completion/error flags.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_adc_clear_events(self.inner) };
    }

    /// Validate a logical channel once and borrow its originating converter.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let mut channel = device.channel(0)?;
    /// let sample = channel.read();
    /// let _value = sample.value();
    /// # Ok(())
    /// # }
    /// ```
    pub fn channel(&mut self, index: usize) -> Result<Channel<'_>, Error> {
        Channel::new(self, index)
    }

    /// Select MAX10 scan channels while idle; external converters always scan all eight.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let mask = insper_riscv_adc::ChannelMask::new(1)?;
    /// let _result = device.set_mask(mask);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_mask(&mut self, mask: ChannelMask) -> Result<(), Error> {
        if self.inner.backend != 1 {
            return Err(Error::Unsupported);
        }

        if unsafe { sys::rv32_adc_set_mask(self.inner, mask.value()) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Set the MAX10 continuous-scan period while idle.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _result = device.set_period(core::num::NonZeroU32::new(50_000).unwrap());
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_period(&mut self, cycles: core::num::NonZeroU32) -> Result<(), Error> {
        if self.inner.backend != 1 {
            return Err(Error::Unsupported);
        }

        if unsafe { sys::rv32_adc_set_period(self.inner, cycles.get()) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Set the external ADC serial divider while idle; unavailable on MAX10.
    ///
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Adc::new()?;
    /// let _result = device.set_serial_divider(49);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_serial_divider(&mut self, divider: u16) -> Result<(), Error> {
        if self.inner.backend != 0 {
            return Err(Error::Unsupported);
        }

        if unsafe { sys::rv32_adc_set_serial_divider(self.inner, divider) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }
}

/// A validated channel tied to its converter.
pub struct Channel<'a> {
    device: &'a mut Adc,
    index: usize,
}

impl<'a> Channel<'a> {
    /// Validate a zero-based converter channel.
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Channel, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut adc = Adc::new()?;
    /// let mut channel = Channel::new(&mut adc, 0)?;
    /// let _sample = channel.read();
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(device: &'a mut Adc, index: usize) -> Result<Self, Error> {
        if index >= device.channel_count() {
            return Err(Error::OutOfRange);
        }

        Ok(Self { device, index })
    }

    /// Read one sample, consuming MAX10 freshness flags exactly once.
    /// ```no_run
    /// use insper_riscv_adc::{Adc, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut adc = Adc::new()?;
    /// let mut channel = adc.channel(0)?;
    /// let sample = channel.read();
    /// let _raw = sample.value();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read(&mut self) -> Sample {
        Sample::new(unsafe { sys::rv32_adc_read_channel(self.device.inner, self.index) })
    }
}

/// One raw ADC sample and the freshness flags returned with it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sample(u32);

impl Sample {
    fn new(raw: u32) -> Self {
        Self(raw)
    }

    /// The 12-bit conversion value; voltage conversion needs board calibration.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_adc::Error> {
    /// let mut adc = insper_riscv_adc::Adc::new()?;
    /// let sample = adc.channel(0)?.read();
    /// let _value = sample.value();
    /// # Ok(())
    /// # }
    /// ```
    pub const fn value(self) -> u16 {
        (self.0 & 4095) as u16
    }

    /// Whether this backend reported a valid sample.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_adc::Error> {
    /// let mut adc = insper_riscv_adc::Adc::new()?;
    /// let _valid = adc.channel(0)?.read().valid();
    /// # Ok(())
    /// # }
    /// ```
    pub const fn valid(self) -> bool {
        self.0 & 4096 != 0
    }

    /// Whether MAX10 replaced an unread result.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_adc::Error> {
    /// let mut adc = insper_riscv_adc::Adc::new()?;
    /// let _overrun = adc.channel(0)?.read().overrun();
    /// # Ok(())
    /// # }
    /// ```
    pub const fn overrun(self) -> bool {
        self.0 & 8192 != 0
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_adc::ChannelMask(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChannelMask(u32);

impl ChannelMask {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_adc::ChannelMask::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn new(value: u32) -> Result<Self, Error> {
        if value <= 262143 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_adc::ChannelMask::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
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
        let count = Adc::instance_count();

        if count == 0 {
            assert!(matches!(Adc::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Adc::instance(count), Err(Error::Unavailable)));
        assert!(matches!(Adc::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_adc_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;
        inner.backend = 0;
        inner.channels = 8;
        assert!(unsafe { sys::rv32_adc_valid(inner) });
        let mut device = Adc {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.busy());
        unsafe { registers.as_mut_ptr().add(9).write_volatile(u32::MAX) };
        assert!(device.busy());
        unsafe { registers.as_mut_ptr().add(9).write_volatile(0) };
        assert!(!device.busy());
    }
}

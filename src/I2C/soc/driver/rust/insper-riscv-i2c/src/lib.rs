//! Platform-selected I2C; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_i2c_sys as sys;

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
pub struct I2c {
    inner: sys::rv32_i2c_t,
    _single_thread: PhantomData<*mut ()>,
}

impl I2c {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _device = I2c::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _device = I2c::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_i2c_new(index) };

        if !unsafe { sys::rv32_i2c_valid(inner) } {
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
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _count = I2c::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_i2c_instance_count() }
    }

    /// Enable the I2C controller.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// device.enable(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_i2c_enable(self.inner, enabled) };
    }

    /// Enable command completion interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// device.done_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn done_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_i2c_done_interrupt(self.inner, enabled) };
    }

    /// Enable NACK/arbitration/rejection interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_i2c_error_interrupt(self.inner, enabled) };
    }

    /// Abort and release the bus; preserve interrupt enables.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// device.abort();
    /// # Ok(())
    /// # }
    /// ```
    pub fn abort(&mut self) {
        unsafe { sys::rv32_i2c_abort(self.inner) };
    }

    /// Whether a command is executing.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _state = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_i2c_busy(self.inner) }
    }

    /// Whether a transaction remains open.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _state = device.bus_active();
    /// # Ok(())
    /// # }
    /// ```
    pub fn bus_active(&mut self) -> bool {
        unsafe { sys::rv32_i2c_bus_active(self.inner) }
    }

    /// Whether the last command completed.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _state = device.done();
    /// # Ok(())
    /// # }
    /// ```
    pub fn done(&mut self) -> bool {
        unsafe { sys::rv32_i2c_done(self.inner) }
    }

    /// Whether the slave failed to acknowledge.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _state = device.nack();
    /// # Ok(())
    /// # }
    /// ```
    pub fn nack(&mut self) -> bool {
        unsafe { sys::rv32_i2c_nack(self.inner) }
    }

    /// Whether arbitration was lost.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _state = device.arbitration_lost();
    /// # Ok(())
    /// # }
    /// ```
    pub fn arbitration_lost(&mut self) -> bool {
        unsafe { sys::rv32_i2c_arbitration_lost(self.inner) }
    }

    /// Whether hardware rejected a command.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _state = device.rejected();
    /// # Ok(())
    /// # }
    /// ```
    pub fn rejected(&mut self) -> bool {
        unsafe { sys::rv32_i2c_rejected(self.inner) }
    }

    /// Clear only sticky completion/error flags (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_i2c_clear_events(self.inner) };
    }

    /// Configure a validated I2C clock divider.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// device.set_divider(insper_riscv_i2c::Divider::new(99)?);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_divider(&mut self, divider: Divider) {
        unsafe { sys::rv32_i2c_set_divider(self.inner, divider.value()) };
    }

    /// Queue this I2C bus action; disabled/busy/closed-bus state can block it.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _result = device.start_write(0xA0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn start_write(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_i2c_start_write(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queue this I2C bus action; disabled/busy/closed-bus state can block it.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _result = device.write_byte(0xA0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write_byte(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_i2c_write_byte(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queue this I2C bus action; disabled/busy/closed-bus state can block it.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _result = device.write_stop(0xA0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write_stop(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_i2c_write_stop(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queue this I2C bus action; disabled/busy/closed-bus state can block it.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _result = device.read_ack();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read_ack(&mut self) -> Result<(), Error> {
        if unsafe { sys::rv32_i2c_read_ack(self.inner) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queue this I2C bus action; disabled/busy/closed-bus state can block it.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _result = device.read_stop();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read_stop(&mut self) -> Result<(), Error> {
        if unsafe { sys::rv32_i2c_read_stop(self.inner) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Queue this I2C bus action; disabled/busy/closed-bus state can block it.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _result = device.stop();
    /// # Ok(())
    /// # }
    /// ```
    pub fn stop(&mut self) -> Result<(), Error> {
        if unsafe { sys::rv32_i2c_stop(self.inner) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Read the byte from the last completed read command.
    ///
    /// ```no_run
    /// use insper_riscv_i2c::{I2c, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = I2c::new()?;
    /// let _value = device.received_byte();
    /// # Ok(())
    /// # }
    /// ```
    pub fn received_byte(&mut self) -> u8 {
        unsafe { sys::rv32_i2c_received_byte(self.inner) }
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_i2c::Divider(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Divider(u16);

impl Divider {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_i2c::Divider::new(2).unwrap();
    /// assert_eq!(value.value(), 2);
    /// ```
    pub const fn new(value: u16) -> Result<Self, Error> {
        if value >= 2 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_i2c::Divider::new(2).unwrap();
    /// assert_eq!(value.value(), 2);
    /// ```
    pub const fn value(self) -> u16 {
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = I2c::instance_count();

        if count == 0 {
            assert!(matches!(I2c::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(I2c::instance(count), Err(Error::Unavailable)));
        assert!(matches!(I2c::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_i2c_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_i2c_valid(inner) });
        let mut device = I2c {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.busy());
        unsafe { registers.as_mut_ptr().add(5).write_volatile(u32::MAX) };
        assert!(device.busy());
        unsafe { registers.as_mut_ptr().add(5).write_volatile(0) };
        assert!(!device.busy());
    }
}

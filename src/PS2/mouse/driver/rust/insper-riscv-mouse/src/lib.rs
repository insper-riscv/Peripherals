//! Platform-selected MOUSE; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_mouse_sys as sys;

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
pub struct Mouse {
    inner: sys::rv32_mouse_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Mouse {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// let _device = Mouse::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// let _device = Mouse::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_mouse_new(index) };

        if !unsafe { sys::rv32_mouse_valid(inner) } {
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
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// let _count = Mouse::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_mouse_instance_count() }
    }

    /// Read mouse status once; clears NEW, OVERFLOW and ERROR flags.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// let _value = device.read_status_clear();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read_status_clear(&mut self) -> Status {
        Status::new(unsafe { sys::rv32_mouse_read_status_clear(self.inner) })
    }

    /// Consume the accumulated signed X displacement.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// let _value = device.take_dx();
    /// # Ok(())
    /// # }
    /// ```
    pub fn take_dx(&mut self) -> i32 {
        unsafe { sys::rv32_mouse_take_dx(self.inner) }
    }

    /// Consume the accumulated signed Y displacement.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// let _value = device.take_dy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn take_dy(&mut self) -> i32 {
        unsafe { sys::rv32_mouse_take_dy(self.inner) }
    }

    /// Read left/right/middle button bits without clearing motion.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// let _value = device.buttons();
    /// # Ok(())
    /// # }
    /// ```
    pub fn buttons(&mut self) -> u8 {
        unsafe { sys::rv32_mouse_buttons(self.inner) }
    }

    /// Enable new-packet interrupts; reading status clears the cause.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// device.enable_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_mouse_enable_interrupt(self.inner, enabled) };
    }

    /// Restart initialization while preserving the interrupt enable.
    ///
    /// ```no_run
    /// use insper_riscv_mouse::{Mouse, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Mouse::new()?;
    /// device.reinitialize();
    /// # Ok(())
    /// # }
    /// ```
    pub fn reinitialize(&mut self) {
        unsafe { sys::rv32_mouse_reinitialize(self.inner) };
    }
}

/// A snapshot of mouse events; reading it never clears hardware a second time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Status(u32);

impl Status {
    fn new(value: u32) -> Self {
        Self(value)
    }

    /// Query the new_packet flag captured by one status-register read.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_mouse::Error> {
    /// let mut mouse = insper_riscv_mouse::Mouse::new()?;
    /// let _flag = mouse.read_status_clear().new_packet();
    /// # Ok(())
    /// # }
    /// ```
    pub const fn new_packet(self) -> bool {
        self.0 & (1 << 0) != 0
    }

    /// Query the overflowed flag captured by one status-register read.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_mouse::Error> {
    /// let mut mouse = insper_riscv_mouse::Mouse::new()?;
    /// let _flag = mouse.read_status_clear().overflowed();
    /// # Ok(())
    /// # }
    /// ```
    pub const fn overflowed(self) -> bool {
        self.0 & (1 << 1) != 0
    }

    /// Query the error flag captured by one status-register read.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_mouse::Error> {
    /// let mut mouse = insper_riscv_mouse::Mouse::new()?;
    /// let _flag = mouse.read_status_clear().error();
    /// # Ok(())
    /// # }
    /// ```
    pub const fn error(self) -> bool {
        self.0 & (1 << 2) != 0
    }

    /// Query the streaming flag captured by one status-register read.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_mouse::Error> {
    /// let mut mouse = insper_riscv_mouse::Mouse::new()?;
    /// let _flag = mouse.read_status_clear().streaming();
    /// # Ok(())
    /// # }
    /// ```
    pub const fn streaming(self) -> bool {
        self.0 & (1 << 3) != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Mouse::instance_count();

        if count == 0 {
            assert!(matches!(Mouse::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Mouse::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            Mouse::instance(usize::MAX),
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
        let mut inner = unsafe { sys::rv32_mouse_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_mouse_valid(inner) });
        let mut device = Mouse {
            inner,
            _single_thread: PhantomData,
        };
        assert_eq!(device.buttons(), 0);
        unsafe { registers.as_mut_ptr().add(3).write_volatile(u32::MAX) };
        assert_eq!(device.buttons(), 7);
        unsafe { registers.as_mut_ptr().add(3).write_volatile(0) };
        assert_eq!(device.buttons(), 0);
    }
}

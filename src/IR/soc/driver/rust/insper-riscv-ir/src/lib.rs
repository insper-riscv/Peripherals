//! Platform-selected IR; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_ir_sys as sys;

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
pub struct Ir {
    inner: sys::rv32_ir_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Ir {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// let _device = Ir::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// let _device = Ir::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_ir_new(index) };

        if !unsafe { sys::rv32_ir_valid(inner) } {
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
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// let _count = Ir::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_ir_instance_count() }
    }

    /// Enable reception without flushing pending frames.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// device.enable(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_ir_enable(self.inner, enabled) };
    }

    /// Enable frame-available interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// device.frame_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn frame_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_ir_frame_interrupt(self.inner, enabled) };
    }

    /// Enable malformed-frame and overflow interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_ir_error_interrupt(self.inner, enabled) };
    }

    /// Accept extended 16-bit NEC addresses.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// device.extended_addresses(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn extended_addresses(&mut self, enabled: bool) {
        unsafe { sys::rv32_ir_extended_addresses(self.inner, enabled) };
    }

    /// Enable raw timing measurement interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// device.raw_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn raw_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_ir_raw_interrupt(self.inner, enabled) };
    }

    /// Discard queued frames without altering enables.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// device.flush();
    /// # Ok(())
    /// # }
    /// ```
    pub fn flush(&mut self) {
        unsafe { sys::rv32_ir_flush(self.inner) };
    }

    /// Whether a complete NEC frame is queued.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// let _state = device.ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn ready(&mut self) -> bool {
        unsafe { sys::rv32_ir_ready(self.inner) }
    }

    /// Clear frame error, overflow and raw-new flags (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_ir_clear_events(self.inner) };
    }

    /// Pop one packed NEC frame; None means the FIFO is empty.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// if let Some(value) = device.try_read() {
    ///     let _ = value;
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_read(&mut self) -> Option<Frame> {
        let mut value = 0;

        if unsafe { sys::rv32_ir_try_read(self.inner, &mut value) } {
            Some(Frame::new(value))
        } else {
            None
        }
    }

    /// Duration of the most recent infrared mark.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// let _value = device.raw_mark_cycles();
    /// # Ok(())
    /// # }
    /// ```
    pub fn raw_mark_cycles(&mut self) -> u32 {
        unsafe { sys::rv32_ir_raw_mark_cycles(self.inner) }
    }

    /// Duration of the most recent infrared space.
    ///
    /// ```no_run
    /// use insper_riscv_ir::{Ir, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ir::new()?;
    /// let _value = device.raw_space_cycles();
    /// # Ok(())
    /// # }
    /// ```
    pub fn raw_space_cycles(&mut self) -> u32 {
        unsafe { sys::rv32_ir_raw_space_cycles(self.inner) }
    }
}

/// A decoded NEC frame, returned only when a complete record was queued.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Frame(u32);

impl Frame {
    fn new(value: u32) -> Self {
        Self(value)
    }

    /// Read the decoded address field without consuming another hardware frame.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_ir::Error> {
    /// let mut ir = insper_riscv_ir::Ir::new()?;
    /// if let Some(frame) = ir.try_read() {
    ///     let _value = frame.address();
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub const fn address(self) -> u16 {
        self.0 as u16
    }

    /// Read the decoded command field without consuming another hardware frame.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_ir::Error> {
    /// let mut ir = insper_riscv_ir::Ir::new()?;
    /// if let Some(frame) = ir.try_read() {
    ///     let _value = frame.command();
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub const fn command(self) -> u8 {
        (self.0 >> 16) as u8
    }

    /// Read the decoded repeated field without consuming another hardware frame.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_ir::Error> {
    /// let mut ir = insper_riscv_ir::Ir::new()?;
    /// if let Some(frame) = ir.try_read() {
    ///     let _value = frame.repeated();
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub const fn repeated(self) -> bool {
        self.0 & (1 << 24) != 0
    }

    /// Read the decoded extended field without consuming another hardware frame.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_ir::Error> {
    /// let mut ir = insper_riscv_ir::Ir::new()?;
    /// if let Some(frame) = ir.try_read() {
    ///     let _value = frame.extended();
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub const fn extended(self) -> bool {
        self.0 & (1 << 25) != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Ir::instance_count();

        if count == 0 {
            assert!(matches!(Ir::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Ir::instance(count), Err(Error::Unavailable)));
        assert!(matches!(Ir::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_ir_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_ir_valid(inner) });
        let mut device = Ir {
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

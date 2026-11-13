//! Platform-selected CLINT. No heap, raw addresses or register offsets.
//! Handles are not Send/Sync. Serialize configuration, including interrupt handlers.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_clint_sys as sys;

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
pub struct Clint {
    inner: sys::rv32_clint_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Clint {
    /// Construct using generated platform metadata; does not reset the hardware.
    /// ```no_run
    /// use insper_riscv_clint::{Clint, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut clint = Clint::new()?;
    /// let available = Clint::new();
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_clint_platform_new() };
        if !unsafe { sys::rv32_clint_valid(inner) } {
            return Err(Error::Unavailable);
        }
        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }
    /// Read a coherent 64-bit time using the RV32 high/low/high sequence.
    /// ```no_run
    /// use insper_riscv_clint::{Clint, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut clint = Clint::new()?;
    /// let ticks = clint.time();
    /// # Ok(())
    /// # }
    /// ```
    pub fn time(&mut self) -> u64 {
        unsafe { sys::rv32_clint_time(self.inner) }
    }
    /// Update the deadline without transient spurious RV32 timer interrupts.
    /// ```no_run
    /// use insper_riscv_clint::{Clint, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut clint = Clint::new()?;
    /// clint.set_deadline(u64::MAX);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_deadline(&mut self, ticks: u64) {
        unsafe { sys::rv32_clint_set_deadline(self.inner, ticks) };
    }
    /// Set or clear the software interrupt source.
    /// ```no_run
    /// use insper_riscv_clint::{Clint, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut clint = Clint::new()?;
    /// clint.set_software_interrupt(true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_software_interrupt(&mut self, pending: bool) {
        unsafe { sys::rv32_clint_software_irq(self.inner, pending) };
    }
    /// Read the software interrupt source state.
    /// ```no_run
    /// use insper_riscv_clint::{Clint, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut clint = Clint::new()?;
    /// let pending = clint.software_interrupt_pending();
    /// # Ok(())
    /// # }
    /// ```
    pub fn software_interrupt_pending(&mut self) -> bool {
        unsafe { sys::rv32_clint_software_irq_pending(self.inner) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unconfigured_factory_is_safe() {
        assert!(matches!(Clint::new(), Err(Error::Unavailable)));
    }

    #[test]
    fn ffi_registers_boundaries_and_side_effect_contracts() {
        extern crate std;
        let mut words = std::vec![0_u32; 0xc000 / 4];
        let mut clint = Clint {
            inner: unsafe { sys::rv32_clint_new(words.as_mut_ptr() as usize) },
            _single_thread: PhantomData,
        };
        words[0xbff8 / 4] = 0x12345678;
        words[0xbffc / 4] = 0xabcdef01;
        assert_eq!(clint.time(), 0xabcdef0112345678);
        clint.set_deadline(0x9876543212345678);
        assert_eq!(words[0x4000 / 4], 0x12345678);
        assert_eq!(words[0x4004 / 4], 0x98765432);
        clint.set_software_interrupt(true);
        assert!(clint.software_interrupt_pending());
        clint.set_software_interrupt(false);
        assert!(!clint.software_interrupt_pending());
    }
}

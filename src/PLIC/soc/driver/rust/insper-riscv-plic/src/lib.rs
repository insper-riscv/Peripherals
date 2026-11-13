//! Platform-selected PLIC. No heap, raw addresses or register offsets.
//! Handles are not Send/Sync. Serialize configuration, including interrupt handlers.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_plic_sys as sys;

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
pub struct Plic {
    inner: sys::rv32_plic_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Plic {
    /// Construct using generated platform metadata; does not reset the hardware.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// let available = Plic::new();
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_plic_platform_new() };
        if !unsafe { sys::rv32_plic_valid(inner) } {
            return Err(Error::Unavailable);
        }
        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }
    /// Return the generated number of sources; IDs are 1 through this count.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// let count = plic.source_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn source_count(&mut self) -> usize {
        self.inner.source_count
    }
    /// Set a source priority. Zero disables its priority.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// plic.set_priority(1, 1)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_priority(&mut self, source: usize, priority: u32) -> Result<(), Error> {
        checked(unsafe { sys::rv32_plic_set_priority(self.inner, source, priority) })
    }
    /// Set the acceptance threshold.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// plic.set_threshold(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_threshold(&mut self, priority: u32) -> Result<(), Error> {
        checked(unsafe { sys::rv32_plic_set_threshold(self.inner, priority) })
    }
    /// Enable a source. Configuration is read/modify/write and must be serialized.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// plic.enable(1, true)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable(&mut self, source: usize, enabled: bool) -> Result<(), Error> {
        checked(unsafe { sys::rv32_plic_enable(self.inner, source, enabled) })
    }
    /// Read pending state for a valid source.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// let pending = plic.pending(1)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn pending(&mut self, source: usize) -> Result<bool, Error> {
        if source == 0 || source > self.inner.source_count {
            return Err(Error::Rejected);
        }
        Ok(unsafe { sys::rv32_plic_pending(self.inner, source) })
    }
    /// Claim consumes the winning pending request; None means no candidate.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// let source = plic.claim();
    /// # Ok(())
    /// # }
    /// ```
    pub fn claim(&mut self) -> Option<usize> {
        match unsafe { sys::rv32_plic_claim(self.inner) } {
            0 => None,
            id => Some(id),
        }
    }
    /// Complete a previously claimed request.
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// if let Some(source) = plic.claim() { plic.complete(source)?; }
    /// # Ok(())
    /// # }
    /// ```
    pub fn complete(&mut self, source: usize) -> Result<(), Error> {
        checked(unsafe { sys::rv32_plic_complete(self.inner, source) })
    }
}

fn checked(accepted: bool) -> Result<(), Error> {
    if accepted {
        Ok(())
    } else {
        Err(Error::Rejected)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unconfigured_factory_is_safe() {
        assert!(matches!(Plic::new(), Err(Error::Unavailable)));
    }

    #[test]
    fn ffi_registers_boundaries_and_side_effect_contracts() {
        extern crate std;
        let mut words = std::vec![0_u32; 0x200008 / 4];
        let mut plic = Plic {
            inner: unsafe { sys::rv32_plic_new(words.as_mut_ptr() as usize, 40, 3) },
            _single_thread: PhantomData,
        };
        assert_eq!(plic.set_priority(0, 1), Err(Error::Rejected));
        assert_eq!(plic.set_priority(41, 1), Err(Error::Rejected));
        assert_eq!(plic.set_priority(1, 8), Err(Error::Rejected));
        plic.set_priority(40, 7).unwrap();
        assert_eq!(words[40], 7);
        plic.enable(32, true).unwrap();
        assert_eq!(words[0x2004 / 4], 1);
        plic.enable(32, false).unwrap();
        assert_eq!(words[0x2004 / 4], 0);
        plic.set_threshold(2).unwrap();
        assert_eq!(words[0x200000 / 4], 2);
        assert_eq!(plic.set_threshold(8), Err(Error::Rejected));
        words[0x1004 / 4] = 1;
        assert!(plic.pending(32).unwrap());
        assert_eq!(plic.pending(0), Err(Error::Rejected));
        words[0x200004 / 4] = 40;
        assert_eq!(plic.claim(), Some(40));
        plic.complete(40).unwrap();
        assert_eq!(words[0x200004 / 4], 40);
        assert_eq!(plic.complete(41), Err(Error::Rejected));
        assert_eq!(plic.source_count(), 40);
    }
}

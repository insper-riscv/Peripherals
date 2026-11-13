//! PLIC source and claim handles keep validated source IDs private.
//! Handles are not Send/Sync; serialize access with any C or interrupt callers.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_plic_sys as sys;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Unavailable,
    InvalidSource,
    InvalidPriority,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Unavailable => "PLIC unavailable on this platform.",
            Self::InvalidSource => "Source ID is outside the platform's range.",
            Self::InvalidPriority => "Priority exceeds the platform's supported range.",
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
    /// Validate the generated PLIC configuration.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let plic = Plic::new()?;
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

    /// Return the number of sources; valid IDs start at one.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let plic = Plic::new()?;
    /// let count = plic.source_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn source_count(&self) -> usize {
        self.inner.source_count
    }

    /// Validate an ID once and borrow the controller for source operations.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// let mut source = plic.source(1)?;
    /// source.enable(true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn source(&mut self, id: usize) -> Result<Source<'_>, Error> {
        Source::new(self, id)
    }

    /// Accept a new threshold, checking its platform-dependent numeric range.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// plic.set_threshold(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_threshold(&mut self, priority: u32) -> Result<(), Error> {
        if priority > self.inner.max_priority {
            return Err(Error::InvalidPriority);
        }
        unsafe { sys::rv32_plic_set_threshold(self.inner, priority) };
        Ok(())
    }

    /// Claim a pending request. The returned token can be completed exactly once.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// if let Some(claim) = plic.claim() {
    ///     let source_id = claim.id();
    ///     // Service the peripheral before completing its interrupt.
    ///     claim.complete();
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn claim(&mut self) -> Option<Claim<'_>> {
        let id = unsafe { sys::rv32_plic_claim(self.inner) };
        if id == 0 || id > self.source_count() {
            return None;
        }
        Some(Claim::new(self, id))
    }
}

/// A validated source, inseparable from its controller.
#[derive(Debug)]
pub struct Source<'a> {
    plic: &'a mut Plic,
    id: usize,
}

impl<'a> Source<'a> {
    /// Validate an external ID at the construction boundary.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// let source = insper_riscv_plic::Source::new(&mut plic, 1)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(plic: &'a mut Plic, id: usize) -> Result<Self, Error> {
        if id == 0 || id > plic.source_count() {
            return Err(Error::InvalidSource);
        }
        Ok(Self { plic, id })
    }

    /// Return the source ID.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// assert_eq!(plic.source(1)?.id(), 1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn id(&self) -> usize {
        self.id
    }

    /// Set a new priority. Zero disables priority; new values are range checked.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// plic.source(1)?.set_priority(1)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_priority(&mut self, priority: u32) -> Result<(), Error> {
        if priority > self.plic.inner.max_priority {
            return Err(Error::InvalidPriority);
        }
        unsafe { sys::rv32_plic_set_priority(self.plic.inner, self.id, priority) };
        Ok(())
    }

    /// Enable or disable a valid source.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// plic.source(1)?.enable(true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_plic_enable(self.plic.inner, self.id, enabled) };
    }

    /// Read the source pending bit without claiming it.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// let pending = plic.source(1)?.pending();
    /// # Ok(())
    /// # }
    /// ```
    pub fn pending(&self) -> bool {
        unsafe { sys::rv32_plic_pending(self.plic.inner, self.id) }
    }
}

/// A non-cloneable claim borrowed from its controller. Call complete after servicing.
/// Dropping it does not complete the hardware request.
///
/// ```compile_fail
/// use insper_riscv_plic::Plic;
/// let mut plic = Plic::new().unwrap();
/// let claim = plic.claim().unwrap();
/// claim.complete();
/// claim.complete(); // The token was consumed, so double completion is impossible.
/// ```
#[must_use = "service the interrupt and complete the claim"]
#[derive(Debug)]
pub struct Claim<'a> {
    plic: &'a mut Plic,
    id: usize,
}

impl<'a> Claim<'a> {
    fn new(plic: &'a mut Plic, id: usize) -> Self {
        Self { plic, id }
    }

    /// Return the claimed source ID.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// if let Some(claim) = plic.claim() {
    ///     let id = claim.id();
    ///     claim.complete();
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn id(&self) -> usize {
        self.id
    }

    /// Consume the claim and complete only that request.
    ///
    /// ```no_run
    /// use insper_riscv_plic::{Plic, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut plic = Plic::new()?;
    /// if let Some(claim) = plic.claim() {
    ///     claim.complete();
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn complete(self) {
        unsafe { sys::rv32_plic_complete(self.plic.inner, self.id) };
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
    fn validated_sources_and_claims_preserve_register_protocol() {
        extern crate std;
        let mut words = std::vec![0_u32; 0x200008 / 4];
        let mut plic = Plic {
            inner: unsafe { sys::rv32_plic_new(words.as_mut_ptr() as usize, 40, 3) },
            _single_thread: PhantomData,
        };
        assert!(matches!(plic.source(0), Err(Error::InvalidSource)));
        assert!(matches!(plic.source(41), Err(Error::InvalidSource)));
        assert!(matches!(plic.source(usize::MAX), Err(Error::InvalidSource)));
        assert_eq!(
            plic.source(1).unwrap().set_priority(8),
            Err(Error::InvalidPriority)
        );
        plic.source(40).unwrap().set_priority(7).unwrap();
        assert_eq!(words[40], 7);
        {
            let mut source = plic.source(32).unwrap();
            source.enable(true);
            assert_eq!(words[0x2004 / 4], 1);
            source.enable(false);
            assert_eq!(words[0x2004 / 4], 0);
            words[0x1004 / 4] = 1;
            assert!(source.pending());
        }
        plic.set_threshold(2).unwrap();
        assert_eq!(words[0x200000 / 4], 2);
        assert_eq!(plic.set_threshold(8), Err(Error::InvalidPriority));
        assert!(plic.claim().is_none());
        words[0x200004 / 4] = 40;
        let claim = plic.claim().unwrap();
        assert_eq!(claim.id(), 40);
        claim.complete();
        assert_eq!(words[0x200004 / 4], 40);
        assert_eq!(plic.source_count(), 40);
    }
}

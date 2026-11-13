//! Platform-selected FLASH. No heap, raw addresses or register offsets.
//! Handles are not Send/Sync. Serialize configuration, including interrupt handlers.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_flash_sys as sys;

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
pub struct Flash {
    inner: sys::rv32_flash_t,
    _single_thread: PhantomData<*mut ()>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Command {
    EraseSector,
    ProgramPage,
    ProtectSector,
    UnprotectSector,
}
impl Command {
    fn raw(self) -> sys::rv32_flash_command_t {
        match self {
            Self::EraseSector => sys::RV32_FLASH_ERASE_SECTOR,
            Self::ProgramPage => sys::RV32_FLASH_PROGRAM_PAGE,
            Self::ProtectSector => sys::RV32_FLASH_PROTECT_SECTOR,
            Self::UnprotectSector => sys::RV32_FLASH_UNPROTECT_SECTOR,
        }
    }
}

impl Flash {
    /// Construct using generated platform metadata; does not reset the hardware.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// let available = Flash::new();
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_flash_platform_new() };
        if !unsafe { sys::rv32_flash_valid(inner) } {
            return Err(Error::Unavailable);
        }
        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }
    /// Return the generated flash programming page size.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// let bytes = flash.page_bytes();
    /// # Ok(())
    /// # }
    /// ```
    pub fn page_bytes(&mut self) -> usize {
        self.inner.page_bytes
    }
    /// Check whether an operation is in progress.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// let busy = flash.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_flash_busy(self.inner) }
    }
    /// Check the hardware refused-operation flag.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// let refused = flash.refused();
    /// # Ok(())
    /// # }
    /// ```
    pub fn refused(&mut self) -> bool {
        unsafe { sys::rv32_flash_refused(self.inner) }
    }
    /// Fill a word in the page buffer. Fill every word before submitting a program command; busy writes are rejected.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// flash.buffer_word(0, u32::MAX)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn buffer_word(&mut self, word: usize, value: u32) -> Result<(), Error> {
        checked(unsafe { sys::rv32_flash_buffer_word(self.inner, word, value) })
    }
    /// Submit a flash command, not wait for completion. Offset is within flash, not MMIO. Erase/program must execute outside that flash.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// flash.submit(Command::ProgramPage, 0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn submit(&mut self, command: Command, byte_offset: u32) -> Result<(), Error> {
        checked(unsafe { sys::rv32_flash_submit(self.inner, command.raw(), byte_offset) })
    }
    /// Configure completion/refusal event generation.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// flash.configure_interrupts(true, true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn configure_interrupts(&mut self, done: bool, refused: bool) {
        unsafe { sys::rv32_flash_irq_configure(self.inner, done, refused) };
    }
    /// Acknowledge selected events using the flash W1C protocol.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// flash.acknowledge_interrupts(true, false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn acknowledge_interrupts(&mut self, done: bool, refused: bool) {
        unsafe { sys::rv32_flash_irq_acknowledge(self.inner, done, refused) };
    }
    /// Read pending events without clearing them.
    /// ```no_run
    /// use insper_riscv_flash::{Flash, Error, Command};
    /// # fn example() -> Result<(), Error> {
    /// let mut flash = Flash::new()?;
    /// let (done, refused) = flash.pending_interrupts();
    /// # Ok(())
    /// # }
    /// ```
    pub fn pending_interrupts(&mut self) -> (bool, bool) {
        let pending = unsafe { sys::rv32_flash_irq_pending(self.inner) };
        (pending & 1 != 0, pending & 2 != 0)
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
        assert!(matches!(Flash::new(), Err(Error::Unavailable)));
    }

    #[test]
    fn ffi_registers_boundaries_and_side_effect_contracts() {
        let mut words = [0_u32; 7];
        let mut flash = Flash {
            inner: unsafe { sys::rv32_flash_new(words.as_mut_ptr() as usize, 256) },
            _single_thread: PhantomData,
        };
        assert_eq!(flash.page_bytes(), 256);
        flash.buffer_word(63, 123).unwrap();
        assert_eq!(words[3], 63);
        assert_eq!(words[4], 123);
        assert_eq!(flash.buffer_word(64, 0), Err(Error::Rejected));
        words[2] = 1;
        assert!(flash.busy());
        assert_eq!(
            flash.submit(Command::ProgramPage, 256),
            Err(Error::Rejected)
        );
        assert_eq!(flash.buffer_word(0, 0), Err(Error::Rejected));
        words[2] = 4;
        assert!(flash.refused());
        flash.submit(Command::ProgramPage, 256).unwrap();
        assert_eq!(words[0], 3);
        assert_eq!(words[1], 256);
        flash.configure_interrupts(true, true);
        assert_eq!(words[5], 3);
        words[6] = 3;
        assert_eq!(flash.pending_interrupts(), (true, true));
        flash.acknowledge_interrupts(true, false);
        assert_eq!(words[6], 1);
    }
}

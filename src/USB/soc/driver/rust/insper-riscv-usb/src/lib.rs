//! Platform-selected USB; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_usb_sys as sys;

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
pub struct Usb {
    inner: sys::rv32_usb_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Usb {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _device = Usb::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _device = Usb::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_usb_instance_new(index) };

        if !unsafe { sys::rv32_usb_valid(inner) } {
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
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _count = Usb::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_usb_instance_count() }
    }

    /// Read the current USB bridge state without consuming chip data.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _state = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_usb_bridge_status(self.inner) & 8 != 0 }
    }

    /// Read the current USB bridge state without consuming chip data.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _state = device.has_error();
    /// # Ok(())
    /// # }
    /// ```
    pub fn has_error(&mut self) -> bool {
        unsafe { sys::rv32_usb_bridge_status(self.inner) & 16 != 0 }
    }

    /// Read the current USB bridge state without consuming chip data.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _state = device.interrupt0();
    /// # Ok(())
    /// # }
    /// ```
    pub fn interrupt0(&mut self) -> bool {
        unsafe { sys::rv32_usb_bridge_status(self.inner) & 1 != 0 }
    }

    /// Read the current USB bridge state without consuming chip data.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _state = device.interrupt1();
    /// # Ok(())
    /// # }
    /// ```
    pub fn interrupt1(&mut self) -> bool {
        unsafe { sys::rv32_usb_bridge_status(self.inner) & 2 != 0 }
    }

    /// Read the current USB bridge state without consuming chip data.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// let _state = device.dma_requested();
    /// # Ok(())
    /// # }
    /// ```
    pub fn dma_requested(&mut self) -> bool {
        unsafe { sys::rv32_usb_bridge_status(self.inner) & 4 != 0 }
    }

    /// Clear only the bridge error bit with a W1C write.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// device.clear_error();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_error(&mut self) {
        unsafe { sys::rv32_usb_bridge_clear_error(self.inner) };
    }

    /// Hold or release chip reset; no startup delay is guessed.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// device.hold_reset(true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn hold_reset(&mut self, held: bool) {
        unsafe { sys::rv32_usb_chip_hold_reset(self.inner, held) };
    }

    /// Limit status reads per HPI wait; this is not a duration in microseconds.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// device.set_poll_budget(core::num::NonZeroUsize::new(4096).unwrap());
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_poll_budget(&mut self, polls: core::num::NonZeroUsize) {
        self.inner.poll_budget = polls.get();
    }

    /// Enable either of the two bridge interrupt inputs using booleans.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// device.interrupt_mask(false, false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn interrupt_mask(&mut self, interrupt0: bool, interrupt1: bool) {
        let mask = u8::from(interrupt0) | (u8::from(interrupt1) << 1);

        unsafe { sys::rv32_usb_irq_mask(self.inner, mask) };
    }

    /// Set setup/pulse/recovery fields in FPGA cycles; obtain values from the chip timing requirements.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// device.set_timing(1, 2, 1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_timing(&mut self, setup: u8, pulse: u8, recovery: u8) {
        unsafe { sys::rv32_usb_set_timing(self.inner, setup, pulse, recovery) };
    }

    /// Read a typed HPI port with bounded busy polling.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// use insper_riscv_usb::Port;
    /// let _result = device.port_read(Port::Status);
    /// # Ok(())
    /// # }
    /// ```
    pub fn port_read(&mut self, port: Port) -> Result<u16, Error> {
        let mut value = 0;

        completed(unsafe { sys::rv32_usb_port_read(self.inner, port.raw(), &mut value) })?;

        Ok(value)
    }

    /// Write a typed HPI port with bounded busy polling.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// use insper_riscv_usb::Port;
    /// let _result = device.port_write(Port::Address, 0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn port_write(&mut self, port: Port, value: u16) -> Result<(), Error> {
        completed(unsafe { sys::rv32_usb_port_write(self.inner, port.raw(), value) })
    }

    /// Access chip words by numbered index; check the whole range before any transfer.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// use insper_riscv_usb::{ChipWord, Port};
    /// let mut words = [0; 4];
    /// let _result = device.read_words(ChipWord::new(0)?, &mut words);
    /// # Ok(())
    /// # }
    /// ```
    pub fn read_words(&mut self, first: ChipWord, words: &mut [u16]) -> Result<(), Error> {
        if words.len() > 32768 - first.0 as usize {
            return Err(Error::OutOfRange);
        }

        if words.is_empty() {
            return Ok(());
        }

        completed(unsafe {
            sys::rv32_usb_hpi_read_words(self.inner, first.0 * 2, words.as_mut_ptr(), words.len())
        })
    }

    /// Access chip words by numbered index; check the whole range before any transfer.
    ///
    /// ```no_run
    /// use insper_riscv_usb::{Usb, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Usb::new()?;
    /// use insper_riscv_usb::{ChipWord, Port};
    /// let words = [0; 4];
    /// let _result = device.write_words(ChipWord::new(0)?, &words);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write_words(&mut self, first: ChipWord, words: &[u16]) -> Result<(), Error> {
        if words.len() > 32768 - first.0 as usize {
            return Err(Error::OutOfRange);
        }

        if words.is_empty() {
            return Ok(());
        }

        completed(unsafe {
            sys::rv32_usb_hpi_write_words(self.inner, first.0 * 2, words.as_ptr(), words.len())
        })
    }
}

/// The four physical HPI ports, not SoC register offsets.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Port {
    Data,
    Mailbox,
    Address,
    Status,
}

impl Port {
    fn raw(self) -> sys::rv32_usb_port_t {
        match self {
            Self::Data => sys::RV32_USB_PORT_DATA,
            Self::Mailbox => sys::RV32_USB_PORT_MAILBOX,
            Self::Address => sys::RV32_USB_PORT_ADDRESS,
            Self::Status => sys::RV32_USB_PORT_STATUS,
        }
    }
}

/// A logical 16-bit chip-memory word, hiding the byte-address conversion.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ChipWord(u16);

impl ChipWord {
    /// Validate a word number; an odd byte address cannot be represented.
    /// ```
    /// use insper_riscv_usb::ChipWord;
    /// assert!(ChipWord::new(32767).is_ok());
    /// assert!(ChipWord::new(32768).is_err());
    /// ```
    pub const fn new(index: usize) -> Result<Self, Error> {
        if index < 32768 {
            Ok(Self(index as u16))
        } else {
            Err(Error::OutOfRange)
        }
    }
}

fn completed(result: sys::rv32_usb_err_t) -> Result<(), Error> {
    match result {
        sys::RV32_USB_OK => Ok(()),
        sys::RV32_USB_E_BUSY_TIMEOUT | sys::RV32_USB_E_MAILBOX_TIMEOUT => Err(Error::Timeout),
        _ => Err(Error::Hardware),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Usb::instance_count();

        if count == 0 {
            assert!(matches!(Usb::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Usb::instance(count), Err(Error::Unavailable)));
        assert!(matches!(Usb::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

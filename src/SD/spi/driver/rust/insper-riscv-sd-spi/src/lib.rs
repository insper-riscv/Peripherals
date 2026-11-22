//! Platform-selected SD_SPI; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_sd_spi_sys as sys;

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
pub struct SdSpi {
    inner: sys::rv32_sd_spi_t,
    _single_thread: PhantomData<*mut ()>,
}

impl SdSpi {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _device = SdSpi::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _device = SdSpi::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_sd_spi_new(index) };

        if !unsafe { sys::rv32_sd_spi_valid(inner) } {
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
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _count = SdSpi::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_sd_spi_instance_count() }
    }

    /// Whether queued or active transfers are still pending.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _state = device.busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn busy(&mut self) -> bool {
        unsafe { sys::rv32_sd_spi_busy(self.inner) }
    }

    /// Whether the transmit queue accepts another word.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _state = device.tx_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn tx_ready(&mut self) -> bool {
        unsafe { sys::rv32_sd_spi_tx_ready(self.inner) }
    }

    /// Whether the receive queue contains data.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _state = device.rx_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn rx_ready(&mut self) -> bool {
        unsafe { sys::rv32_sd_spi_rx_ready(self.inner) }
    }

    /// Receive queue occupancy.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _value = device.receive_level();
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_level(&mut self) -> u8 {
        unsafe { sys::rv32_sd_spi_receive_level(self.inner) }
    }

    /// Transmit queue occupancy.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _value = device.transmit_level();
    /// # Ok(())
    /// # }
    /// ```
    pub fn transmit_level(&mut self) -> u8 {
        unsafe { sys::rv32_sd_spi_transmit_level(self.inner) }
    }

    /// Pop one received word, or return no data.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// if let Some(value) = device.try_read() {
    ///     let _ = value;
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_read(&mut self) -> Option<u8> {
        let mut value = 0;

        if unsafe { sys::rv32_sd_spi_try_read(self.inner, &mut value) } {
            Some(value)
        } else {
            None
        }
    }

    /// Queue one word without waiting.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _result = device.try_write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_write(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_sd_spi_try_write(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Clear only DONE, RX_OVERRUN and TX_DROPPED (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_sd_spi_clear_events(self.inner) };
    }

    /// Set the hardware half-clock divider.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// device.set_divider(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_divider(&mut self, value: u16) {
        unsafe { sys::rv32_sd_spi_set_divider(self.inner, value) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// device.receive_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_spi_receive_interrupt(self.inner, enabled) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// device.empty_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn empty_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_spi_empty_interrupt(self.inner, enabled) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// device.done_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn done_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_spi_done_interrupt(self.inner, enabled) };
    }

    /// Enable this interrupt source; CPU interrupt routing is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_spi_error_interrupt(self.inner, enabled) };
    }

    /// Assert the SD chip-select line; wait for idle before changing it.
    ///
    /// ```no_run
    /// use insper_riscv_sd_spi::{SdSpi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = SdSpi::new()?;
    /// let _result = device.select(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn select(&mut self, enabled: bool) -> Result<(), Error> {
        if unsafe { sys::rv32_sd_spi_select(self.inner, enabled) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = SdSpi::instance_count();

        if count == 0 {
            assert!(matches!(SdSpi::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(SdSpi::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            SdSpi::instance(usize::MAX),
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
        let mut inner = unsafe { sys::rv32_sd_spi_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_sd_spi_valid(inner) });
        let mut device = SdSpi {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.busy());
        unsafe { registers.as_mut_ptr().add(2).write_volatile(u32::MAX) };
        assert!(device.busy());
        unsafe { registers.as_mut_ptr().add(2).write_volatile(0) };
        assert!(!device.busy());
    }
}

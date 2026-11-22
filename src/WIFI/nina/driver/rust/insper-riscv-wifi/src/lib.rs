//! Platform-selected WIFI; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_wifi_sys as sys;

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
pub struct Wifi {
    inner: sys::rv32_wifi_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Wifi {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _device = Wifi::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _device = Wifi::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_wifi_new(index) };

        if !unsafe { sys::rv32_wifi_valid(inner) } {
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
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _count = Wifi::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_wifi_instance_count() }
    }

    /// Release or hold module reset; firmware startup is asynchronous.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.run(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn run(&mut self, enabled: bool) {
        unsafe { sys::rv32_wifi_run(self.inner, enabled) };
    }

    /// Drive GPIO0 low for the external firmware bootloader.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.bootloader_mode(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn bootloader_mode(&mut self, enabled: bool) {
        unsafe { sys::rv32_wifi_bootloader_mode(self.inner, enabled) };
    }

    /// Enable rising ACK edge interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.rise_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn rise_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_wifi_rise_interrupt(self.inner, enabled) };
    }

    /// Enable falling ACK edge interrupts.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.fall_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn fall_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_wifi_fall_interrupt(self.inner, enabled) };
    }

    /// Read the synchronized module ACK line.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _state = device.acknowledge();
    /// # Ok(())
    /// # }
    /// ```
    pub fn acknowledge(&mut self) -> bool {
        unsafe { sys::rv32_wifi_acknowledge(self.inner) }
    }

    /// Whether a timed module reset pulse is active.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _state = device.resetting();
    /// # Ok(())
    /// # }
    /// ```
    pub fn resetting(&mut self) -> bool {
        unsafe { sys::rv32_wifi_resetting(self.inner) }
    }

    /// Clear ACK rising/falling edge flags with W1C writes.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_wifi_clear_events(self.inner) };
    }

    /// Request the hardware-timed reset pulse; no software delay is invented.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.reset_pulse();
    /// # Ok(())
    /// # }
    /// ```
    pub fn reset_pulse(&mut self) {
        unsafe { sys::rv32_wifi_reset_pulse(self.inner) };
    }

    /// Whether the SPI transport still has pending work.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _state = device.spi_busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn spi_busy(&mut self) -> bool {
        unsafe { sys::rv32_wifi_spi_busy(self.inner) }
    }

    /// Pop one SPI transport byte.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// if let Some(value) = device.spi_try_read() {
    ///     let _ = value;
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn spi_try_read(&mut self) -> Option<u8> {
        let mut value = 0;

        if unsafe { sys::rv32_wifi_spi_try_read(self.inner, &mut value) } {
            Some(value)
        } else {
            None
        }
    }

    /// Queue one SPI transport byte.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _result = device.spi_try_write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn spi_try_write(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_wifi_spi_try_write(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Set the SPI half-clock divider.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.spi_set_divider(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn spi_set_divider(&mut self, value: u16) {
        unsafe { sys::rv32_wifi_spi_set_divider(self.inner, value) };
    }

    /// Change chip select only while the SPI transport is idle.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _result = device.spi_select(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn spi_select(&mut self, selected: bool) -> Result<(), Error> {
        if unsafe { sys::rv32_wifi_spi_select(self.inner, selected) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Pop one UART transport byte.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// if let Some(value) = device.uart_try_read() {
    ///     let _ = value;
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn uart_try_read(&mut self) -> Option<u8> {
        let mut value = 0;

        if unsafe { sys::rv32_wifi_uart_try_read(self.inner, &mut value) } {
            Some(value)
        } else {
            None
        }
    }

    /// Queue one UART transport byte.
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// let _result = device.uart_try_write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn uart_try_write(&mut self, value: u8) -> Result<(), Error> {
        if unsafe { sys::rv32_wifi_uart_try_write(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Clear the SPI transport sticky events (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.spi_clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn spi_clear_events(&mut self) {
        unsafe { sys::rv32_wifi_spi_clear_events(self.inner) };
    }

    /// Clear UART receive-overflow and transmit-drop flags (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_wifi::{Wifi, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Wifi::new()?;
    /// device.uart_clear_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn uart_clear_errors(&mut self) {
        unsafe { sys::rv32_wifi_uart_clear_errors(self.inner) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Wifi::instance_count();

        if count == 0 {
            assert!(matches!(Wifi::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Wifi::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            Wifi::instance(usize::MAX),
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
        let mut inner = unsafe { sys::rv32_wifi_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_wifi_valid(inner) });
        let mut device = Wifi {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.acknowledge());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(u32::MAX) };
        assert!(device.acknowledge());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(0) };
        assert!(!device.acknowledge());
    }
}

//! Platform-selected UART. No heap, raw addresses or register offsets.
//! Handles are not Send/Sync. Serialize configuration, including interrupt handlers.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_uart_sys as sys;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    Unavailable,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Unavailable => "Peripheral unavailable on this platform/profile.",
        })
    }
}
impl core::error::Error for Error {}

#[derive(Debug)]
pub struct Uart {
    inner: sys::rv32_uart_t,
    _single_thread: PhantomData<*mut ()>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Instance {
    Default,
    Serial,
    Jtag,
}

impl Uart {
    /// Construct using generated platform metadata; does not reset the hardware.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// let available = Uart::new();
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_uart_platform_new(sys::RV32_UART_DEFAULT_INSTANCE) };
        if !unsafe { sys::rv32_uart_valid(inner) } {
            return Err(Error::Unavailable);
        }
        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }
    /// Select the serial or JTAG UART without specifying a backend or address.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// let serial = Uart::new_for(Instance::Serial)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new_for(instance: Instance) -> Result<Self, Error> {
        let instance = match instance {
            Instance::Default => sys::RV32_UART_DEFAULT_INSTANCE,
            Instance::Serial => sys::RV32_UART_SERIAL_INSTANCE,
            Instance::Jtag => sys::RV32_UART_JTAG_INSTANCE,
        };
        let inner = unsafe { sys::rv32_uart_platform_new(instance) };
        if !unsafe { sys::rv32_uart_valid(inner) } {
            return Err(Error::Unavailable);
        }
        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }
    /// Try one byte without waiting. False means the TX queue was not ready.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// let sent = uart.try_write(b'A');
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_write(&mut self, byte: u8) -> bool {
        unsafe { sys::rv32_uart_try_write(self.inner, byte) }
    }
    /// Try reading one byte. None means no input is available.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// let byte = uart.try_read();
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_read(&mut self) -> Option<u8> {
        let mut byte = 0;
        if unsafe { sys::rv32_uart_try_read(self.inner, &mut byte) } {
            Some(byte)
        } else {
            None
        }
    }
    /// Write with a total status-poll budget, returning the number sent. Budget is not time.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// let sent = uart.write(b"hello", 1000);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write(&mut self, bytes: &[u8], poll_budget: usize) -> usize {
        unsafe { sys::rv32_uart_write(self.inner, bytes.as_ptr(), bytes.len(), poll_budget) }
    }
    /// Serial waits for the stop bit; JTAG reports an empty host queue. Status reads acknowledge JTAG TX drops.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// let idle = uart.tx_idle();
    /// # Ok(())
    /// # }
    /// ```
    pub fn tx_idle(&mut self) -> bool {
        unsafe { sys::rv32_uart_tx_idle(self.inner) }
    }
    /// Configure event sources; enable the CPU interrupt route separately.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// uart.configure_interrupts(true, false, true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn configure_interrupts(&mut self, receive: bool, transmit_empty: bool, errors: bool) {
        unsafe { sys::rv32_uart_irq_configure(self.inner, receive, transmit_empty, errors) };
    }
    /// Acknowledge sticky errors (serial W1C; JTAG status read).
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// uart.clear_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_errors(&mut self) {
        unsafe { sys::rv32_uart_clear_errors(self.inner) };
    }
    /// Read status once. JTAG status reads acknowledge dropped TX events.
    /// ```no_run
    /// use insper_riscv_uart::{Uart, Error, Instance};
    /// # fn example() -> Result<(), Error> {
    /// let mut uart = Uart::new()?;
    /// let status = uart.status();
    /// let ready = status.transmit_ready;
    /// # Ok(())
    /// # }
    /// ```
    pub fn status(&mut self) -> Status {
        let bits = unsafe { sys::rv32_uart_status_read(self.inner) };
        Status::new(bits, self.inner.backend)
    }
}

/// Decoded UART status; JTAG status reads acknowledge transmit drops.
#[derive(Clone, Copy, Debug)]
pub struct Status {
    pub transmit_ready: bool,
    pub receive_ready: bool,
    pub transmit_dropped: bool,
    pub host_attached: Option<bool>,
    pub receive_overrun: bool,
}

impl Status {
    fn new(bits: u32, backend: sys::rv32_uart_backend_t) -> Self {
        if backend == sys::RV32_UART_JTAG {
            Self {
                transmit_ready: bits & 0xff != 0,
                receive_ready: bits & 0xff00 != 0,
                transmit_dropped: bits & (1 << 16) != 0,
                host_attached: Some(bits & (1 << 17) != 0),
                receive_overrun: false,
            }
        } else {
            Self {
                transmit_ready: bits & 2 != 0,
                receive_ready: bits & 1 != 0,
                transmit_dropped: bits & 8 != 0,
                host_attached: None,
                receive_overrun: bits & 4 != 0,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unconfigured_factory_is_safe() {
        assert!(matches!(Uart::new(), Err(Error::Unavailable)));
    }

    #[test]
    fn ffi_registers_boundaries_and_side_effect_contracts() {
        let mut words = [0_u32; 4];
        let mut uart = Uart {
            inner: unsafe {
                sys::rv32_uart_new(words.as_mut_ptr() as usize, sys::RV32_UART_SERIAL, 4)
            },
            _single_thread: PhantomData,
        };
        assert!(!uart.try_write(b'A'));
        assert_eq!(uart.write(b"hello", 2), 0);
        words[2] = 2 | 1 | 4 | 8 | 0x40;
        assert!(uart.try_write(b'A'));
        assert_eq!(words[0], 65);
        words[1] = 90;
        assert_eq!(uart.try_read(), Some(90));
        assert!(uart.tx_idle());
        let status = uart.status();
        assert!(status.receive_overrun);
        assert!(status.transmit_dropped);
        assert_eq!(status.host_attached, None);
        uart.clear_errors();
        assert_eq!(words[2], 12);
        uart.configure_interrupts(true, false, true);
        assert_eq!(words[3], 5);
        uart.inner.backend = sys::RV32_UART_JTAG;
        words[2] = 4 | (2 << 8) | (1 << 16) | (1 << 17);
        let status = uart.status();
        assert!(status.transmit_ready);
        assert!(status.receive_ready);
        assert!(status.transmit_dropped);
        assert_eq!(status.host_attached, Some(true));
        words[1] = 0x100 | 66;
        assert_eq!(uart.try_read(), Some(66));
        words[1] = 0;
        assert_eq!(uart.try_read(), None);
        words[2] = 4;
        assert_eq!(uart.write(b"ab", 2), 2);
        assert_eq!(words[0], 98);
        assert!(uart.tx_idle());
    }
}

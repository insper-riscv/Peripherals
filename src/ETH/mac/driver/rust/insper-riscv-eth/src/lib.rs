//! Platform-selected ETH; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_eth_sys as sys;

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
pub struct Ethernet {
    inner: sys::rv32_eth_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Ethernet {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _device = Ethernet::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _device = Ethernet::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_eth_new(index) };

        if !unsafe { sys::rv32_eth_valid(inner) } {
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
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _count = Ethernet::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_eth_instance_count() }
    }

    /// Control this MAC option while serializing configuration changes.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.enable_receive(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable_receive(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_enable_receive(self.inner, enabled) };
    }

    /// Control this MAC option while serializing configuration changes.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.promiscuous(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn promiscuous(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_promiscuous(self.inner, enabled) };
    }

    /// Control this MAC option while serializing configuration changes.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.broadcast(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn broadcast(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_broadcast(self.inner, enabled) };
    }

    /// Control this MAC option while serializing configuration changes.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.multicast(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn multicast(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_multicast(self.inner, enabled) };
    }

    /// Control this MAC option while serializing configuration changes.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.accept_errors(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn accept_errors(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_accept_errors(self.inner, enabled) };
    }

    /// Control this MAC option while serializing configuration changes.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.hold_phy_reset(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn hold_phy_reset(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_hold_phy_reset(self.inner, enabled) };
    }

    /// Request a MAC reset; hardware clears registers and queues.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.reset();
    /// # Ok(())
    /// # }
    /// ```
    pub fn reset(&mut self) {
        unsafe { sys::rv32_eth_reset(self.inner) };
    }

    /// Read the current hardware state without clearing events.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _state = device.tx_busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn tx_busy(&mut self) -> bool {
        unsafe { sys::rv32_eth_tx_busy(self.inner) }
    }

    /// Read the current hardware state without clearing events.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _state = device.rx_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn rx_ready(&mut self) -> bool {
        unsafe { sys::rv32_eth_rx_ready(self.inner) }
    }

    /// Read the current hardware state without clearing events.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _state = device.mdio_busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn mdio_busy(&mut self) -> bool {
        unsafe { sys::rv32_eth_mdio_busy(self.inner) }
    }

    /// Read the current hardware state without clearing events.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _state = device.phy_interrupt();
    /// # Ok(())
    /// # }
    /// ```
    pub fn phy_interrupt(&mut self) -> bool {
        unsafe { sys::rv32_eth_phy_interrupt(self.inner) }
    }

    /// Read the current hardware state without clearing events.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _state = device.mdio_no_ack();
    /// # Ok(())
    /// # }
    /// ```
    pub fn mdio_no_ack(&mut self) -> bool {
        unsafe { sys::rv32_eth_mdio_no_ack(self.inner) }
    }

    /// Acknowledge RX/TX/error/MDIO events; PHY level is not W1C.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_eth_clear_events(self.inner) };
    }

    /// Enable this Ethernet interrupt source.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.receive_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_receive_interrupt(self.inner, enabled) };
    }

    /// Enable this Ethernet interrupt source.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.transmit_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn transmit_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_transmit_interrupt(self.inner, enabled) };
    }

    /// Enable this Ethernet interrupt source.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_error_interrupt(self.inner, enabled) };
    }

    /// Enable this Ethernet interrupt source.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.mdio_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn mdio_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_mdio_interrupt(self.inner, enabled) };
    }

    /// Enable this Ethernet interrupt source.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.phy_irq_enable(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn phy_irq_enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_eth_phy_irq_enable(self.inner, enabled) };
    }

    /// Read this hardware frame counter without clearing it.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.transmitted_frames();
    /// # Ok(())
    /// # }
    /// ```
    pub fn transmitted_frames(&mut self) -> u32 {
        unsafe { sys::rv32_eth_transmitted_frames(self.inner) }
    }

    /// Read this hardware frame counter without clearing it.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.received_frames();
    /// # Ok(())
    /// # }
    /// ```
    pub fn received_frames(&mut self) -> u32 {
        unsafe { sys::rv32_eth_received_frames(self.inner) }
    }

    /// Read this hardware frame counter without clearing it.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.crc_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn crc_errors(&mut self) -> u32 {
        unsafe { sys::rv32_eth_crc_errors(self.inner) }
    }

    /// Read this hardware frame counter without clearing it.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.phy_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn phy_errors(&mut self) -> u32 {
        unsafe { sys::rv32_eth_phy_errors(self.inner) }
    }

    /// Read this hardware frame counter without clearing it.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.dropped_frames();
    /// # Ok(())
    /// # }
    /// ```
    pub fn dropped_frames(&mut self) -> u32 {
        unsafe { sys::rv32_eth_dropped_frames(self.inner) }
    }

    /// Read this hardware frame counter without clearing it.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.filtered_frames();
    /// # Ok(())
    /// # }
    /// ```
    pub fn filtered_frames(&mut self) -> u32 {
        unsafe { sys::rv32_eth_filtered_frames(self.inner) }
    }

    /// Length of the ready frame, excluding FCS.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.receive_length();
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_length(&mut self) -> u32 {
        unsafe { sys::rv32_eth_receive_length(self.inner) }
    }

    /// Result of the last completed MDIO read.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _value = device.mdio_data();
    /// # Ok(())
    /// # }
    /// ```
    pub fn mdio_data(&mut self) -> u16 {
        unsafe { sys::rv32_eth_mdio_data(self.inner) }
    }

    /// Set the six octets in wire order, without host-endian casts.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// device.set_mac([2, 0, 0, 0, 0, 1]);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_mac(&mut self, address: [u8; 6]) {
        unsafe { sys::rv32_eth_set_mac(self.inner, address.as_ptr()) };
    }

    /// Queue one frame; hardware supplies padding/FCS and does not wait for completion.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let _result = device.send(&[0xFF; 60]);
    /// # Ok(())
    /// # }
    /// ```
    pub fn send(&mut self, frame: &[u8]) -> Result<(), Error> {
        if frame.is_empty() || frame.len() > self.inner.tx_words as usize * 4 {
            return Err(Error::OutOfRange);
        }

        if unsafe { sys::rv32_eth_send(self.inner, frame.as_ptr(), frame.len()) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Copy and release a ready frame; a short destination leaves it pending.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let mut frame = [0; 1536];
    /// let _received = device.receive(&mut frame)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive(&mut self, frame: &mut [u8]) -> Result<Option<usize>, Error> {
        if !self.rx_ready() {
            return Ok(None);
        }

        let required = self.receive_length() as usize;

        if required > frame.len() || required > self.inner.rx_words as usize * 4 {
            return Err(Error::OutOfRange);
        }

        let mut length = 0;

        if unsafe {
            sys::rv32_eth_receive(self.inner, frame.as_mut_ptr(), frame.len(), &mut length)
        } {
            Ok(Some(length))
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Start one Clause-22 MDIO transaction without polling indefinitely.
    ///
    /// ```no_run
    /// use insper_riscv_eth::{Ethernet, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Ethernet::new()?;
    /// let phy = insper_riscv_eth::PhyAddress::new(16)?;
    /// let register = insper_riscv_eth::PhyRegister::new(1)?;
    /// let _result = device.mdio_start(phy, register, None);
    /// # Ok(())
    /// # }
    /// ```
    pub fn mdio_start(
        &mut self,
        phy: PhyAddress,
        register: PhyRegister,
        write: Option<u16>,
    ) -> Result<(), Error> {
        if unsafe {
            sys::rv32_eth_mdio_start(
                self.inner,
                phy.value(),
                register.value(),
                write.is_some(),
                write.unwrap_or(0),
            )
        } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_eth::PhyAddress(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PhyAddress(u8);

impl PhyAddress {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_eth::PhyAddress::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn new(value: u8) -> Result<Self, Error> {
        if value <= 31 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_eth::PhyAddress::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn value(self) -> u8 {
        self.0
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_eth::PhyRegister(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PhyRegister(u8);

impl PhyRegister {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_eth::PhyRegister::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn new(value: u8) -> Result<Self, Error> {
        if value <= 31 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_eth::PhyRegister::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn value(self) -> u8 {
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Ethernet::instance_count();

        if count == 0 {
            assert!(matches!(Ethernet::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Ethernet::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            Ethernet::instance(usize::MAX),
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
        let mut inner = unsafe { sys::rv32_eth_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;
        inner.tx_words = 512;
        inner.rx_words = 512;
        assert!(unsafe { sys::rv32_eth_valid(inner) });
        let mut device = Ethernet {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.tx_busy());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(u32::MAX) };
        assert!(device.tx_busy());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(0) };
        assert!(!device.tx_busy());
    }
}

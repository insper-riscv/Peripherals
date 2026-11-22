//! Platform-selected SD; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_sd_sys as sys;

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
pub struct Sd {
    inner: sys::rv32_sd_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Sd {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _device = Sd::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _device = Sd::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_sd_new(index) };

        if !unsafe { sys::rv32_sd_valid(inner) } {
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
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _count = Sd::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_sd_instance_count() }
    }

    /// Read the current command/data engine state.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _state = device.command_busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn command_busy(&mut self) -> bool {
        unsafe { sys::rv32_sd_command_busy(self.inner) }
    }

    /// Read the current command/data engine state.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _state = device.data_busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn data_busy(&mut self) -> bool {
        unsafe { sys::rv32_sd_data_busy(self.inner) }
    }

    /// Read the current command/data engine state.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _state = device.command_done();
    /// # Ok(())
    /// # }
    /// ```
    pub fn command_done(&mut self) -> bool {
        unsafe { sys::rv32_sd_command_done(self.inner) }
    }

    /// Read the current command/data engine state.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _state = device.data_done();
    /// # Ok(())
    /// # }
    /// ```
    pub fn data_done(&mut self) -> bool {
        unsafe { sys::rv32_sd_data_done(self.inner) }
    }

    /// Read the current command/data engine state.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _state = device.card_busy();
    /// # Ok(())
    /// # }
    /// ```
    pub fn card_busy(&mut self) -> bool {
        unsafe { sys::rv32_sd_card_busy(self.inner) }
    }

    /// Read sticky command and data error flags.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _value = device.errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn errors(&mut self) -> u32 {
        unsafe { sys::rv32_sd_errors(self.inner) }
    }

    /// Clear only CMD_DONE and DATA_DONE flags (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.clear_events();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_events(&mut self) {
        unsafe { sys::rv32_sd_clear_events(self.inner) };
    }

    /// Clear only defined command/data error flags (W1C).
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.clear_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_errors(&mut self) {
        unsafe { sys::rv32_sd_clear_errors(self.inner) };
    }

    /// Configure this SD controller option; card negotiation is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.clock_enable(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn clock_enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_clock_enable(self.inner, enabled) };
    }

    /// Configure this SD controller option; card negotiation is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.wide_bus(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn wide_bus(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_wide_bus(self.inner, enabled) };
    }

    /// Configure this SD controller option; card negotiation is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.command_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn command_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_command_interrupt(self.inner, enabled) };
    }

    /// Configure this SD controller option; card negotiation is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.data_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn data_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_data_interrupt(self.inner, enabled) };
    }

    /// Configure this SD controller option; card negotiation is separate.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_sd_error_interrupt(self.inner, enabled) };
    }

    /// Abort the command/data engine and release the lines.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.abort();
    /// # Ok(())
    /// # }
    /// ```
    pub fn abort(&mut self) {
        unsafe { sys::rv32_sd_abort(self.inner) };
    }

    /// Set the SD clock divider for the current negotiation stage.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.set_divider(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_divider(&mut self, value: u16) {
        unsafe { sys::rv32_sd_set_divider(self.inner, value) };
    }

    /// Set a validated hardware wait limit in SD clocks.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// device.set_timeout(insper_riscv_sd::TimeoutCycles::new(100_000)?);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_timeout(&mut self, clocks: TimeoutCycles) {
        unsafe { sys::rv32_sd_set_timeout(self.inner, clocks.value()) };
    }

    /// Submit one typed command; no filesystem/card-protocol assumptions are hidden.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// use insper_riscv_sd::{CommandIndex, Response, DataDirection};
    /// let _result = device.command(CommandIndex::new(8)?, 0x1AA, Response::ShortChecked, false, DataDirection::None);
    /// # Ok(())
    /// # }
    /// ```
    pub fn command(
        &mut self,
        index: CommandIndex,
        argument: u32,
        response: Response,
        wait_busy: bool,
        data: DataDirection,
    ) -> Result<(), Error> {
        let response = match response {
            Response::None => 0,
            Response::ShortChecked => 1,
            Response::ShortUnchecked => 2,
            Response::Long => 3,
        };
        let data = match data {
            DataDirection::None => 0,
            DataDirection::Read => 1,
            DataDirection::Write => 2,
        };

        if unsafe {
            sys::rv32_sd_command(
                self.inner,
                index.value(),
                argument,
                response,
                wait_busy,
                data,
            )
        } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Read this word of the last response.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _value = device.response0();
    /// # Ok(())
    /// # }
    /// ```
    pub fn response0(&mut self) -> u32 {
        unsafe { sys::rv32_sd_response0(self.inner) }
    }

    /// Read this word of the last response.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _value = device.response1();
    /// # Ok(())
    /// # }
    /// ```
    pub fn response1(&mut self) -> u32 {
        unsafe { sys::rv32_sd_response1(self.inner) }
    }

    /// Read this word of the last response.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _value = device.response2();
    /// # Ok(())
    /// # }
    /// ```
    pub fn response2(&mut self) -> u32 {
        unsafe { sys::rv32_sd_response2(self.inner) }
    }

    /// Read this word of the last response.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let _value = device.response3();
    /// # Ok(())
    /// # }
    /// ```
    pub fn response3(&mut self) -> u32 {
        unsafe { sys::rv32_sd_response3(self.inner) }
    }

    /// Access a bounded range of the 128-word block buffer while the engine is idle.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let mut words = [0; 4];
    /// let _result = device.read_buffer(0, &mut words);
    /// # Ok(())
    /// # }
    /// ```
    pub fn read_buffer(&mut self, first: usize, words: &mut [u32]) -> Result<(), Error> {
        if first > 128 || words.len() > 128 - first {
            return Err(Error::OutOfRange);
        }

        if unsafe { sys::rv32_sd_read_buffer(self.inner, first, words.as_mut_ptr(), words.len()) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Access a bounded range of the 128-word block buffer while the engine is idle.
    ///
    /// ```no_run
    /// use insper_riscv_sd::{Sd, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Sd::new()?;
    /// let words = [0; 4];
    /// let _result = device.write_buffer(0, &words);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write_buffer(&mut self, first: usize, words: &[u32]) -> Result<(), Error> {
        if first > 128 || words.len() > 128 - first {
            return Err(Error::OutOfRange);
        }

        if unsafe { sys::rv32_sd_write_buffer(self.inner, first, words.as_ptr(), words.len()) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_sd::CommandIndex(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CommandIndex(u8);

impl CommandIndex {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_sd::CommandIndex::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn new(value: u8) -> Result<Self, Error> {
        if value <= 63 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_sd::CommandIndex::new(0).unwrap();
    /// assert_eq!(value.value(), 0);
    /// ```
    pub const fn value(self) -> u8 {
        self.0
    }
}

/// A value validated once before configuring hardware.
/// ```compile_fail
/// let _ = insper_riscv_sd::TimeoutCycles(0);
/// ```
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TimeoutCycles(u32);

impl TimeoutCycles {
    /// Validate the supported inclusive range.
    /// ```
    /// let value = insper_riscv_sd::TimeoutCycles::new(1).unwrap();
    /// assert_eq!(value.value(), 1);
    /// ```
    pub const fn new(value: u32) -> Result<Self, Error> {
        if value >= 1 && value <= 16777215 {
            Ok(Self(value))
        } else {
            Err(Error::OutOfRange)
        }
    }

    /// Return the validated numeric value.
    /// ```
    /// let value = insper_riscv_sd::TimeoutCycles::new(1).unwrap();
    /// assert_eq!(value.value(), 1);
    /// ```
    pub const fn value(self) -> u32 {
        self.0
    }
}

/// Response format accepted by the SD command engine.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Response {
    None,
    ShortChecked,
    ShortUnchecked,
    Long,
}

/// Optional 512-byte data stage direction.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DataDirection {
    None,
    Read,
    Write,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Sd::instance_count();

        if count == 0 {
            assert!(matches!(Sd::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Sd::instance(count), Err(Error::Unavailable)));
        assert!(matches!(Sd::instance(usize::MAX), Err(Error::Unavailable)));
    }
}

#[cfg(test)]
mod register_contract {
    use super::*;

    #[test]
    fn valid_handle_reads_the_bound_hardware_register() {
        let mut registers = [0u32; 64];
        let mut inner = unsafe { sys::rv32_sd_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_sd_valid(inner) });
        let mut device = Sd {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.command_busy());
        unsafe { registers.as_mut_ptr().add(6).write_volatile(u32::MAX) };
        assert!(device.command_busy());
        unsafe { registers.as_mut_ptr().add(6).write_volatile(0) };
        assert!(!device.command_busy());
    }
}

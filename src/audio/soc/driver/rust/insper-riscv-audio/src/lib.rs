//! Platform-selected AUDIO; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_audio_sys as sys;

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
pub struct Audio {
    inner: sys::rv32_audio_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Audio {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _device = Audio::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _device = Audio::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_audio_new(index) };

        if !unsafe { sys::rv32_audio_valid(inner) } {
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
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _count = Audio::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_audio_instance_count() }
    }

    /// Enable this audio function; codec setup and clock policy remain explicit.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.playback(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn playback(&mut self, enabled: bool) {
        unsafe { sys::rv32_audio_playback(self.inner, enabled) };
    }

    /// Enable this audio function; codec setup and clock policy remain explicit.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.recording(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn recording(&mut self, enabled: bool) {
        unsafe { sys::rv32_audio_recording(self.inner, enabled) };
    }

    /// Enable this audio function; codec setup and clock policy remain explicit.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.transmit_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn transmit_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_audio_transmit_interrupt(self.inner, enabled) };
    }

    /// Enable this audio function; codec setup and clock policy remain explicit.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.receive_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn receive_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_audio_receive_interrupt(self.inner, enabled) };
    }

    /// Enable this audio function; codec setup and clock policy remain explicit.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.error_interrupt(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn error_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_audio_error_interrupt(self.inner, enabled) };
    }

    /// Enable this audio function; codec setup and clock policy remain explicit.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.clocks(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn clocks(&mut self, enabled: bool) {
        unsafe { sys::rv32_audio_clocks(self.inner, enabled) };
    }

    /// Enable this audio function; codec setup and clock policy remain explicit.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.tone(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn tone(&mut self, enabled: bool) {
        unsafe { sys::rv32_audio_tone(self.inner, enabled) };
    }

    /// Whether the playback queue can accept a sample.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _state = device.tx_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn tx_ready(&mut self) -> bool {
        unsafe { sys::rv32_audio_tx_ready(self.inner) }
    }

    /// Whether the recording queue contains a sample.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _state = device.rx_ready();
    /// # Ok(())
    /// # }
    /// ```
    pub fn rx_ready(&mut self) -> bool {
        unsafe { sys::rv32_audio_rx_ready(self.inner) }
    }

    /// Queue one signed sample; left and right alternate.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _result = device.try_write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_write(&mut self, value: i32) -> Result<(), Error> {
        if unsafe { sys::rv32_audio_try_write(self.inner, value) } {
            Ok(())
        } else {
            Err(Error::WouldBlock)
        }
    }

    /// Pop one sign-extended sample from the recording queue.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// if let Some(value) = device.try_read() {
    ///     let _ = value;
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub fn try_read(&mut self) -> Option<i32> {
        let mut value = 0;

        if unsafe { sys::rv32_audio_try_read(self.inner, &mut value) } {
            Some(value)
        } else {
            None
        }
    }

    /// Clear only playback underflow, recording overflow and dropped write.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.clear_errors();
    /// # Ok(())
    /// # }
    /// ```
    pub fn clear_errors(&mut self) {
        unsafe { sys::rv32_audio_clear_errors(self.inner) };
    }

    /// Read hardware-reported playback capacity.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _value = device.playback_depth();
    /// # Ok(())
    /// # }
    /// ```
    pub fn playback_depth(&mut self) -> u16 {
        unsafe { sys::rv32_audio_playback_depth(self.inner) }
    }

    /// Read hardware-reported recording capacity.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// let _value = device.recording_depth();
    /// # Ok(())
    /// # }
    /// ```
    pub fn recording_depth(&mut self) -> u16 {
        unsafe { sys::rv32_audio_recording_depth(self.inner) }
    }

    /// Configure the master-clock accumulator with clocks disabled.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.set_xck_step(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_xck_step(&mut self, value: u32) {
        unsafe { sys::rv32_audio_set_xck_step(self.inner, value) };
    }

    /// Configure the master-clock accumulator with clocks disabled.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.set_xck_modulus(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_xck_modulus(&mut self, value: u32) {
        unsafe { sys::rv32_audio_set_xck_modulus(self.inner, value) };
    }

    /// Configure this audio parameter with playback/clocks stopped.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.set_bit_divider(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_bit_divider(&mut self, value: u16) {
        unsafe { sys::rv32_audio_set_bit_divider(self.inner, value) };
    }

    /// Configure this audio parameter with playback/clocks stopped.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.set_slot_bits(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_slot_bits(&mut self, value: u16) {
        unsafe { sys::rv32_audio_set_slot_bits(self.inner, value) };
    }

    /// Configure this audio parameter with playback/clocks stopped.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.set_tone_half_period(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_tone_half_period(&mut self, value: u16) {
        unsafe { sys::rv32_audio_set_tone_half_period(self.inner, value) };
    }

    /// Configure this audio parameter with playback/clocks stopped.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.set_tone_amplitude(1);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_tone_amplitude(&mut self, value: u16) {
        unsafe { sys::rv32_audio_set_tone_amplitude(self.inner, value) };
    }

    /// Select a typed sample width; hardware state changes should be serialized.
    ///
    /// ```no_run
    /// use insper_riscv_audio::{Audio, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Audio::new()?;
    /// device.set_sample_width(insper_riscv_audio::SampleWidth::Bits16);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_sample_width(&mut self, width: SampleWidth) {
        let code = match width {
            SampleWidth::Bits16 => 0,
            SampleWidth::Bits24 => 1,
            SampleWidth::Bits32 => 2,
        };

        unsafe { sys::rv32_audio_set_sample_width(self.inner, code) };
    }
}

/// Sample word width accepted by the audio hardware.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SampleWidth {
    Bits16,
    Bits24,
    Bits32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Audio::instance_count();

        if count == 0 {
            assert!(matches!(Audio::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Audio::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            Audio::instance(usize::MAX),
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
        let mut inner = unsafe { sys::rv32_audio_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;

        assert!(unsafe { sys::rv32_audio_valid(inner) });
        let mut device = Audio {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.tx_ready());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(u32::MAX) };
        assert!(device.tx_ready());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(0) };
        assert!(!device.tx_ready());
    }
}

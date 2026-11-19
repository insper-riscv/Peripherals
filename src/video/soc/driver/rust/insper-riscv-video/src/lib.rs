//! Platform-selected VIDEO; no application MMIO addresses are needed.
//! Configuration must be serialized with interrupt handlers and other users.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_video_sys as sys;

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
pub struct Video {
    inner: sys::rv32_video_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Video {
    /// Construct the default platform instance without enabling hardware.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _device = Video::new()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        Self::instance(0)
    }

    /// Select a zero-based platform instance, never an address.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _device = Video::instance(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance(index: usize) -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_video_new(index) };

        if !unsafe { sys::rv32_video_valid(inner) } {
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
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _count = Video::instance_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn instance_count() -> usize {
        unsafe { sys::rv32_video_instance_count() }
    }

    /// Enable the framebuffer display; mode timing comes from the hardware profile.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// device.enable(false);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable(&mut self, enabled: bool) {
        unsafe { sys::rv32_video_enable(self.inner, enabled) };
    }

    /// Current synchronized vertical-sync level.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _state = device.vertical_sync();
    /// # Ok(())
    /// # }
    /// ```
    pub fn vertical_sync(&mut self) -> bool {
        unsafe { sys::rv32_video_vertical_sync(self.inner) }
    }

    /// Current synchronized vertical-blank interval.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _state = device.vertical_blank();
    /// # Ok(())
    /// # }
    /// ```
    pub fn vertical_blank(&mut self) -> bool {
        unsafe { sys::rv32_video_vertical_blank(self.inner) }
    }

    /// Frame counter increments at the start of vertical blanking.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _value = device.frame_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn frame_count(&mut self) -> u32 {
        unsafe { sys::rv32_video_frame_count(self.inner) }
    }

    /// Immutable framebuffer width.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _value = device.width();
    /// # Ok(())
    /// # }
    /// ```
    pub fn width(&mut self) -> u16 {
        unsafe { sys::rv32_video_width(self.inner) }
    }

    /// Immutable framebuffer height.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _value = device.height();
    /// # Ok(())
    /// # }
    /// ```
    pub fn height(&mut self) -> u16 {
        unsafe { sys::rv32_video_height(self.inner) }
    }

    /// Framebuffer storage bits per pixel.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _value = device.pixel_bits();
    /// # Ok(())
    /// # }
    /// ```
    pub fn pixel_bits(&mut self) -> u8 {
        unsafe { sys::rv32_video_pixel_bits(self.inner) }
    }

    /// Stored bits per color channel.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _value = device.channel_bits();
    /// # Ok(())
    /// # }
    /// ```
    pub fn channel_bits(&mut self) -> u8 {
        unsafe { sys::rv32_video_channel_bits(self.inner) }
    }

    /// Whether this hardware provides an indexed palette.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _state = device.indexed();
    /// # Ok(())
    /// # }
    /// ```
    pub fn indexed(&mut self) -> bool {
        unsafe { sys::rv32_video_indexed(self.inner) }
    }

    /// Frame capacity checked against both immutable geometry and the platform window.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let _capacity = device.word_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn word_count(&mut self) -> usize {
        unsafe { sys::rv32_video_word_count(self.inner) }
    }

    /// Validate one framebuffer position once and borrow its display.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let mut word = device.framebuffer_word(0)?;
    /// word.write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn framebuffer_word(&mut self, index: usize) -> Result<FramebufferWord<'_>, Error> {
        FramebufferWord::new(self, index)
    }

    /// Obtain palette operations only for a validated indexed display.
    ///
    /// ```no_run
    /// use insper_riscv_video::{Video, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut device = Video::new()?;
    /// let mut palette = device.palette()?;
    /// palette.set(0, 0, 0, 0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn palette(&mut self) -> Result<Palette<'_>, Error> {
        Palette::new(self)
    }
}

/// A validated framebuffer word tied to its display.
pub struct FramebufferWord<'a> {
    device: &'a mut Video,
    index: usize,
}

impl<'a> FramebufferWord<'a> {
    /// Validate a numbered word, without exposing the framebuffer offset.
    /// ```no_run
    /// use insper_riscv_video::{Video, FramebufferWord, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut display = Video::new()?;
    /// let mut word = FramebufferWord::new(&mut display, 0)?;
    /// word.write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(device: &'a mut Video, index: usize) -> Result<Self, Error> {
        if index >= device.word_count() {
            return Err(Error::OutOfRange);
        }

        Ok(Self { device, index })
    }

    /// Write packed pixels; this immutable geometry cannot invalidate the index.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_video::Error> {
    /// let mut display = insper_riscv_video::Video::new()?;
    /// display.framebuffer_word(0)?.write(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn write(&mut self, pixels: u32) {
        unsafe { sys::rv32_video_write_word(self.device.inner, self.index, pixels) };
    }
}

/// An indexed palette; direct-color hardware cannot construct this handle.
pub struct Palette<'a> {
    device: &'a mut Video,
}

impl<'a> Palette<'a> {
    /// Validate palette availability and its immutable channel width once.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_video::Error> {
    /// let mut display = insper_riscv_video::Video::new()?;
    /// let _palette = insper_riscv_video::Palette::new(&mut display)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(device: &'a mut Video) -> Result<Self, Error> {
        if !device.indexed() || !(1..=10).contains(&device.channel_bits()) {
            return Err(Error::Unsupported);
        }

        Ok(Self { device })
    }

    /// Set one of 256 entries using RGB components from zero to 255.
    /// ```no_run
    /// # fn example() -> Result<(), insper_riscv_video::Error> {
    /// let mut display = insper_riscv_video::Video::new()?;
    /// display.palette()?.set(1, 255, 0, 0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set(&mut self, index: u8, red: u8, green: u8, blue: u8) {
        unsafe { sys::rv32_video_palette_write(self.device.inner, index, red, green, blue) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_platform_is_rejected_before_mmio() {
        let count = Video::instance_count();

        if count == 0 {
            assert!(matches!(Video::new(), Err(Error::Unavailable)));
        }

        assert!(matches!(Video::instance(count), Err(Error::Unavailable)));
        assert!(matches!(
            Video::instance(usize::MAX),
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
        let mut inner = unsafe { sys::rv32_video_new(usize::MAX) };
        inner.base = registers.as_mut_ptr() as usize;
        inner.framebuffer_offset = 131072;
        inner.window_bytes = 262144;
        assert!(unsafe { sys::rv32_video_valid(inner) });
        let mut device = Video {
            inner,
            _single_thread: PhantomData,
        };
        assert!(!device.vertical_sync());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(u32::MAX) };
        assert!(device.vertical_sync());
        unsafe { registers.as_mut_ptr().add(1).write_volatile(0) };
        assert!(!device.vertical_sync());
    }
}

//! Platform-selected TIMER. No heap, raw addresses or register offsets.
//! Handles are not Send/Sync. Serialize configuration, including interrupt handlers.
#![no_std]

use core::{fmt, marker::PhantomData};
use insper_riscv_timer_sys as sys;

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
pub struct Timer {
    inner: sys::rv32_timer_t,
    _single_thread: PhantomData<*mut ()>,
}

impl Timer {
    /// Construct using generated platform metadata; does not reset the hardware.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// let available = Timer::new();
    /// # Ok(())
    /// # }
    /// ```
    pub fn new() -> Result<Self, Error> {
        let inner = unsafe { sys::rv32_timer_platform_new() };
        if !unsafe { sys::rv32_timer_valid(inner) } {
            return Err(Error::Unavailable);
        }
        Ok(Self {
            inner,
            _single_thread: PhantomData,
        })
    }
    /// Start counting.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.start();
    /// # Ok(())
    /// # }
    /// ```
    pub fn start(&mut self) {
        unsafe { sys::rv32_timer_start(self.inner) };
    }
    /// Stop counting.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.stop();
    /// # Ok(())
    /// # }
    /// ```
    pub fn stop(&mut self) {
        unsafe { sys::rv32_timer_stop(self.inner) };
    }
    /// Select one-shot mode.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.one_shot(true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn one_shot(&mut self, enabled: bool) {
        unsafe { sys::rv32_timer_one_shot(self.inner, enabled) };
    }
    /// Enable overflow event generation; CPU routing is separate.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.enable_interrupt(true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable_interrupt(&mut self, enabled: bool) {
        unsafe { sys::rv32_timer_irq_enable(self.inner, enabled) };
    }
    /// Enable the hardware PWM output.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.enable_pwm(true);
    /// # Ok(())
    /// # }
    /// ```
    pub fn enable_pwm(&mut self, enabled: bool) {
        unsafe { sys::rv32_timer_pwm_enable(self.inner, enabled) };
    }
    /// Set the counter top value.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.set_top(100);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_top(&mut self, ticks: u32) {
        unsafe { sys::rv32_timer_set_top(self.inner, ticks) };
    }
    /// Set the PWM duty compare value.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.set_duty(25);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_duty(&mut self, ticks: u32) {
        unsafe { sys::rv32_timer_set_duty(self.inner, ticks) };
    }
    /// Set cycles per timer tick. Zero is rejected.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.set_divider(4)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_divider(&mut self, cycles: u32) -> Result<(), Error> {
        checked(unsafe { sys::rv32_timer_set_divider(self.inner, cycles) })
    }
    /// Load the counter.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.load(0);
    /// # Ok(())
    /// # }
    /// ```
    pub fn load(&mut self, ticks: u32) {
        unsafe { sys::rv32_timer_load(self.inner, ticks) };
    }
    /// Reset timer counter state.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// timer.reset();
    /// # Ok(())
    /// # }
    /// ```
    pub fn reset(&mut self) {
        unsafe { sys::rv32_timer_reset(self.inner) };
    }
    /// Read the current count.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// let ticks = timer.count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn count(&mut self) -> u32 {
        unsafe { sys::rv32_timer_count(self.inner) }
    }
    /// Read and clear the pending overflow event.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// let overflow = timer.take_overflow();
    /// # Ok(())
    /// # }
    /// ```
    pub fn take_overflow(&mut self) -> bool {
        unsafe { sys::rv32_timer_overflow_read_clear(self.inner) }
    }
    /// Read the PWM output level.
    /// ```no_run
    /// use insper_riscv_timer::{Timer, Error};
    /// # fn example() -> Result<(), Error> {
    /// let mut timer = Timer::new()?;
    /// let high = timer.pwm_high();
    /// # Ok(())
    /// # }
    /// ```
    pub fn pwm_high(&mut self) -> bool {
        unsafe { sys::rv32_timer_pwm_read(self.inner) }
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
        assert!(matches!(Timer::new(), Err(Error::Unavailable)));
    }

    #[test]
    fn ffi_registers_boundaries_and_side_effect_contracts() {
        let mut words = [0_u32; 8];
        let mut timer = Timer {
            inner: unsafe { sys::rv32_timer_new(words.as_mut_ptr() as usize) },
            _single_thread: PhantomData,
        };
        timer.start();
        timer.one_shot(true);
        timer.enable_pwm(true);
        timer.enable_interrupt(true);
        assert_eq!(words[0], 15);
        timer.stop();
        assert_eq!(words[0], 14);
        assert_eq!(timer.set_divider(0), Err(Error::Rejected));
        timer.set_divider(4).unwrap();
        assert_eq!(words[7], 3);
        timer.set_top(100);
        timer.set_duty(25);
        timer.load(7);
        assert_eq!(timer.count(), 7);
        assert_eq!(words[3], 100);
        assert_eq!(words[4], 25);
        words[5] = 1;
        words[6] = 1;
        assert!(timer.take_overflow());
        assert!(timer.pwm_high());
        assert_eq!(words[5], 1);
        assert_eq!(words[6], 1);
        timer.reset();
        assert_eq!(words[2], 0);
    }
}

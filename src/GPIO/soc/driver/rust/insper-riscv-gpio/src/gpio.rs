use core::marker::PhantomData;
use insper_riscv_gpio_sys as sys;

use crate::{error::GPIOError, pin::Pin};

/// A platform instance, never a physical address.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Instance {
    /// The first GPIO in the platform map (normally Switches).
    Default,
    Switches,
    Keys,
}

/// An owned, allocation-free handle. Not Send/Sync: configuration uses RMW.
/// Do not access the same instance from an interrupt handler while configuring it.
#[derive(Debug)]
pub struct GPIO {
    pub(crate) inner: sys::rv32_gpio_t,
    pin_count: usize,
    _single_thread: PhantomData<*mut ()>,
}

impl GPIO {
    /// Select the default platform GPIO and expose its first `pin_count` pins.
    /// The platform-generated width is an upper bound, not an MMIO window size.
    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let gpio = GPIO::new(4)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new(pin_count: usize) -> Result<Self, GPIOError> {
        Self::new_for(Instance::Default, pin_count)
    }

    /// Select a named instance without exposing its address.
    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let keys = GPIO::new_for(Instance::Keys, 4)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn new_for(instance: Instance, pin_count: usize) -> Result<Self, GPIOError> {
        let mut gpio = Self::from_platform(instance)?;
        if pin_count == 0 || pin_count > gpio.pin_count {
            return Err(GPIOError::InvalidBuilder);
        }
        gpio.pin_count = pin_count;
        gpio.inner.pin_count = pin_count;
        Ok(gpio)
    }

    /// Use the complete width generated from the selected platform/RTL.
    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn from_platform(instance: Instance) -> Result<Self, GPIOError> {
        let instance = match instance {
            Instance::Default => sys::RV32_GPIO_DEFAULT_INSTANCE,
            Instance::Switches => sys::RV32_GPIO_SWITCHES_INSTANCE,
            Instance::Keys => sys::RV32_GPIO_KEYS_INSTANCE,
        };
        // The C constructor validates metadata and never accesses MMIO.
        let inner = unsafe { sys::rv32_gpio_platform_new(instance) };
        if !unsafe { sys::rv32_gpio_valid(inner) } {
            return Err(GPIOError::InvalidBuilder);
        }
        Ok(Self {
            pin_count: inner.pin_count,
            inner,
            _single_thread: PhantomData,
        })
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let count = gpio.pin_count();
    /// # Ok(())
    /// # }
    /// ```
    pub fn pin_count(&self) -> usize {
        self.pin_count
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let pin = gpio.get(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn get(&self, pin_idx: usize) -> Result<Pin<'_>, GPIOError> {
        if pin_idx >= self.pin_count {
            return Err(GPIOError::InvalidPinIndex);
        }
        Ok(Pin::new(pin_idx, self))
    }

    /// Read and clear ALL pending events once. Inspect this snapshot for each pin.
    /// A persistent level condition can immediately assert a new event.
    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let pending = gpio.take_interrupts();
    /// # Ok(())
    /// # }
    /// ```
    pub fn take_interrupts(&self) -> Interrupts {
        Interrupts::new(
            unsafe { sys::rv32_gpio_irq_read_clear(self.inner) },
            self.pin_count,
        )
    }
}

/// A side-effect-free copy of the read-to-clear interrupt status.
#[derive(Clone, Copy, Debug)]
pub struct Interrupts {
    bits: u32,
    pin_count: usize,
}

impl Interrupts {
    fn new(bits: u32, pin_count: usize) -> Self {
        Self { bits, pin_count }
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let pending = gpio.take_interrupts();
    /// let active = pending.contains(0)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn contains(&self, pin_idx: usize) -> Result<bool, GPIOError> {
        if pin_idx >= self.pin_count {
            return Err(GPIOError::InvalidPinIndex);
        }
        Ok(unsafe { sys::rv32_gpio_irq_contains(self.bits, pin_idx) })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Direction, InterruptMode};

    #[test]
    fn unconfigured_platform_fails_without_accessing_address_zero() {
        if option_env!("RV32_GPIO_CONFIG_DIR").is_none() {
            assert!(matches!(GPIO::new(4), Err(GPIOError::InvalidBuilder)));
        }
    }

    #[test]
    fn configured_factory_rebuilds_from_platform_metadata() {
        extern crate std;
        let Ok(expected) = std::env::var("RV32_GPIO_TEST_WIDTH") else {
            return;
        };
        let width: usize = expected.parse().unwrap();
        let gpio = GPIO::from_platform(Instance::Default).unwrap();
        assert_eq!(gpio.pin_count(), width);
        assert!(GPIO::new(width).is_ok());
        assert!(matches!(GPIO::new(0), Err(GPIOError::InvalidBuilder)));
        assert!(matches!(
            GPIO::new(width + 1),
            Err(GPIOError::InvalidBuilder)
        ));
        assert!(matches!(
            GPIO::from_platform(Instance::Keys),
            Err(GPIOError::InvalidBuilder)
        ));
        assert_eq!(gpio.inner.base, width * 4096);
    }

    #[test]
    fn numbered_pins_direction_output_input_and_boundaries() {
        let mut registers = [0_u32; 11];
        let gpio = GPIO {
            inner: unsafe { sys::rv32_gpio_new(registers.as_mut_ptr() as usize, 32) },
            pin_count: 32,
            _single_thread: PhantomData,
        };
        assert!(matches!(gpio.get(32), Err(GPIOError::InvalidPinIndex)));
        assert!(matches!(
            gpio.get(usize::MAX),
            Err(GPIOError::InvalidPinIndex)
        ));
        let mut pin = gpio.get(31).unwrap();
        assert_eq!(pin.index(), 31);
        assert_eq!(pin.set_high(), Err(GPIOError::NotOutput));
        pin.set_direction(Direction::Output).unwrap();
        assert_eq!(registers[0], 1 << 31);
        pin.set_high().unwrap();
        assert_eq!(registers[2], 1 << 31);
        pin.set_low().unwrap();
        assert_eq!(registers[3], 1 << 31);
        pin.toggle().unwrap();
        assert_eq!(registers[4], 1 << 31);
        registers[9] = 1 << 31;
        assert!(pin.is_high().unwrap());
        assert!(!pin.is_low().unwrap());
        let mut alias = gpio.get(31).unwrap();
        alias.set_direction(Direction::Input).unwrap();
        assert_eq!(pin.toggle(), Err(GPIOError::NotOutput));
        assert_eq!(registers[0], 0);
        registers[8] = (1 << 31) | 1;
        let pending = gpio.take_interrupts();
        assert_eq!(registers[8], (1 << 31) | 1); // RAM has no read-to-clear.
        assert!(pending.contains(31).unwrap());
        assert!(pending.contains(0).unwrap());
        assert!(!pending.contains(1).unwrap());
        assert_eq!(pending.contains(32), Err(GPIOError::InvalidPinIndex));
    }

    #[test]
    fn every_interrupt_mode_maps_to_the_c_registers() {
        let mut registers = [0_u32; 11];
        let gpio = GPIO {
            inner: unsafe { sys::rv32_gpio_new(registers.as_mut_ptr() as usize, 4) },
            pin_count: 4,
            _single_thread: PhantomData,
        };
        let mut pin = gpio.get(3).unwrap();
        for (mode, expected) in [
            (InterruptMode::RisingEdge, [8, 8, 0, 0]),
            (InterruptMode::FallingEdge, [8, 0, 8, 0]),
            (InterruptMode::BothEdges, [8, 8, 8, 0]),
            (InterruptMode::HighLevel, [8, 8, 0, 8]),
            (InterruptMode::LowLevel, [8, 0, 8, 8]),
            (InterruptMode::Disabled, [0, 0, 0, 0]),
        ] {
            pin.configure_interrupt(mode).unwrap();
            assert_eq!(
                [registers[5], registers[6], registers[7], registers[10]],
                expected
            );
        }
    }
}

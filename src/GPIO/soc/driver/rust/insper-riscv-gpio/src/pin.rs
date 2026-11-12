use insper_riscv_gpio_sys as sys;

use crate::{error::GPIOError, gpio::GPIO};

#[derive(Clone, Debug, Copy, PartialEq, Eq)]
pub enum Direction {
    Input,
    Output,
}

#[derive(Clone, Debug, Copy, PartialEq, Eq)]
pub enum InterruptMode {
    Disabled,
    RisingEdge,
    FallingEdge,
    BothEdges,
    HighLevel,
    LowLevel,
}

/// A numbered pin borrowed from its GPIO. No masks or offsets are exposed.
pub struct Pin<'a> {
    idx: usize,
    gpio: &'a GPIO,
}

impl<'a> Pin<'a> {
    pub(crate) fn new(idx: usize, gpio: &'a GPIO) -> Self {
        Self { idx, gpio }
    }

    pub fn index(&self) -> usize {
        self.idx
    }

    pub fn set_direction(&mut self, dir: Direction) -> Result<(), GPIOError> {
        let dir = match dir {
            Direction::Input => sys::RV32_GPIO_INPUT,
            Direction::Output => sys::RV32_GPIO_OUTPUT_PIN,
        };
        checked(unsafe { sys::rv32_gpio_pin_direction(self.gpio.inner, self.idx, dir) })
    }

    /// Read the hardware direction, so another pin handle cannot stale a cache.
    pub fn direction(&self) -> Direction {
        let outputs = unsafe { sys::rv32_gpio_get_direction(self.gpio.inner) };
        if outputs & (1_u32 << self.idx) != 0 {
            Direction::Output
        } else {
            Direction::Input
        }
    }

    pub fn write(&mut self, high: bool) -> Result<(), GPIOError> {
        self.require_output()?;
        checked(unsafe { sys::rv32_gpio_pin_write(self.gpio.inner, self.idx, high) })
    }

    pub fn set_high(&mut self) -> Result<(), GPIOError> {
        self.write(true)
    }

    pub fn set_low(&mut self) -> Result<(), GPIOError> {
        self.write(false)
    }

    pub fn toggle(&mut self) -> Result<(), GPIOError> {
        self.require_output()?;
        checked(unsafe { sys::rv32_gpio_pin_toggle(self.gpio.inner, self.idx) })
    }

    /// Read the synchronized input, which can lag an output change by two clocks.
    pub fn read(&self) -> Result<bool, GPIOError> {
        let mut high = false;
        checked(unsafe { sys::rv32_gpio_pin_read(self.gpio.inner, self.idx, &mut high) })?;
        Ok(high)
    }

    pub fn is_high(&self) -> Result<bool, GPIOError> {
        self.read()
    }

    pub fn is_low(&self) -> Result<bool, GPIOError> {
        self.read().map(|high| !high)
    }

    pub fn configure_interrupt(&mut self, mode: InterruptMode) -> Result<(), GPIOError> {
        let mode = match mode {
            InterruptMode::Disabled => sys::RV32_GPIO_IRQ_DISABLED,
            InterruptMode::RisingEdge => sys::RV32_GPIO_IRQ_RISING_EDGE,
            InterruptMode::FallingEdge => sys::RV32_GPIO_IRQ_FALLING_EDGE,
            InterruptMode::BothEdges => sys::RV32_GPIO_IRQ_BOTH_EDGES,
            InterruptMode::HighLevel => sys::RV32_GPIO_IRQ_HIGH_LEVEL,
            InterruptMode::LowLevel => sys::RV32_GPIO_IRQ_LOW_LEVEL,
        };
        checked(unsafe { sys::rv32_gpio_pin_irq_configure(self.gpio.inner, self.idx, mode) })
    }

    fn require_output(&self) -> Result<(), GPIOError> {
        if self.direction() == Direction::Output {
            Ok(())
        } else {
            Err(GPIOError::NotOutput)
        }
    }
}

fn checked(success: bool) -> Result<(), GPIOError> {
    if success {
        Ok(())
    } else {
        Err(GPIOError::OperationFailed)
    }
}

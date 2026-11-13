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
/// Index validity is established by GPIO::get and cannot change afterward.
/// Multiple handles can refer to one pin, so writing still checks the current
/// hardware direction. A direction cached in a Rust type would become stale
/// when another handle, C code, or an interrupt handler reconfigures that pin.
pub struct Pin<'a> {
    idx: usize,
    gpio: &'a GPIO,
}

impl<'a> Pin<'a> {
    pub(crate) fn new(idx: usize, gpio: &'a GPIO) -> Self {
        Self { idx, gpio }
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// let index = pin.index();
    /// # Ok(())
    /// # }
    /// ```
    pub fn index(&self) -> usize {
        self.idx
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// pin.set_direction(Direction::Output);
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_direction(&mut self, dir: Direction) {
        let dir = match dir {
            Direction::Input => sys::RV32_GPIO_INPUT,
            Direction::Output => sys::RV32_GPIO_OUTPUT_PIN,
        };
        // GPIO::get validates the index; Direction is exhaustive.
        unsafe { sys::rv32_gpio_pin_direction(self.gpio.inner, self.idx, dir) };
    }

    /// Read the hardware direction, so another pin handle cannot stale a cache.
    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// let direction = pin.direction();
    /// # Ok(())
    /// # }
    /// ```
    pub fn direction(&self) -> Direction {
        let outputs = unsafe { sys::rv32_gpio_get_direction(self.gpio.inner) };
        if outputs & (1_u32 << self.idx) != 0 {
            Direction::Output
        } else {
            Direction::Input
        }
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// pin.set_direction(Direction::Output);
    /// pin.write(true)?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn write(&mut self, high: bool) -> Result<(), GPIOError> {
        self.require_output()?;
        unsafe { sys::rv32_gpio_pin_write(self.gpio.inner, self.idx, high) };
        Ok(())
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// pin.set_direction(Direction::Output);
    /// pin.set_high()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_high(&mut self) -> Result<(), GPIOError> {
        self.write(true)
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// pin.set_direction(Direction::Output);
    /// pin.set_low()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn set_low(&mut self) -> Result<(), GPIOError> {
        self.write(false)
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// pin.set_direction(Direction::Output);
    /// pin.toggle()?;
    /// # Ok(())
    /// # }
    /// ```
    pub fn toggle(&mut self) -> Result<(), GPIOError> {
        self.require_output()?;
        unsafe { sys::rv32_gpio_pin_toggle(self.gpio.inner, self.idx) };
        Ok(())
    }

    /// Read the synchronized input, which can lag an output change by two clocks.
    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// let level = pin.read();
    /// # Ok(())
    /// # }
    /// ```
    pub fn read(&self) -> bool {
        let mut high = false;
        unsafe { sys::rv32_gpio_pin_read(self.gpio.inner, self.idx, &mut high) };
        high
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// let high = pin.is_high();
    /// # Ok(())
    /// # }
    /// ```
    pub fn is_high(&self) -> bool {
        self.read()
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// let low = pin.is_low();
    /// # Ok(())
    /// # }
    /// ```
    pub fn is_low(&self) -> bool {
        !self.read()
    }

    /// ```no_run
    /// use insper_riscv_gpio::{GPIO, GPIOError, Instance, Direction, InterruptMode};
    /// # fn example() -> Result<(), GPIOError> {
    /// let gpio = GPIO::from_platform(Instance::Switches)?;
    /// let mut pin = gpio.get(0)?;
    /// pin.configure_interrupt(InterruptMode::RisingEdge);
    /// # Ok(())
    /// # }
    /// ```
    pub fn configure_interrupt(&mut self, mode: InterruptMode) {
        let mode = match mode {
            InterruptMode::Disabled => sys::RV32_GPIO_IRQ_DISABLED,
            InterruptMode::RisingEdge => sys::RV32_GPIO_IRQ_RISING_EDGE,
            InterruptMode::FallingEdge => sys::RV32_GPIO_IRQ_FALLING_EDGE,
            InterruptMode::BothEdges => sys::RV32_GPIO_IRQ_BOTH_EDGES,
            InterruptMode::HighLevel => sys::RV32_GPIO_IRQ_HIGH_LEVEL,
            InterruptMode::LowLevel => sys::RV32_GPIO_IRQ_LOW_LEVEL,
        };
        unsafe { sys::rv32_gpio_pin_irq_configure(self.gpio.inner, self.idx, mode) };
    }

    fn require_output(&self) -> Result<(), GPIOError> {
        if self.direction() == Direction::Output {
            Ok(())
        } else {
            Err(GPIOError::NotOutput)
        }
    }
}

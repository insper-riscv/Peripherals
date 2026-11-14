// SPDX-License-Identifier: Apache-2.0
//! Native RAM-backed FFI tests. RAM does not emulate GPIO hardware side effects.
use insper_riscv_gpio_sys as gpio;

#[test]
fn constructor_and_target_layout() {
    assert_eq!(size_of::<gpio::rv32_gpio_t>(), 2 * size_of::<usize>());
    assert_eq!(align_of::<gpio::rv32_gpio_t>(), align_of::<usize>());

    // Constructors validate arguments without dereferencing the base.
    unsafe {
        assert!(!gpio::rv32_gpio_valid(gpio::rv32_gpio_new(0, 4)));
        assert!(!gpio::rv32_gpio_valid(gpio::rv32_gpio_new(3, 4)));
    }
}

#[test]
fn pin_indices_reach_the_c_driver_and_link_real_symbols() {
    // Eleven MMIO words are registers, not eleven GPIO pins.
    let mut registers = [0_u32; 11];
    let base = registers.as_mut_ptr() as usize;

    // The array is aligned, remains alive and is exclusively used in this test.
    unsafe {
        let handle = gpio::rv32_gpio_new(base, 4);

        assert!(gpio::rv32_gpio_valid(handle));
        assert!(gpio::rv32_gpio_pin_direction(
            handle,
            3,
            gpio::RV32_GPIO_OUTPUT_PIN,
        ));
        assert_eq!(registers[0], 8);

        assert!(gpio::rv32_gpio_pin_write(handle, 3, true));
        assert_eq!(registers[2], 8);
        assert!(gpio::rv32_gpio_pin_write(handle, 3, false));
        assert_eq!(registers[3], 8);
        assert!(gpio::rv32_gpio_pin_toggle(handle, 3));
        assert_eq!(registers[4], 8);

        // The C bounds check must reject these before MMIO/bit shifting.
        assert!(!gpio::rv32_gpio_pin_write(handle, 4, true));
        assert!(!gpio::rv32_gpio_pin_write(handle, usize::MAX, true));
        assert_eq!(registers[2], 8);

        registers[9] = 8;
        let mut high = false;

        assert!(gpio::rv32_gpio_pin_read(handle, 3, &mut high));
        assert!(high);
        assert!(!gpio::rv32_gpio_pin_read(handle, 3, core::ptr::null_mut()));

        assert!(gpio::rv32_gpio_pin_irq_configure(
            handle,
            3,
            gpio::RV32_GPIO_IRQ_BOTH_EDGES,
        ));
        assert_eq!(registers[5], 8);
        assert_eq!(registers[6], 8);
        assert_eq!(registers[7], 8);
        assert_eq!(registers[10], 0);

        registers[8] = 8;
        let snapshot = gpio::rv32_gpio_irq_read_clear(handle);

        assert!(gpio::rv32_gpio_irq_contains(snapshot, 3));
        assert_eq!(registers[8], 8); // RAM cannot model read-to-clear.
    }
}

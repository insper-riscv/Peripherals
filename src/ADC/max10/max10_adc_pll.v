// =============================================================================
// PLL de 10 MHz do conversor do MAX 10 (megafunção altpll)
//
// Exclusiva da placa e escrita em Verilog de propósito: o ADC do MAX 10
// recebe o clock da saída C0 de um PLL (PLL1 ou PLL3), e o ADC_CLK_10 da
// DE10-Lite (pino N5, 10 MHz, seção 3.2 do manual) é ligado a esses PLLs. O
// PLL entrega os mesmos 10 MHz (multiplicador 1, divisor 1) e o sinal de
// travamento, que o núcleo do ADC exige. A megafunção altpll só elabora no
// quartus_map 25.1 por instanciação em Verilog com os parâmetros abaixo; a
// mesma instanciação em VHDL deixa os contadores do PLL em zero (erro 14024),
// e por isso o max10_adc_shell a instancia como component.
// =============================================================================

module max10_adc_pll (
    // Clock de entrada de 10 MHz (ADC_CLK_10).
    input  wire i_clk_10,
    // Clock de 10 MHz do conversor.
    output wire o_adc_clk,
    // O PLL travou.
    output wire o_locked
);

    // Saídas do PLL, C0 no bit 0.
    wire [4:0] clocks;

    altpll pll (
        .inclk              ({1'b0, i_clk_10}),
        .clk                (clocks),
        .locked             (o_locked),
        .activeclock        (),
        .areset             (1'b0),
        .clkbad             (),
        .clkena             ({6{1'b1}}),
        .clkloss            (),
        .clkswitch          (1'b0),
        .configupdate       (1'b0),
        .enable0            (),
        .enable1            (),
        .extclk             (),
        .extclkena          ({4{1'b1}}),
        .fbin               (1'b1),
        .fbmimicbidir       (),
        .fbout              (),
        .fref               (),
        .icdrclk            (),
        .pfdena             (1'b1),
        .phasecounterselect ({4{1'b1}}),
        .phasedone          (),
        .phasestep          (1'b1),
        .phaseupdown        (1'b1),
        .pllena             (1'b1),
        .scanaclr           (1'b0),
        .scanclk            (1'b0),
        .scanclkena         (1'b1),
        .scandata           (1'b0),
        .scandataout        (),
        .scandone           (),
        .scanread           (1'b0),
        .scanwrite          (1'b0),
        .sclkout0           (),
        .sclkout1           (),
        .vcooverrange       (),
        .vcounderrange      ()
    );

    assign o_adc_clk = clocks[0];

    defparam pll.bandwidth_type = "AUTO",
        pll.clk0_divide_by = 1,
        pll.clk0_duty_cycle = 50,
        pll.clk0_multiply_by = 1,
        pll.clk0_phase_shift = "0",
        pll.compensate_clock = "CLK0",
        pll.inclk0_input_frequency = 100000,
        pll.intended_device_family = "MAX 10",
        pll.lpm_hint = "CBX_MODULE_PREFIX=max10_adc_pll",
        pll.lpm_type = "altpll",
        pll.operation_mode = "NORMAL",
        pll.pll_type = "AUTO",
        pll.port_activeclock = "PORT_UNUSED",
        pll.port_areset = "PORT_UNUSED",
        pll.port_clkbad0 = "PORT_UNUSED",
        pll.port_clkbad1 = "PORT_UNUSED",
        pll.port_clkloss = "PORT_UNUSED",
        pll.port_clkswitch = "PORT_UNUSED",
        pll.port_configupdate = "PORT_UNUSED",
        pll.port_fbin = "PORT_UNUSED",
        pll.port_inclk0 = "PORT_USED",
        pll.port_inclk1 = "PORT_UNUSED",
        pll.port_locked = "PORT_USED",
        pll.port_pfdena = "PORT_UNUSED",
        pll.port_phasecounterselect = "PORT_UNUSED",
        pll.port_phasedone = "PORT_UNUSED",
        pll.port_phasestep = "PORT_UNUSED",
        pll.port_phaseupdown = "PORT_UNUSED",
        pll.port_pllena = "PORT_UNUSED",
        pll.port_scanaclr = "PORT_UNUSED",
        pll.port_scanclk = "PORT_UNUSED",
        pll.port_scanclkena = "PORT_UNUSED",
        pll.port_scandata = "PORT_UNUSED",
        pll.port_scandataout = "PORT_UNUSED",
        pll.port_scandone = "PORT_UNUSED",
        pll.port_scanread = "PORT_UNUSED",
        pll.port_scanwrite = "PORT_UNUSED",
        pll.port_clk0 = "PORT_USED",
        pll.port_clk1 = "PORT_UNUSED",
        pll.port_clk2 = "PORT_UNUSED",
        pll.port_clk3 = "PORT_UNUSED",
        pll.port_clk4 = "PORT_UNUSED",
        pll.port_clk5 = "PORT_UNUSED",
        pll.port_clkena0 = "PORT_UNUSED",
        pll.port_clkena1 = "PORT_UNUSED",
        pll.port_clkena2 = "PORT_UNUSED",
        pll.port_clkena3 = "PORT_UNUSED",
        pll.port_clkena4 = "PORT_UNUSED",
        pll.port_clkena5 = "PORT_UNUSED",
        pll.port_extclk0 = "PORT_UNUSED",
        pll.port_extclk1 = "PORT_UNUSED",
        pll.port_extclk2 = "PORT_UNUSED",
        pll.port_extclk3 = "PORT_UNUSED",
        pll.self_reset_on_loss_lock = "OFF",
        pll.width_clock = 5;

endmodule

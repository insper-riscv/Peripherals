# Cria o sistema Platform Designer max10_adc_core: um núcleo altera_modular_adc na variante autônoma
# (CORE_VAR 3), só com as interfaces Avalon-ST de comando e resposta, para o max10_adc.
#
# Uso (generate.sh faz os dois passos):
#   qsys-script --script=max10_adc_core.tcl
#   qsys-generate max10_adc_core.qsys --synthesis=VHDL --part=10M50DAF484C7G --output-directory=gen
#
# Valores dos parâmetros: o núcleo gerado para a DE10-Lite (ADC de 10 MHz, 1 MHz de amostragem, canais 1 a 6)
# que acompanha o Quartus em ip/altera/university_program/input_output/altera_up_avalon_adc/hdl/de10 usa
# clkdiv 2, refsel 0 e a máscara de pinos 63; aqui a máscara cobre os canais 1 a 8 (ADC1IN1 a ADC1IN8) e o
# sensor de temperatura. A fonte de referência (refsel) é a desse núcleo e não consta do manual da placa.

package require -exact qsys 25.1

create_system max10_adc_core
set_project_property DEVICE_FAMILY "MAX 10"
set_project_property DEVICE 10M50DAF484C7G
set_project_property HIDE_FROM_IP_CATALOG false

add_instance adc altera_modular_adc
set_instance_parameter_value adc CORE_VAR 3
set_instance_parameter_value adc is_this_first_or_second_adc 1
set_instance_parameter_value adc clkdiv 2
set_instance_parameter_value adc sample_rate 0
set_instance_parameter_value adc refsel 0
set_instance_parameter_value adc use_tsd true
foreach channel {1 2 3 4 5 6 7 8} {
    set_instance_parameter_value adc use_ch$channel true
}

add_interface clock clock sink
set_interface_property clock EXPORT_OF adc.clock
add_interface reset reset sink
set_interface_property reset EXPORT_OF adc.reset_sink
add_interface adc_pll_clock clock sink
set_interface_property adc_pll_clock EXPORT_OF adc.adc_pll_clock
add_interface adc_pll_locked conduit end
set_interface_property adc_pll_locked EXPORT_OF adc.adc_pll_locked
add_interface command avalon_streaming sink
set_interface_property command EXPORT_OF adc.command
add_interface response avalon_streaming source
set_interface_property response EXPORT_OF adc.response

save_system max10_adc_core.qsys

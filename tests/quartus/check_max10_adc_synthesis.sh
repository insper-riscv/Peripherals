#!/usr/bin/env bash
# Prova que o invólucro max10_adc_shell elabora no Quartus Prime Lite: gera o IP do núcleo do ADC com o
# Platform Designer e roda a síntese (quartus_map) do shell para o 10M50DAF484C7G, sem ajuste de pinos.
# Uso: tests/quartus/check_max10_adc_synthesis.sh [diretório de trabalho]
# QUARTUS_ROOTDIR aponta para a instalação (padrão /opt/altera_lite/25.1std/quartus).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="${1:-$(mktemp -d)}"
quartus="${QUARTUS_ROOTDIR:-/opt/altera_lite/25.1std/quartus}"
export PATH="$quartus/bin:$quartus/sopc_builder/bin:$PATH"

mkdir -p "$work"
"$root/src/ADC/max10/ip/generate.sh" "$work/ip"

cd "$work"
cat > max10_adc_shell.qsf <<EOQ
set_global_assignment -name FAMILY "MAX 10"
set_global_assignment -name DEVICE 10M50DAF484C7G
set_global_assignment -name TOP_LEVEL_ENTITY max10_adc_shell
set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008
set_global_assignment -name QIP_FILE ip/max10_adc_core/synthesis/max10_adc_core.qip
set_global_assignment -name VHDL_FILE $root/src/common/src/utils_pkg.vhd
set_global_assignment -name VHDL_FILE $root/src/common/src/config_pkg.vhd
set_global_assignment -name VHDL_FILE $root/src/ADC/soc/max10_adc_consts.vhd
set_global_assignment -name VHDL_FILE $root/src/ADC/soc/max10_adc_sequencer.vhd
set_global_assignment -name VHDL_FILE $root/src/ADC/soc/max10_adc.vhd
set_global_assignment -name VERILOG_FILE $root/src/ADC/max10/max10_adc_pll.v
set_global_assignment -name VHDL_FILE $root/src/ADC/max10/max10_adc_ip.vhd
set_global_assignment -name VHDL_FILE $root/src/ADC/max10/max10_adc_shell.vhd
EOQ
quartus_map max10_adc_shell

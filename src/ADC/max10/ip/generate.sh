#!/usr/bin/env bash
# Gera o núcleo altera_modular_adc (max10_adc_core) com o Platform Designer do Quartus Prime Lite.
# Uso: ip/generate.sh <diretório de saída>   (QUARTUS_ROOTDIR aponta para a instalação, por exemplo
# /opt/altera_lite/25.1std/quartus). A saída é <diretório>/max10_adc_core/synthesis/max10_adc_core.qip,
# que o projeto Quartus inclui com `set_global_assignment -name QIP_FILE`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:?uso: generate.sh <diretório de saída>}"
quartus="${QUARTUS_ROOTDIR:-/opt/altera_lite/25.1std/quartus}"
export PATH="$quartus/bin:$quartus/sopc_builder/bin:$PATH"

mkdir -p "$out"
cd "$out"
qsys-script --script="$here/max10_adc_core.tcl"
qsys-generate max10_adc_core.qsys --synthesis=VHDL --part=10M50DAF484C7G --output-directory=max10_adc_core
echo "IP gerado em $out/max10_adc_core/synthesis/max10_adc_core.qip"

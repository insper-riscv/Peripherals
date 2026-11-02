#!/usr/bin/env bash
# The formal proofs of this repository. It has none yet, so a run writes an empty result for the engine and
# the formal job decides over zero proofs. A proof joins by running sby here and writing one line per proof to
# build/formal/result-<engine>.tsv, the way the Core and the Memory do (see formal/aggregate.sh for the format).
# Run from the root of the repository:  FORMAL_ENGINE=bitwuzla bash formal/run.sh
set -euo pipefail

engine="${FORMAL_ENGINE:-bitwuzla}"
case "$engine" in
  yices | bitwuzla | boolector | abc-bmc3) ;;
  *) echo "FORMAL_ENGINE must be yices, bitwuzla, boolector or abc-bmc3, not '$engine'" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/build/formal"
: > "$root/build/formal/result-$engine.tsv"
echo "This repository has no formal proofs yet (engine $engine)."

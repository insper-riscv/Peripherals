#!/usr/bin/env bash
# Tests of formal/aggregate.sh over made-up results:  bash formal/aggregate_test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

# row <id> <wanted> <verdict>: a line of a result file.
row() { printf '%s\t%s\t%s\t0\t10\tlabel of %s\n' "$1" "$2" "$3" "$1"; }

# check <name> <wanted exit code> <directory>: runs the aggregator and compares its exit code.
check() {
  local code=0
  bash "$here/aggregate.sh" "$3" > "$work/out.txt" 2>&1 || code=$?
  if [ "$code" = "$2" ]; then echo "ok    $1"; else echo "WRONG $1: exit $code, wanted $2"; cat "$work/out.txt"; failures=$((failures + 1)); fi
}

d="$work/agree"; mkdir "$d"
{ row p1 pass pass; row m1 fail fail; } > "$d/result-yices.tsv"
{ row p1 pass pass; row m1 fail fail; } > "$d/result-bitwuzla.tsv"
check "every engine agrees with what is wanted" 0 "$d"

d="$work/one-error"; mkdir "$d"
{ row p1 pass pass; row m1 fail fail; } > "$d/result-bitwuzla.tsv"
{ row p1 pass error; row m1 fail error; } > "$d/result-yices.tsv"
check "an engine with an error does not stop another from deciding" 0 "$d"

d="$work/skip"; mkdir "$d"
{ row p1 pass pass; row c1 pass pass; } > "$d/result-bitwuzla.tsv"
{ row p1 pass pass; row c1 pass skip; } > "$d/result-abc-bmc3.tsv"
check "a skip is not an answer, and the other engine decides" 0 "$d"

d="$work/disagree"; mkdir "$d"
{ row p1 pass pass; } > "$d/result-bitwuzla.tsv"
{ row p1 pass fail; } > "$d/result-yices.tsv"
check "one engine says pass and another says fail" 1 "$d"

d="$work/nobody"; mkdir "$d"
{ row p1 pass error; } > "$d/result-bitwuzla.tsv"
{ row p1 pass skip; } > "$d/result-abc-bmc3.tsv"
check "no engine answered a proof" 1 "$d"

d="$work/only-broken"; mkdir "$d"
{ row p1 pass error; row m1 fail error; } > "$d/result-yices.tsv"
check "the only engine is broken" 1 "$d"

d="$work/wanted-fail-passed"; mkdir "$d"
{ row m1 fail pass; } > "$d/result-bitwuzla.tsv"
{ row m1 fail pass; } > "$d/result-yices.tsv"
check "the engines agree on pass where fail is wanted" 1 "$d"

d="$work/missing-engine"; mkdir "$d"
{ row p1 pass pass; row p2 pass pass; } > "$d/result-bitwuzla.tsv"
{ row p1 pass pass; } > "$d/result-yices.tsv"
check "an engine that lacks a proof leaves it to the others" 0 "$d"

d="$work/empty"; mkdir "$d"
check "no result file at all" 1 "$d"

[ "$failures" -eq 0 ] && echo "aggregate: all tests passed" || { echo "aggregate: $failures test(s) failed"; exit 1; }

#!/usr/bin/env bash
# Joins the results of the formal engines and decides, per proof, whether the repository passes. Run from
# anywhere:  bash formal/aggregate.sh <directory with result-<engine>.tsv files>
#
# Every engine writes result-<engine>.tsv (see formal/run.sh): one line per proof with the id, the wanted
# verdict (pass or fail), the verdict the engine reached (pass, fail, error or skip), the sby exit code, the
# milliseconds and the label. An error (no verdict: timeout, crash) and a skip (a proof the engine does not do)
# are not answers. For each proof:
#
#   no engine answered                          -> FAIL (nothing decided it)
#   one engine said pass and another said fail  -> FAIL (the engines disagree)
#   the engines agree and differ from the wanted -> FAIL
#   otherwise                                   -> ok
#
# The table of proofs by engines goes to the standard output and, when set, to $GITHUB_STEP_SUMMARY. The exit
# code is 0 when every proof is ok and 1 otherwise, also when there is no result file at all.
set -euo pipefail

dir="${1:?usage: aggregate.sh <directory with result-<engine>.tsv files>}"
files=$(find "$dir" -type f -name 'result-*.tsv' | sort)
if [ -z "$files" ]; then
  echo "formal: no result-<engine>.tsv in $dir, so no engine ran" >&2
  exit 1
fi

report=$(mktemp)
trap 'rm -f "$report"' EXIT

# One awk pass over every file: the engine is the file name between "result-" and ".tsv".
# shellcheck disable=SC2086
awk -F'\t' '
  FNR == 1 {
    engine = FILENAME
    sub(/^.*result-/, "", engine); sub(/\.tsv$/, "", engine)
    engines[++n_engines] = engine
  }
  {
    id = $1
    if (!(id in seen)) { seen[id] = 1; order[++n_ids] = id; label[id] = $6 }
    wanted[id] = $2
    verdict[id, engine] = $3
    ms[id, engine] = $5
  }
  END {
    failed = 0
    printf "| proof |"
    for (e = 1; e <= n_engines; e++) printf " %s |", engines[e]
    printf " wanted | result |\n|:---|"
    for (e = 1; e <= n_engines; e++) printf ":---:|"
    printf ":---:|:---|\n"
    for (i = 1; i <= n_ids; i++) {
      id = order[i]; pass = 0; fail = 0
      printf "| %s |", id
      for (e = 1; e <= n_engines; e++) {
        v = ((id, engines[e]) in verdict) ? verdict[id, engines[e]] : "error"
        if (v == "pass") pass++
        else if (v == "fail") fail++
        printf " %s |", v
      }
      if (pass + fail == 0) result = "FAIL: no engine answered"
      else if (pass > 0 && fail > 0) result = "FAIL: the engines disagree"
      else if ((pass > 0 ? "pass" : "fail") != wanted[id]) result = "FAIL: wanted " wanted[id]
      else result = "ok"
      if (result != "ok") failed++
      printf " %s | %s |\n", wanted[id], result
    }
    printf "\n%d proofs, %d engines, %d failed\n", n_ids, n_engines, failed
    exit(failed > 0 ? 1 : 0)
  }
' $files > "$report" && status=0 || status=$?

cat "$report"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### formal"; echo; cat "$report"; } >> "$GITHUB_STEP_SUMMARY"
fi
if [ "$status" -ne 0 ]; then
  echo "formal: FAILED (some proof has no answer, or the engines disagree, or they differ from the wanted verdict)" >&2
  exit 1
fi
echo "formal: every proof was decided and agrees with what is wanted"

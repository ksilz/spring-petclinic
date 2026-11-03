#!/usr/bin/env bash
# Tests the GC / startup extraction functions of benchmark.sh against saved last-run logs.
# Usage: test_gc.sh <benchmark.sh> <run folder>
script="$1"
run="$2"
funcs=$(mktemp)
for f in extract_startup_time extract_process_startup_time extract_gc_counts_graalvm extract_gc_counts; do
  awk -v name="$f" '$0 ~ "^"name"\\(\\) \\{" {p=1} p {print} p && /^}/ {p=0}' "$script" >>"$funcs"
done
# shellcheck disable=SC1090
source "$funcs"
rm -f "$funcs"

declare -A expect=(
  [jdk25/baseline]="17,2" [jdk25/tuning]="14,1" [jdk25/cds]="2,1" [jdk25/leyden]="2,0" [jdk25/crac]="0,0" [jdk25/graalvm]="4,4"
  [jdk27/baseline]="18,1" [jdk27/tuning]="12,0" [jdk27/cds]="2,1" [jdk27/leyden]="2,0" [jdk27/crac]="0,0"
)
fail=0
for key in jdk25/baseline jdk25/tuning jdk25/cds jdk25/leyden jdk25/crac jdk25/graalvm jdk27/baseline jdk27/tuning jdk27/cds jdk27/leyden jdk27/crac; do
  label="${key#*/}"
  app="$run/$key-app-benchmark-last.log"
  gc="$run/$key-gc-last.log"
  got=$(extract_gc_counts "$label" "$app" "$gc")
  s=$(extract_startup_time "$label" "$app")
  p=$(extract_process_startup_time "$label" "$app")
  status="ok"
  [[ "$got" != "${expect[$key]}" ]] && { status="FAIL (expected ${expect[$key]})"; fail=1; }
  printf "%-16s gc pauses %-6s %-22s startup %-7s from process start %s\n" "$key" "$got" "$status" "$s" "$p"
done
exit $fail

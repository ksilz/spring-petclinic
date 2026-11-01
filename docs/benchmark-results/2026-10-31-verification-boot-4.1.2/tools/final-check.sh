#!/usr/bin/env bash
# Throwaway (RUN-UPGRADE-BENCHMARKS): final end-to-end check on the final commit: graalvm (attempt-4 executable) then crac, track 25.
B="$HOME/bench-runs"
echo "FINAL START $(date -u +%FT%TZ) commit $(git -C "$HOME/projects/petclinic-upgrade" rev-parse --short HEAD)" >>"$B/chain.log"
BENCH_WARMUPS=1 BENCH_RUNS=3 bash "$B/run-track.sh" 25 graalvm
echo "FINAL step graalvm exit $? $(date -u +%FT%TZ)" >>"$B/chain.log"
BENCH_WARMUPS=1 BENCH_RUNS=3 bash "$B/run-track.sh" 25 crac
echo "FINAL step crac exit $? $(date -u +%FT%TZ)" >>"$B/chain.log"
echo "FINAL DONE $(date -u +%FT%TZ)" >>"$B/chain.log"

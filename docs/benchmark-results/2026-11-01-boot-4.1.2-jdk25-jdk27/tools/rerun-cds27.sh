#!/usr/bin/env bash
# Throwaway: rerun of Tuning + CDS on JDK 27 (3 warm-ups + 7 runs), 2026-11-01, after CPU steal hit runs 5-7.
unset BENCH_WARMUPS BENCH_RUNS
B="$HOME/bench-runs"
rm -f "$B/mem.stop"
nohup setsid bash "$B/mem-logger.sh" >/dev/null 2>&1 </dev/null &
echo "RERUN START $(date -u +%FT%TZ)" >>"$B/rerun.log"
bash "$B/run-track.sh" 27 cds
echo "RERUN step exit $? $(date -u +%FT%TZ)" >>"$B/rerun.log"
touch "$B/mem.stop"
echo "RERUN DONE $(date -u +%FT%TZ)" >>"$B/rerun.log"

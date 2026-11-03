#!/usr/bin/env bash
# Throwaway chain for the rerun of 2026-11-02 (fixed GC split, per-run logs). Not part of the repo.
# Track 25 (five JVM variants) -> wait for staged native files -> track 25 graalvm -> track 27.
# One benchmark at a time, default run counts (3 warm-ups + 7 runs). Memory logger runs throughout.
set -uo pipefail
unset BENCH_WARMUPS BENCH_RUNS
B="$HOME/bench-runs"
CHAIN="$B/chain.log"
now() { date -u +%FT%TZ; }

rm -f "$B/mem.stop"
nohup setsid bash "$B/mem-logger.sh" >/dev/null 2>&1 </dev/null &

echo "CHAIN START $(now) default run counts, commit $(git -C "$HOME/projects/petclinic-upgrade" rev-parse --short HEAD)" >>"$CHAIN"

bash "$B/run-track.sh" 25 baseline tuning cds leyden crac
echo "CHAIN step track25-jvm exit $? $(now)" >>"$CHAIN"

# Wait up to 3 h for the GraalVM files staged from the big server.
waited=0
until [[ -f "$B/native/SHA256SUMS" ]] || ((waited >= 10800)); do
  sleep 30
  waited=$((waited + 30))
done
if [[ -f "$B/native/SHA256SUMS" ]]; then
  bash "$B/run-track.sh" 25 graalvm
  echo "CHAIN step track25-graalvm exit $? $(now)" >>"$CHAIN"
else
  mkdir -p "$B/jdk25"
  echo "TRACK 25 ABORTED native-files-not-staged-after-3h $(now)" | tee -a "$B/jdk25/progress.log" >>"$CHAIN"
fi

bash "$B/run-track.sh" 27 baseline tuning cds leyden crac
echo "CHAIN step track27 exit $? $(now)" >>"$CHAIN"

touch "$B/mem.stop"
echo "CHAIN DONE $(now)" >>"$CHAIN"

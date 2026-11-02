#!/usr/bin/env bash
# Throwaway (RUN-UPGRADE-BENCHMARKS): after the chain finishes, rerun track 25 crac with the CRaC wait fix.
B="$HOME/bench-runs"
until grep -q "CHAIN DONE" "$B/chain.log" 2>/dev/null; do sleep 30; done
rm -f "$B/mem.stop"
setsid -f nohup bash "$B/mem-logger.sh" >/dev/null 2>&1 </dev/null
echo "POSTCHAIN START track25-crac-rerun $(date -u +%FT%TZ)" >>"$B/chain.log"
mv "$B/jdk25/crac.log" "$B/jdk25/crac-attempt1.log" 2>/dev/null
BENCH_WARMUPS=1 BENCH_RUNS=3 bash "$B/run-track.sh" 25 crac
echo "POSTCHAIN step track25-crac-rerun exit $? $(date -u +%FT%TZ)" >>"$B/chain.log"
touch "$B/mem.stop"
echo "POSTCHAIN DONE $(date -u +%FT%TZ)" >>"$B/chain.log"

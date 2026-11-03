#!/usr/bin/env bash
# Throwaway memory logger for RUN-UPGRADE-BENCHMARKS. Logs every 15 s until ~/bench-runs/mem.stop exists.
B="$HOME/bench-runs"
while [[ ! -f "$B/mem.stop" ]]; do
  {
    echo "--- $(date -u +%FT%TZ)"
    free -m | sed -n '2,3p'
    vmstat 1 2 | tail -n1
  } >>"$B/mem.log"
  sleep 15
done

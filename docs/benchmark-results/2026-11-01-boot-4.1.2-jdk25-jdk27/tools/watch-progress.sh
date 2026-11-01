#!/usr/bin/env bash
# Mac side: wakes up after the next finished variant (or a failure, the chain end, or ~10 min unreachable).
# Usage: watch-progress.sh <number of VARIANT ... EXIT lines already reported>
KEY=~/.ssh/AWS-Better-Projects-Faster-GmbH.pem
O=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
SMALL=ubuntu@35.158.97.4
seen="${1:-0}" fails=0
while true; do
  out=$(ssh "${O[@]}" "$SMALL" 'cat ~/bench-runs/chain.log ~/bench-runs/jdk25/progress.log ~/bench-runs/jdk27/progress.log 2>/dev/null; true' 2>/dev/null)
  rc=$?
  if ((rc != 255)); then
    fails=0
    n=$(grep -c "VARIANT .* EXIT" <<<"$out")
    if grep -qE "EXIT [1-9]|CSV (bad|missing)|ABORTED" <<<"$out"; then echo "WATCH: failure"; echo "$out"; exit 1; fi
    if grep -q "CHAIN DONE" <<<"$out" || ((n > seen)); then
      grep -q "CHAIN DONE" <<<"$out" && echo "WATCH: chain done" || echo "WATCH: variant finished (count $n)"
      echo "$out"
      ssh "${O[@]}" "$SMALL" 'for f in ~/bench-runs/jdk25/result_*.csv ~/bench-runs/jdk27/result_*.csv; do [ -f "$f" ] && echo "$(basename "$f"): $(tail -1 "$f")"; done; tail -3 ~/bench-runs/mem.log' 2>/dev/null
      exit 0
    fi
  else
    fails=$((fails + 1))
    if ((fails >= 5)); then echo "WATCH: small server unreachable since about $((fails * 2)) min, $(date -u +%FT%TZ)"; exit 2; fi
  fi
  sleep 120
done

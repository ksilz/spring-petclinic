#!/usr/bin/env bash
# Throwaway diagnostic: start a PetClinic executable N times, record "Started ... in X seconds",
# then stop it. Usage: startup-probe.sh <label> <runs> <command...>
# Writes app logs to ~/investigate/logs/<label>-<n>.log and one summary line per run to stdout.
set -u
label="$1"; runs="$2"; shift 2
mkdir -p ~/investigate/logs
cd ~/investigate || exit 1
for n in $(seq 1 "$runs"); do
  if ss -tln | grep -q ":8080 "; then echo "PROBE $label ABORT port-8080-busy"; exit 1; fi
  log=~/investigate/logs/"$label-$n".log
  "$@" >"$log" 2>&1 &
  pid=$!
  t=""
  for _ in $(seq 1 300); do
    t=$(grep -o "Started PetClinicApplication in [0-9.]* seconds" "$log" | grep -o "[0-9.]*" | head -1)
    [[ -n "$t" ]] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  scripts=$(grep -c "Executing SQL script from" "$log")
  script_ms=$(grep -o "Executed SQL script from .*\.sql\] in [0-9]* ms" "$log" | sed -E 's/.*\/([a-z]+)\.sql\] in ([0-9]+) ms/\1=\2ms/' | tr '\n' ' ')
  kill -TERM "$pid" 2>/dev/null
  for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  for _ in $(seq 1 100); do ss -tln | grep -q ":8080 " || break; sleep 0.1; done
  echo "PROBE $label run=$n startup=${t:-FAILED} sql_scripts=$scripts ${script_ms}"
  sleep 2
done

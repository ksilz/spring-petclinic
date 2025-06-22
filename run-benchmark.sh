#!/bin/bash
# Usage: ./benchmark.sh <JAR_PATH> <LABEL> [-Dspring.aot.enabled=true]

# ---------------- Parameters & checks ----------------
JAR_PATH="$1"
LABEL="$2"
AOT_FLAG="${3:-}"        # optional third param

[[ -z $JAR_PATH ]] && { echo "ERROR: missing JAR_PATH"; exit 1; }
[[ ! -f $JAR_PATH ]] && { echo "ERROR: $JAR_PATH not found"; exit 1; }
[[ -z $LABEL ]] && { echo "ERROR: missing LABEL"; exit 1; }
if [[ -n $AOT_FLAG && $AOT_FLAG != "-Dspring.aot.enabled=true" ]]; then
  echo "ERROR: third param must be '-Dspring.aot.enabled=true' (or omitted)"; exit 1
fi

# ---------------- Configuration -----------------------
APP_CMD="java ${AOT_FLAG} -jar $JAR_PATH --spring.profiles.active=postgres"
CSV_FILE="${LABEL}_results.csv"
WARMUPS=3
RUNS=7

# list of URLs to hit
URLS=(
  "http://localhost:8080/owners?lastName="
  "http://localhost:8080/owners?page=2"
  "http://localhost:8080/owners?page=1"
  "http://localhost:8080/owners/2"
  "http://localhost:8080/owners?page=1"
  "http://localhost:8080/owners/5"
  "http://localhost:8080/vets.html"
  "http://localhost:8080/vets.html?page=2"
  "http://localhost:8080/vets.html?page=1"
  "http://localhost:8080/oups"
)

# ---------- function reused by warm-ups & benchmarks ----------
hit_urls() {
  printf '    Calling URLs: '           # four-space indent
  for url in "${URLS[@]}"; do
    curl -s -o /dev/null -w '%{http_code} ' "$url"
    sleep 5
  done
  echo                     # newline
}

# ---------------- Warm-up phase -----------------------
echo "Warm-up ($WARMUPS runs)…"
for ((i=1;i<=WARMUPS;i++)); do
  echo "  Warm-up $i"
  : > /tmp/app_out.log
  $APP_CMD > /tmp/app_out.log 2>&1 &
  pid=$!
  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
  hit_urls                       # --- load generator ---
  kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
done

# ---------------- Benchmark phase ---------------------
echo "Starting $RUNS benchmark runs…"
echo "Run,Startup Time (s),Max Memory (KB)" > "$CSV_FILE"

declare -a times mems
for ((i=1;i<=RUNS;i++)); do
  echo "  Run $i"
  : > /tmp/app_out.log
  /usr/bin/time -v -o /tmp/time_out.log $APP_CMD > /tmp/app_out.log 2>&1 &
  tpid=$!
  for _ in {1..5}; do java_pid=$(pgrep -P "$tpid" java) && break || sleep 0.3; done
  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
  line=$(grep -m1 "Started PetClinicApplication in" /tmp/app_out.log)
  [[ $line =~ in\ ([0-9.]+)\ seconds ]] && s_time="${BASH_REMATCH[1]}"
  hit_urls                       # --- load generator ---
  kill -TERM "${java_pid:-$tpid}" 2>/dev/null; wait "$tpid" 2>/dev/null
  m_rss=$(grep "Maximum resident set size" /tmp/time_out.log | awk '{print $NF}')
  echo "$i,$s_time,$m_rss" >> "$CSV_FILE"
  times+=("$s_time"); mems+=("$m_rss")
  echo "    ${s_time}s, ${m_rss} KB"
done

# -------- Trimmed-mean averages (drop min & max) -------
trimmed_mean() {
  local sorted=($(printf '%s\n' "$@" | sort -n))
  local n=${#sorted[@]}; (( n<=2 )) && { echo 0; return; }
  local sum=0
  for ((k=1;k<n-1;k++)); do sum=$(awk "BEGIN{print $sum+${sorted[k]}}"); done
  awk "BEGIN{print $sum/($n-2)}"
}
avg_time=$(trimmed_mean "${times[@]}")
avg_mem=$(trimmed_mean "${mems[@]}")

echo "A,$avg_time,$avg_mem" >> "$CSV_FILE"

# ---------------- Show results -------------------------
echo -e "\n--- Benchmark Results ---"
cat "$CSV_FILE"

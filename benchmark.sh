#!/bin/bash
# Usage: ./benchmark.sh <JAR_PATH> <LABEL> [-Dspring.aot.enabled=true]

# ---------------- Parameters & checks ----------------
JAR_PATH="$1"
LABEL="$2"
AOT_FLAG="${3:-}" # optional third param

[[ -z $JAR_PATH ]] && {
  echo "ERROR: missing JAR_PATH"
  exit 1
}
[[ ! -f $JAR_PATH ]] && {
  echo "ERROR: $JAR_PATH not found"
  exit 1
}
[[ -z $LABEL ]] && {
  echo "ERROR: missing LABEL"
  exit 1
}
if [[ -n $AOT_FLAG && $AOT_FLAG != "-Dspring.aot.enabled=true" ]]; then
  echo "ERROR: third param must be '-Dspring.aot.enabled=true' (or omitted)"
  exit 1
fi

# ---------------- Configuration -----------------------
APP_CMD="java ${AOT_FLAG} -jar $JAR_PATH --spring.profiles.active=postgres"
CSV_FILE="${LABEL}_results.csv"
WARMUPS=1
RUNS=4

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
  printf '    Calling URLs: ' # four-space indent
  for url in "${URLS[@]}"; do
    sleep 3
    curl -s -o /dev/null -w '%{http_code} ' "$url"
  done
  echo # newline
}

# ---------------- Warm-up phase -----------------------
echo "Warm-up ($WARMUPS runs)…"

# Kill any running java processes for spring-petclinic JAR to avoid conflicts
EXISTING_PIDS=$(pgrep -f "java.*spring-petclinic")
if [[ -n "$EXISTING_PIDS" ]]; then
  echo "Killing existing spring-petclinic Java processes: $EXISTING_PIDS"
  kill -9 $EXISTING_PIDS 2>/dev/null || true
fi

for ((i = 1; i <= WARMUPS; i++)); do
  echo "  Warm-up $i"
  $APP_CMD >/tmp/app_out.log 2>&1 &
  pid=$!
  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
  hit_urls # --- load generator ---
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
done

# ---------------- Benchmark phase ---------------------
echo "Starting $RUNS benchmark runs…"
echo "Run,Startup Time (s),Max Memory (KB)" >"$CSV_FILE"

declare -a times mems
for ((i = 1; i <= RUNS; i++)); do
  echo "  Run $i"
  : >/tmp/app_out.log
  if [[ "$(uname)" == "Darwin" ]]; then
    /usr/bin/time -l stdbuf -oL $APP_CMD >/tmp/app_out.log 2>/tmp/time_out.log &
  else
    /usr/bin/time -v -o /tmp/time_out.log stdbuf -oL $APP_CMD >/tmp/app_out.log 2>&1 &
  fi
  tpid=$!
  for _ in {1..5}; do java_pid=$(pgrep -P "$tpid" java) && break || sleep 0.3; done
  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
  line=$(grep -m1 "Started PetClinicApplication in" /tmp/app_out.log)
  [[ $line =~ in\ ([0-9.]+)\ seconds ]] && s_time="${BASH_REMATCH[1]}"
  hit_urls # --- load generator ---
  kill -TERM "${java_pid:-$tpid}" 2>/dev/null
  wait "$tpid" 2>/dev/null
  if [[ "$(uname)" == "Darwin" ]]; then
    m_rss=$(grep "peak memory footprint" /tmp/time_out.log | awk '{print $(NF-3)}')
    m_rss=$((m_rss / 1024))
  else
    m_rss=$(grep "Maximum resident set size" /tmp/time_out.log | awk '{print $NF}')
  fi
  echo "$i,$s_time,$m_rss" >>"$CSV_FILE"
  times+=("$s_time")
  mems+=("$m_rss")
  printf "    %ss, %'d KB\n" "$s_time" "$m_rss"
done

# -------- Trimmed-mean averages (drop min & max) -------
trimmed_mean() {
  local sorted=($(printf '%s\n' "$@" | sort -n))
  local n=${#sorted[@]}
  ((n <= 2)) && {
    echo 0
    return
  }
  local sum=0
  for ((k = 1; k < n - 1; k++)); do sum=$(awk "BEGIN{print $sum+${sorted[k]}}"); done
  awk "BEGIN{print $sum/($n-2)}"
}
avg_time=$(trimmed_mean "${times[@]}")
avg_mem=$(trimmed_mean "${mems[@]}")

echo "A,$avg_time,$avg_mem" >>"$CSV_FILE"

# ---------------- Show results -------------------------
echo -e "\n--- Benchmark Results ---"
cat "$CSV_FILE"

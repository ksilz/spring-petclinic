#!/bin/bash
# Usage: ./benchmark.sh <JAR_PATH> <LABEL> [-Dspring.aot.enabled=true] [training]

# ---------------- Parameters & checks ----------------
JAR_PATH="$1"
LABEL="$2"
AOT_FLAG="${3:-}"      # optional third param
TRAINING_MODE="${4:-}" # optional fourth param for training mode

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

# ---------------- Configuration -----------------------
if [[ "$LABEL" == "graalvm" ]]; then
  APP_CMD="./build/native/nativeCompile/spring-petclinic --spring.profiles.active=postgres -Xms512m -Xmx1g"
  TRAIN_CMD="./build/native/nativeCompile/spring-petclinic-instrumented --spring.profiles.active=postgres -Xms512m -Xmx1g"
elif [[ "$LABEL" == "crac" ]]; then
  # For CRaC, use different commands for training (checkpoint creation) and benchmark (restore)
  APP_CMD="java -Xms512m -Xmx1g -XX:+UseG1GC -Dspring.aot.enabled=false -XX:CRaCRestoreFrom=petclinic.bin -jar $JAR_PATH --spring.profiles.active=postgres"
  TRAIN_CMD="java -Xms512m -Xmx1g -XX:+UseG1GC -Dspring.aot.enabled=false -XX:CRaCCheckpointTo=petclinic.bin -jar $JAR_PATH --spring.profiles.active=postgres"
else
  APP_CMD="java -Xms512m -Xmx1g -XX:+UseG1GC ${AOT_FLAG} -jar $JAR_PATH --spring.profiles.active=postgres"
  TRAIN_CMD="$APP_CMD"
fi
CSV_FILE="result_${LABEL}.csv"
WARMUPS=1
RUNS=4

echo
echo "****************************************************************"
echo
echo "Running application"
echo
if [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]]; then
  echo "-> $TRAIN_CMD"
else
  echo "-> $APP_CMD"
fi
echo
echo "****************************************************************"
echo

# list of URLs to hit
URLS=(
  "http://localhost:8080"
  "http://localhost:8080/owners/find"
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
if [[ "$LABEL" == "cds" && ! -f petclinic.jsa ]] || [[ "$LABEL" == "leyden" && ! -f petclinic.aot ]] || [[ "$LABEL" == "crac" ]] || [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]]; then
  echo "Training Run"
else
  echo "Warm-up ($WARMUPS runs)…"
fi

# Kill any running java processes for spring-petclinic JAR to avoid conflicts
EXISTING_PIDS=$(pgrep -f "java.*spring-petclinic")
if [[ -n "$EXISTING_PIDS" ]]; then
  echo "Killing existing spring-petclinic Java processes: $EXISTING_PIDS"
  kill -9 $EXISTING_PIDS 2>/dev/null || true
fi
# Kill any running native spring-petclinic processes to avoid conflicts
NATIVE_PIDS=$(pgrep -f "build/native/nativeCompile/spring-petclinic")
if [[ -n "$NATIVE_PIDS" ]]; then
  echo "Killing existing native spring-petclinic processes: $NATIVE_PIDS"
  kill -9 $NATIVE_PIDS 2>/dev/null || true
fi

# --- Special training run for CDS and Leyden ---
if [[ "$LABEL" == "cds" ]]; then
  if [[ ! -f petclinic.jsa ]]; then
    echo "  CDS (creates petclinic.jsa)"
    java -XX:ArchiveClassesAtExit=petclinic.jsa -jar "$JAR_PATH" >/tmp/app_out.log 2>&1 &
    pid=$!
    while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
    hit_urls
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "  CDS training run complete. Proceeding with benchmark measurements."
  fi
elif [[ "$LABEL" == "leyden" ]]; then
  if [[ ! -f petclinic.aot ]]; then
    echo "  Leyden (creates petclinic.aot)"
    java -XX:AOTCacheOutput=petclinic.aot -jar "$JAR_PATH" >/tmp/app_out.log 2>&1 &
    pid=$!

    # Find the actual Java process to kill
    for _ in {1..10}; do
      app_pid=$(pgrep -P "$pid" java) && break || sleep 0.5
    done

    # Wait for startup with timeout (60 seconds)
    timeout_counter=0
    while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do
      sleep 1
      timeout_counter=$((timeout_counter + 1))
      if [[ $timeout_counter -ge 60 ]]; then
        echo "    Timeout waiting for application to start (60s)"
        break
      fi
    done

    if [[ $timeout_counter -lt 60 ]]; then
      hit_urls
    fi

    # Kill the actual application process, fallback to background process if needed
    if [[ -n "$app_pid" ]]; then
      kill -TERM "$app_pid" 2>/dev/null
      sleep 1
      # Force kill if still running
      if kill -0 "$app_pid" 2>/dev/null; then
        kill -9 "$app_pid" 2>/dev/null
      fi
    else
      kill -TERM "$pid" 2>/dev/null
    fi
    wait "$pid" 2>/dev/null
    echo "  Leyden training run complete. Proceeding with benchmark measurements."
  fi
elif [[ "$LABEL" == "crac" ]]; then
  echo "  CRaC (creates checkpoint)"
  $TRAIN_CMD >/tmp/app_out.log 2>&1 &
  pid=$!

  # Find the Java process to take checkpoint
  for _ in {1..10}; do
    app_pid=$(pgrep -P "$pid" java) && break || sleep 0.5
  done

  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
  hit_urls

  # Take CRaC checkpoint before killing
  if [[ -n "$app_pid" ]]; then
    echo "    Taking CRaC checkpoint..."
    jcmd "$app_pid" JDK.checkpoint >/dev/null 2>&1
    sleep 2 # Give time for checkpoint to complete
  fi

  # Kill the application
  if [[ -n "$app_pid" ]]; then
    kill -TERM "$app_pid" 2>/dev/null
    sleep 1
    # Force kill if still running
    if kill -0 "$app_pid" 2>/dev/null; then
      kill -9 "$app_pid" 2>/dev/null
    fi
  else
    kill -TERM "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  echo "  CRaC training run complete. Proceeding with benchmark measurements."
elif [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]]; then
  echo "  GraalVM (instrumented binary)"
  $TRAIN_CMD >/tmp/app_out.log 2>&1 &
  pid=$!

  # Find the actual application process to kill (instrumented binary)
  for _ in {1..10}; do
    app_pid=$(pgrep -f "build/native/nativeCompile/spring-petclinic-instrumented" | grep -v "$pid" | head -1)
    [[ -n "$app_pid" ]] && break
    sleep 0.5
  done

  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
  hit_urls

  # Kill the actual application process, fallback to background process if needed
  if [[ -n "$app_pid" ]]; then
    kill -TERM "$app_pid" 2>/dev/null
    sleep 1
    # Force kill if still running
    if kill -0 "$app_pid" 2>/dev/null; then
      kill -9 "$app_pid" 2>/dev/null
    fi
  else
    kill -TERM "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  echo "  GraalVM training run complete. Returning control to build-and-run.sh."
  exit 0
fi

for ((i = 1; i <= WARMUPS; i++)); do
  echo "  Warm-up $i"
  $APP_CMD >/tmp/app_out.log 2>&1 &
  pid=$!

  # Wait for startup with timeout (60 seconds)
  timeout_counter=0
  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do
    sleep 1
    timeout_counter=$((timeout_counter + 1))
    if [[ $timeout_counter -ge 60 ]]; then
      echo "    Timeout waiting for application to start (60s)"
      break
    fi
  done

  if [[ $timeout_counter -lt 60 ]]; then
    hit_urls # --- load generator ---
  fi

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

  # Find the actual application process to kill
  if [[ "$LABEL" == "graalvm" ]]; then
    # For native executables, look for the correct spring-petclinic process
    if [[ "$TRAINING_MODE" == "training" ]]; then
      # Training run uses instrumented binary
      for _ in {1..10}; do
        app_pid=$(pgrep -f "build/native/nativeCompile/spring-petclinic-instrumented" | grep -v "$tpid" | head -1)
        [[ -n "$app_pid" ]] && break
        sleep 0.5
      done
    else
      # Benchmark run uses regular binary
      for _ in {1..10}; do
        app_pid=$(pgrep -f "build/native/nativeCompile/spring-petclinic" | grep -v "$tpid" | head -1)
        [[ -n "$app_pid" ]] && break
        sleep 0.5
      done
    fi
  else
    # For Java applications, look for the Java process
    for _ in {1..5}; do
      app_pid=$(pgrep -P "$tpid" java) && break || sleep 0.3
    done
  fi

  # Wait for startup with timeout (60 seconds)
  timeout_counter=0
  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do
    sleep 1
    timeout_counter=$((timeout_counter + 1))
    if [[ $timeout_counter -ge 60 ]]; then
      echo "    Timeout waiting for application to start (60s)"
      break
    fi
  done

  if [[ $timeout_counter -lt 60 ]]; then
    line=$(grep -m1 "Started PetClinicApplication in" /tmp/app_out.log)
    [[ $line =~ in\ ([0-9.]+)\ seconds ]] && s_time="${BASH_REMATCH[1]}"
    hit_urls # --- load generator ---
  else
    s_time="N/A"
  fi

  # Kill the actual application process, fallback to time process if needed
  if [[ -n "$app_pid" ]]; then
    kill -TERM "$app_pid" 2>/dev/null
    sleep 1
    # Force kill if still running
    if kill -0 "$app_pid" 2>/dev/null; then
      kill -9 "$app_pid" 2>/dev/null
    fi
  else
    kill -TERM "$tpid" 2>/dev/null
  fi
  wait "$tpid" 2>/dev/null

  # Memory measurement
  if [[ "$(uname)" == "Darwin" ]]; then
    # On macOS, look for "peak memory footprint" for both native and JVM applications
    m_rss=$(grep "peak memory footprint" /tmp/time_out.log | awk '{print $1}')
    if [[ -z "$m_rss" ]]; then
      # Fallback: try to get memory from ps if available
      if [[ -n "$app_pid" ]]; then
        m_rss=$(ps -o rss= -p "$app_pid" 2>/dev/null | tail -1)
      fi
    fi
    # Convert to KB if not already (values are typically in bytes)
    if [[ -n "$m_rss" && "$m_rss" -gt 1000 ]]; then
      m_rss=$((m_rss / 1024))
    fi
  else
    # On Linux, look for "Maximum resident set size" but we'll need to adjust this
    # to use peak memory footprint if available
    m_rss=$(grep "Maximum resident set size" /tmp/time_out.log | awk '{print $NF}')
  fi

  # Ensure we have a valid memory value
  if [[ -z "$m_rss" || "$m_rss" -eq 0 ]]; then
    m_rss="N/A"
  fi

  echo "$i,$s_time,$m_rss" >>"$CSV_FILE"
  times+=("$s_time")
  mems+=("$m_rss")
  printf "    %ss, %s KB\n" "$s_time" "$m_rss"
done

# -------- Trimmed-mean averages (drop min & max) -------
trimmed_mean() {
  # Filter out "N/A" values and convert to numbers
  local valid_values=()
  for val in "$@"; do
    if [[ "$val" != "N/A" && "$val" != "" ]]; then
      valid_values+=("$val")
    fi
  done

  local sorted=($(printf '%s\n' "${valid_values[@]}" | sort -n))
  local n=${#sorted[@]}
  ((n <= 2)) && {
    echo "N/A"
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

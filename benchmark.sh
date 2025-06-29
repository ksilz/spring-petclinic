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
  TRAIN_CMD="./build/native/nativeCompile/spring-petclinic-instrumented --spring.profiles.active=postgres"
elif [[ "$LABEL" == "crac" ]]; then
  # For CRaC, use different commands for training (checkpoint creation) and benchmark (restore)
  APP_CMD="java -Xms512m -Xmx1g -Dspring.aot.enabled=false -XX:CRaCRestoreFrom=petclinic-crac -jar $JAR_PATH --spring.profiles.active=postgres"
  TRAIN_CMD="java -XX:+UseG1GC -Dspring.aot.enabled=false -XX:CRaCCheckpointTo=petclinic-crac -jar $JAR_PATH --spring.profiles.active=postgres"
else
  APP_CMD="java -Xms512m -Xmx1g -XX:+UseG1GC ${AOT_FLAG} -jar $JAR_PATH --spring.profiles.active=postgres"
  TRAIN_CMD="java -XX:+UseG1GC ${AOT_FLAG} -jar $JAR_PATH --spring.profiles.active=postgres"
fi
CSV_FILE="result_${LABEL}.csv"
WARMUPS=3
RUNS=7

# Warning about Leyden on Linux
if [[ "$LABEL" == "leyden" && "$(uname)" == "Linux" ]]; then
  echo "⚠️  WARNING: Leyden AOT cache generation may cause system hangs on Linux."
  echo "   If this happens, set SKIP_LEYDEN_AOT=true to skip AOT generation."
  echo "   Example: SKIP_LEYDEN_AOT=true ./compile-and-run.sh leyden"
  echo
fi

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
# But be careful not to kill the current training process
NATIVE_PIDS=$(pgrep -f "build/native/nativeCompile/spring-petclinic")
if [[ -n "$NATIVE_PIDS" ]]; then
  echo "Killing existing native spring-petclinic processes: $NATIVE_PIDS"
  # Only kill if we're not in training mode for GraalVM
  if [[ "$LABEL" != "graalvm" || "$TRAINING_MODE" != "training" ]]; then
    kill -9 $NATIVE_PIDS 2>/dev/null || true
  else
    echo "  Skipping native process cleanup during GraalVM training"
  fi
fi

# --- Special training run for CDS and Leyden ---
if [[ "$LABEL" == "cds" ]]; then
  if [[ ! -f petclinic.jsa ]]; then
    echo "  CDS (creates petclinic.jsa)"
    cds_cmd="java -XX:ArchiveClassesAtExit=petclinic.jsa -jar $JAR_PATH"
    echo "    Command: $cds_cmd"
    train_start=$(date +%s)
    $cds_cmd >/tmp/app_out.log 2>&1 &
    pid=$!
    while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do sleep 1; done
    hit_urls
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    train_end=$(date +%s)
    train_duration=$(awk "BEGIN {print ($train_end-$train_start)}")
    printf "Training run took %.1f seconds\n" "$train_duration"
    echo "  CDS training run complete. Proceeding with benchmark measurements."
  fi
elif [[ "$LABEL" == "leyden" ]]; then
  if [[ ! -f petclinic.aot ]]; then
    echo "  Leyden (creates petclinic.aot in two steps)"
    train_start=$(date +%s)
    # Step 1: Record mode - collect AOT configuration
    echo "    Step 1: Recording AOT configuration..."
    record_cmd="java -XX:AOTMode=record -XX:AOTConfiguration=petclinic.aotconf -jar $JAR_PATH"
    echo "    Command: $record_cmd"

    # Run without resource limits to avoid memory allocation failures
    $record_cmd >/tmp/app_out.log 2>&1 &
    pid=$!

    # Find the actual Java process to kill
    for _ in {1..10}; do
      app_pid=$(pgrep -P "$pid" java) && break || sleep 0.5
    done

    # Wait for startup with shorter timeout (30 seconds for training run)
    timeout_counter=0
    while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do
      sleep 1
      timeout_counter=$((timeout_counter + 1))

      # Force flush the log file
      sync /tmp/app_out.log 2>/dev/null || true

      if [[ $timeout_counter -ge 30 ]]; then
        echo "    Timeout waiting for application to start (30s)"
        echo "    Last few lines of log:"
        tail -5 /tmp/app_out.log | sed 's/^/      /'
        break
      fi
      # Check if process is still running
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "    Process terminated unexpectedly"
        echo "    Last few lines of log:"
        tail -10 /tmp/app_out.log | sed 's/^/      /'
        break
      fi
    done

    # Check if we actually found the startup message
    if grep -q "Started PetClinicApplication in" /tmp/app_out.log; then
      echo "    Application started successfully"
    else
      echo "    Warning: Could not detect application startup, but continuing..."
    fi

    if [[ $timeout_counter -lt 30 ]]; then
      hit_urls
    else
      # Even if startup detection failed, try to hit URLs in case the app is running
      echo "    Attempting to hit URLs despite startup detection failure..."
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

    # Step 2: Create mode - generate AOT cache from configuration
    if [[ -f petclinic.aotconf ]]; then
      echo "    Step 2: Creating AOT cache from configuration..."
      echo "    Configuration file size: $(ls -lh petclinic.aotconf | awk '{print $5}')"
      create_cmd="java -XX:AOTMode=create -XX:AOTConfiguration=petclinic.aotconf -XX:AOTCache=petclinic.aot -jar $JAR_PATH"
      echo "    Command: $create_cmd"

      # Run without resource limits to avoid memory allocation failures
      $create_cmd >/tmp/app_out.log 2>&1 &
      pid=$!

      # Find the actual Java process to kill
      for _ in {1..10}; do
        app_pid=$(pgrep -P "$pid" java) && break || sleep 0.5
      done

      # Wait for completion with timeout
      timeout_counter=0
      while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        timeout_counter=$((timeout_counter + 1))
        if [[ $timeout_counter -ge 60 ]]; then
          echo "    Timeout waiting for AOT cache creation (60s)"
          break
        fi
      done

      # Kill the process if still running
      if kill -0 "$pid" 2>/dev/null; then
        if [[ -n "$app_pid" ]]; then
          kill -TERM "$app_pid" 2>/dev/null
          sleep 1
          if kill -0 "$app_pid" 2>/dev/null; then
            kill -9 "$app_pid" 2>/dev/null
          fi
        else
          kill -TERM "$pid" 2>/dev/null
        fi
      fi
      wait "$pid" 2>/dev/null

      # Clean up configuration file
      rm -f petclinic.aotconf

      echo "    AOT cache created successfully"
    else
      echo "    Warning: AOT configuration file not found, skipping cache creation"
      echo "    Checking for configuration file:"
      ls -la petclinic.aotconf* 2>/dev/null || echo "      No configuration files found"
      echo "    Last few lines of log from Step 1:"
      tail -10 /tmp/app_out.log | sed 's/^/      /'
    fi

    echo "  Leyden training run complete. Proceeding with benchmark measurements."
    train_end=$(date +%s)
    train_duration=$(awk "BEGIN {print ($train_end-$train_start)}")
    printf "Training run took %.1f seconds\n" "$train_duration"
  fi
elif [[ "$LABEL" == "crac" ]]; then
  echo "  CRaC (creates checkpoint)"
  echo "    Command: $TRAIN_CMD"
  train_start=$(date +%s)
  $TRAIN_CMD >/tmp/app_out.log 2>&1 &
  pid=$!

  # Wait for application to start and extract PID from Spring Boot log
  echo "    Waiting for application to start..."
  timeout_counter=0
  app_pid=""
  while [[ $timeout_counter -lt 60 ]]; do
    # Try to extract PID from Spring Boot startup log
    if grep -q "Starting PetClinicApplication.*with PID" /tmp/app_out.log; then
      app_pid=$(grep "Starting PetClinicApplication.*with PID" /tmp/app_out.log | tail -1 | grep -o "with PID [0-9]*" | awk '{print $3}')
      if [[ -n "$app_pid" ]]; then
        echo "    Found application PID from log: $app_pid"
        break
      fi
    fi

    # Also check if application has started
    if grep -q "Started PetClinicApplication in" /tmp/app_out.log; then
      echo "    Application started successfully"
      break
    fi

    sleep 1
    timeout_counter=$((timeout_counter + 1))
  done

  if [[ -z "$app_pid" ]]; then
    echo "    Error: Could not find Java process PID from Spring Boot log"
    echo "    Background process PID: $pid"
    echo "    Available Java processes:"
    pgrep -f java | while read p; do
      echo "      PID $p: $(ps -p $p -o cmd= 2>/dev/null | head -1)"
    done
    echo "    Last few lines of log:"
    tail -10 /tmp/app_out.log | sed 's/^/      /'
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "    CRaC training failed - skipping benchmark"
    exit 1
  fi

  # Verify the process is still running
  if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "    Error: Application process $app_pid is no longer running"
    echo "    Last few lines of log:"
    tail -10 /tmp/app_out.log | sed 's/^/      /'
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "    CRaC training failed - skipping benchmark"
    exit 1
  fi

  # Wait for application to fully start and hit URLs
  echo "    Application started successfully"
  hit_urls

  # Take CRaC checkpoint before killing
  echo "    Taking CRaC checkpoint..."
  jcmd "$app_pid" JDK.checkpoint >/tmp/jcmd.log 2>&1
  jcmd_exit_code=$?

  if [[ $jcmd_exit_code -eq 0 ]]; then
    echo "    Checkpoint command executed successfully"
  else
    echo "    Warning: jcmd checkpoint command failed with exit code $jcmd_exit_code"
    echo "    jcmd output:"
    cat /tmp/jcmd.log | sed 's/^/      /'
  fi

  # Wait for checkpoint to complete - give it more time
  echo "    Waiting for checkpoint to complete..."
  checkpoint_wait=0
  while [[ $checkpoint_wait -lt 30 ]]; do
    if [[ -d petclinic-crac ]] && [[ "$(ls -A petclinic-crac 2>/dev/null)" ]]; then
      echo "    Checkpoint directory has content after ${checkpoint_wait}s"
      break
    fi
    sleep 1
    checkpoint_wait=$((checkpoint_wait + 1))
    if [[ $((checkpoint_wait % 5)) -eq 0 ]]; then
      echo "    Still waiting for checkpoint... (${checkpoint_wait}s elapsed)"
      # Check if the application process is still running
      if ! kill -0 "$app_pid" 2>/dev/null; then
        echo "    Warning: Application process $app_pid has terminated during checkpoint"
        break
      fi
    fi
  done

  # Verify checkpoint directory was created and has content
  if [[ -d petclinic-crac ]]; then
    if [[ "$(ls -A petclinic-crac 2>/dev/null)" ]]; then
      echo "    Checkpoint directory created successfully: $(ls -lh petclinic-crac)"
      echo "    Checkpoint directory contents:"
      ls -la petclinic-crac | sed 's/^/      /'
    else
      echo "    Error: Checkpoint directory petclinic-crac exists but is empty"
      echo "    Application may have terminated during checkpoint creation"
      echo "    Last few lines of application log:"
      tail -15 /tmp/app_out.log | sed 's/^/      /'
      kill -TERM "$app_pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      echo "    CRaC training failed - skipping benchmark"
      exit 1
    fi
  else
    echo "    Error: Checkpoint directory petclinic-crac was not created"
    echo "    Last few lines of application log:"
    tail -10 /tmp/app_out.log | sed 's/^/      /'
    kill -TERM "$app_pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "    CRaC training failed - skipping benchmark"
    exit 1
  fi

  # Kill the application
  kill -TERM "$app_pid" 2>/dev/null
  sleep 1
  # Force kill if still running
  if kill -0 "$app_pid" 2>/dev/null; then
    kill -9 "$app_pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  train_end=$(date +%s)
  train_duration=$(awk "BEGIN {print ($train_end-$train_start)}")
  printf "Training run took %.1f seconds\n" "$train_duration"
  echo "  CRaC training run complete. Proceeding with benchmark measurements."
elif [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]]; then
  echo "  GraalVM (instrumented binary)"
  echo "    Command: $TRAIN_CMD"
  train_start=$(date +%s)

  $TRAIN_CMD >/tmp/app_out.log 2>&1 &
  pid=$!
  echo "    GraalVM process PID: $pid"

  # Find the actual application process to kill (instrumented binary)
  for _ in {1..10}; do
    app_pid=$(pgrep -f "build/native/nativeCompile/spring-petclinic-instrumented" | grep -v "$pid" | head -1)
    [[ -n "$app_pid" ]] && break
    sleep 0.5
  done
  if [[ -n "$app_pid" ]]; then
    echo "    Found GraalVM app process PID: $app_pid"
  fi

  # Wait for startup with timeout and debug output
  echo "    Waiting for application to start..."
  timeout_counter=0
  while ! grep -qm1 "Started PetClinicApplication in" /tmp/app_out.log; do
    sleep 1
    timeout_counter=$((timeout_counter + 1))

    # Force flush the log file
    sync /tmp/app_out.log 2>/dev/null || true

    # Print progress every 10 seconds
    if [[ $((timeout_counter % 10)) -eq 0 ]]; then
      echo "    Still waiting... ($timeout_counter seconds elapsed)"
      if [[ -n "$app_pid" ]]; then
        if kill -0 "$app_pid" 2>/dev/null; then
          echo "    Process $app_pid is still running"
        else
          echo "    Process $app_pid has terminated"
        fi
      fi
    fi

    if [[ $timeout_counter -ge 120 ]]; then
      echo "    Timeout waiting for application to start (120s)"
      echo "    Last few lines of log:"
      tail -10 /tmp/app_out.log | sed 's/^/      /'
      break
    fi

    # Check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "    Background process terminated unexpectedly"
      echo "    Last few lines of log:"
      tail -15 /tmp/app_out.log | sed 's/^/      /'
      break
    fi
  done

  # Check if we actually found the startup message
  if grep -q "Started PetClinicApplication in" /tmp/app_out.log; then
    echo "    Application started successfully"
    hit_urls
  else
    echo "    Warning: Could not detect application startup, but continuing..."
    echo "    Attempting to hit URLs anyway..."
    hit_urls
  fi

  # Kill the actual application process, fallback to background process if needed
  echo "    Terminating GraalVM process..."
  if [[ -n "$app_pid" ]]; then
    echo "    Killing app process $app_pid"
    kill -TERM "$app_pid" 2>/dev/null
    sleep 2
    # Force kill if still running
    if kill -0 "$app_pid" 2>/dev/null; then
      echo "    Force killing app process $app_pid"
      kill -9 "$app_pid" 2>/dev/null
    fi
  else
    echo "    Killing background process $pid"
    kill -TERM "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
  echo "    GraalVM training run completed at $(date)"
  train_end=$(date +%s)
  train_duration=$(awk "BEGIN {print ($train_end-$train_start)}")
  printf "Training run took %.1f seconds\n" "$train_duration"
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

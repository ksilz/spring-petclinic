#!/bin/bash
# Usage: ./benchmark.sh <JAR_PATH> <LABEL> [-Dspring.aot.enabled=true] [training]

# ---------------- Parameters & checks ----------------
JAR_PATH="$1"
LABEL="$2"
AOT_FLAG="${3:-}"      # optional third param
TRAINING_MODE="${4:-}" # optional fourth param for training mode

# Add timestamp marker for process tracking
SCRIPT_START_TIME=$(date +%s)

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
# Log file configuration - different files for different phases
set_log_file() {
  local phase="$1"
  case "$phase" in
  "training")
    LOG_FILE="/tmp/app_training.log"
    ;;
  "warmup")
    LOG_FILE="/tmp/app_warmup.log"
    ;;
  "benchmark")
    LOG_FILE="/tmp/app_benchmark.log"
    ;;
  *)
    LOG_FILE="/tmp/app_benchmark.log"
    ;;
  esac
}

# CRaC system requirements check
check_crac_requirements() {
  echo "Checking CRaC system requirements..."

  # Check if running on Linux
  if [[ "$(uname)" != "Linux" ]]; then
    echo "❌ CRaC is not supported on $(uname). CRaC requires Linux kernel support."
    echo "   You are currently running on: $(uname -a)"
    echo "   Please run CRaC benchmarks on a Linux system."
    return 1
  fi

  # Check if CRIU is available
  if ! command -v criu >/dev/null 2>&1; then
    echo "❌ CRIU (Checkpoint/Restore In Userspace) is not installed."
    echo "   CRaC requires CRIU to be installed on the system."
    echo ""
    echo "   Installation methods for Ubuntu:"
    echo "   1. Try universe repository:"
    echo "      sudo add-apt-repository universe"
    echo "      sudo apt update"
    echo "      sudo apt install criu"
    echo ""
    echo "   2. Try backports repository:"
    echo "      sudo add-apt-repository \"deb http://archive.ubuntu.com/ubuntu \$(lsb_release -cs)-backports main\""
    echo "      sudo apt update"
    echo "      sudo apt install criu"
    echo ""
    echo "   3. Try PPA:"
    echo "      sudo add-apt-repository ppa:criu/ppa"
    echo "      sudo apt update"
    echo "      sudo apt install criu"
    echo ""
    echo "   4. Build from source:"
    echo "      sudo apt install build-essential libprotobuf-dev libprotobuf-c-dev protobuf-c-compiler"
    echo "      git clone https://github.com/checkpoint-restore/criu.git"
    echo "      cd criu && make && sudo make install"
    echo ""
    echo "   For other distributions:"
    echo "   - RHEL/CentOS: sudo yum install criu"
    echo "   - Fedora: sudo dnf install criu"
    return 1
  fi

  # Check CRIU version
  criu_version=$(criu --version 2>/dev/null | head -1)
  echo "✅ CRIU found: $criu_version"

  # Check if running with elevated privileges
  if [[ $EUID -eq 0 ]]; then
    echo "✅ Running with root privileges"
  else
    echo "✅ Not running with root privileges (using CRaCEngine=warp for non-privileged operation)"
  fi

  # Check if user has necessary capabilities
  if command -v capsh >/dev/null 2>&1; then
    if capsh --print | grep -q "cap_sys_admin"; then
      echo "✅ User has CAP_SYS_ADMIN capability"
    else
      echo "⚠️  User may not have CAP_SYS_ADMIN capability"
      echo "   This capability is often required for CRaC to work properly."
    fi
  fi

  echo "CRaC system requirements check complete."
  return 0
}

# Set initial log file based on current mode
if [[ "$TRAINING_MODE" == "training" ]]; then
  set_log_file "training"
elif [[ "$LABEL" == "cds" && ! -f petclinic.jsa ]] || [[ "$LABEL" == "leyden" && ! -f petclinic.aot ]] || [[ "$LABEL" == "crac" ]]; then
  set_log_file "training"
else
  set_log_file "benchmark"
fi

if [[ "$LABEL" == "graalvm" ]]; then
  APP_CMD="./build/native/nativeCompile/spring-petclinic --spring.profiles.active=postgres -Xms512m -Xmx1g"
  TRAIN_CMD="./build/native/nativeCompile/spring-petclinic-instrumented --spring.profiles.active=postgres"
elif [[ "$LABEL" == "crac" ]]; then
  # For CRaC, use different commands for training (checkpoint creation) and benchmark (restore)
  # Use CRaCEngine=warp to avoid requiring elevated privileges
  # Use JAVA_HOME to ensure we find the correct Java installation
  if [[ -z "$JAVA_HOME" ]]; then
    echo "❌ JAVA_HOME is not set. Please set JAVA_HOME to your Java installation directory."
    echo "   Example: export JAVA_HOME=/usr/lib/jvm/java-17-openjdk"
    exit 1
  fi

  JAVA_CMD="$JAVA_HOME/bin/java"
  if [[ ! -x "$JAVA_CMD" ]]; then
    echo "❌ Java executable not found at $JAVA_CMD"
    echo "   Please check your JAVA_HOME setting: $JAVA_HOME"
    exit 1
  fi

  # Use relative JAR path and specify main class for CRaC
  APP_CMD="$JAVA_CMD -Xms512m -Xmx1g -Dspring.aot.enabled=false -XX:CRaCRestoreFrom=petclinic-crac -XX:CRaCEngine=warp -cp $JAR_PATH org.springframework.samples.petclinic.PetClinicApplication --spring.profiles.active=postgres --spring.datasource.hikari.allow-pool-suspension=true"
  TRAIN_CMD="$JAVA_CMD -XX:+UseG1GC -Dspring.aot.enabled=false -XX:CRaCCheckpointTo=petclinic-crac -XX:CRaCEngine=warp -cp $JAR_PATH org.springframework.samples.petclinic.PetClinicApplication --spring.profiles.active=postgres --spring.datasource.hikari.allow-pool-suspension=true"
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
  # First, wait for the application to be ready by checking the root URL
  echo "    Waiting for application to be ready..."
  readiness_timeout=60
  readiness_counter=0
  while [[ $readiness_counter -lt $readiness_timeout ]]; do
    status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080" 2>/dev/null || echo "000")
    if [[ "$status" == "200" ]]; then
      echo "    Application is ready (status: $status)"
      break
    fi
    sleep 1
    readiness_counter=$((readiness_counter + 1))
    if [[ $((readiness_counter % 5)) -eq 0 ]]; then
      echo "    Still waiting for application readiness... ($readiness_counter seconds elapsed, status: $status)"
    fi
  done

  if [[ $readiness_counter -ge $readiness_timeout ]]; then
    echo "    Warning: Application readiness timeout reached, proceeding anyway..."
  fi

  # Now call the actual URLs
  printf '    Calling URLs: ' # four-space indent
  for url in "${URLS[@]}"; do
    sleep 3
    # For training runs, be more tolerant of errors
    if [[ "$TRAINING_MODE" == "training" ]]; then
      # Just make the request and show the status, don't fail on errors
      status=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
      printf '%s ' "$status"
    else
      # For benchmark runs, be more strict
      curl -s -o /dev/null -w '%{http_code} ' "$url"
    fi
  done
  echo # newline
}

# ---------- Centralized process cleanup function ----------
cleanup_processes() {
  local indent="${1:-}" # Optional indent parameter for consistent formatting

  # Kill any running java processes for spring-petclinic JAR to avoid conflicts
  EXISTING_PIDS=$(pgrep -f "java.*spring-petclinic")
  if [[ -n "$EXISTING_PIDS" ]]; then
    echo "${indent}Killing existing spring-petclinic Java processes: $EXISTING_PIDS"
    kill -9 $EXISTING_PIDS 2>/dev/null || true
  fi

  # For CRaC, also kill any sudo processes running spring-petclinic
  if [[ "$LABEL" == "crac" ]]; then
    SUDO_PIDS=$(pgrep -f "sudo.*java.*spring-petclinic")
    if [[ -n "$SUDO_PIDS" ]]; then
      echo "${indent}Killing existing sudo spring-petclinic processes: $SUDO_PIDS"
      kill -9 $SUDO_PIDS 2>/dev/null || true
    fi
  fi

  # Kill any running native spring-petclinic processes to avoid conflicts
  # But be careful not to kill the current training process
  NATIVE_PIDS=$(pgrep -f "build/native/nativeCompile/spring-petclinic")
  if [[ -n "$NATIVE_PIDS" ]]; then
    echo "${indent}Found existing native spring-petclinic processes: $NATIVE_PIDS"

    # For training runs, be very conservative and don't kill any processes
    if [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]]; then
      echo "${indent}  Skipping native process cleanup during GraalVM training"
    elif [[ "$LABEL" == "graalvm" ]]; then
      # For GraalVM benchmark runs, only kill if we're very sure they're old
      current_script_pid=$$
      should_kill=true

      for pid in $NATIVE_PIDS; do
        # Check if this process is a child of the current script
        if ps -p "$pid" -o ppid= 2>/dev/null | grep -q "^$current_script_pid$"; then
          echo "${indent}  Found native process $pid that is a child of current script - skipping cleanup"
          should_kill=false
          break
        fi

        # Check if process was started very recently (within last 30 seconds)
        if ps -p "$pid" -o etime= 2>/dev/null | grep -q "^[0-9]*:[0-2][0-9]$"; then
          echo "${indent}  Found native process $pid that was started recently - skipping cleanup"
          should_kill=false
          break
        fi
      done

      if [[ "$should_kill" == "true" ]]; then
        echo "${indent}  All native processes appear to be from previous runs, killing them"
        kill -9 $NATIVE_PIDS 2>/dev/null || true
      else
        echo "${indent}  Skipping cleanup due to recent processes"
      fi
    else
      # For non-GraalVM runs, be more aggressive with cleanup
      echo "${indent}  Killing existing native spring-petclinic processes: $NATIVE_PIDS"
      kill -9 $NATIVE_PIDS 2>/dev/null || true
    fi
  fi
}

# Clean up any existing processes before starting warm-up runs
cleanup_processes

for ((i = 1; i <= WARMUPS; i++)); do
  echo "  Warm-up $i"
  set_log_file "warmup"
  $APP_CMD >"$LOG_FILE" 2>&1 &
  pid=$!

  # Wait for startup with timeout (60 seconds)
  timeout_counter=0
  while ! grep -qm1 "Started PetClinicApplication in" "$LOG_FILE"; do
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
  set_log_file "benchmark"
  : >"$LOG_FILE"
  if [[ "$(uname)" == "Darwin" ]]; then
    /usr/bin/time -l stdbuf -oL $APP_CMD >"$LOG_FILE" 2>/tmp/time_out.log &
  else
    /usr/bin/time -v -o /tmp/time_out.log stdbuf -oL $APP_CMD >"$LOG_FILE" 2>&1 &
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
  while ! grep -qm1 "Started PetClinicApplication in" "$LOG_FILE"; do
    sleep 1
    timeout_counter=$((timeout_counter + 1))
    if [[ $timeout_counter -ge 60 ]]; then
      echo "    Timeout waiting for application to start (60s)"
      break
    fi
  done

  if [[ $timeout_counter -lt 60 ]]; then
    line=$(grep -m1 "Started PetClinicApplication in" "$LOG_FILE")
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

#!/bin/bash
# Usage: ./benchmark.sh <JAR_PATH> <LABEL> [-Dspring.aot.enabled=true] [training]

# ---------------- Parameters & checks ----------------
JAR_PATH="$1"
LABEL="$2"
AOT_FLAG="${3:-}"      # optional third param
TRAINING_MODE="${4:-}" # optional fourth param for training mode

# Add timestamp marker for process tracking
SCRIPT_START_TIME=$(date +%s)

# Debug information
echo "DEBUG: Script started with parameters:"
echo "  JAR_PATH: $JAR_PATH"
echo "  LABEL: $LABEL"
echo "  AOT_FLAG: $AOT_FLAG"
echo "  TRAINING_MODE: $TRAINING_MODE"
echo "  SCRIPT_START_TIME: $SCRIPT_START_TIME"
echo "  PID: $$"
echo "  PPID: $PPID"
echo "  Command: $0 $*"
echo "DEBUG: End of debug info"
echo

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
elif [[ "$LABEL" == "cds" && ! -f petclinic.jsa ]] || [[ "$LABEL" == "leyden" && ! -f petclinic.aot ]] || [[ "$LABEL" == "crac" && ! -d petclinic-crac ]]; then
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
  # Checkpoint creation: use -jar with relative path
  # Checkpoint restore: use only -XX:CRaCRestoreFrom without -jar
  APP_CMD="java -Xms512m -Xmx1g -Dspring.aot.enabled=false -XX:CRaCRestoreFrom=petclinic-crac -XX:CRaCEngine=warp --spring.profiles.active=postgres --spring.datasource.hikari.allow-pool-suspension=true"
  TRAIN_CMD="java -XX:+UseG1GC -Dspring.aot.enabled=false -XX:CRaCCheckpointTo=petclinic-crac -XX:CRaCEngine=warp -jar $JAR_PATH --spring.profiles.active=postgres --spring.datasource.hikari.allow-pool-suspension=true"
else
  APP_CMD="java -Xms512m -Xmx1g -XX:+UseG1GC ${AOT_FLAG} -jar $JAR_PATH --spring.profiles.active=postgres"
  TRAIN_CMD="java -XX:+UseG1GC ${AOT_FLAG} -jar $JAR_PATH --spring.profiles.active=postgres"
fi
CSV_FILE="result_${LABEL}.csv"
WARMUPS=1
RUNS=4

# Debug information for configuration
echo "DEBUG: Configuration set:"
echo "  WARMUPS: $WARMUPS"
echo "  RUNS: $RUNS"
echo "  CSV_FILE: $CSV_FILE"
echo "DEBUG: End of configuration debug"
echo

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
if [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]] || [[ "$LABEL" == "cds" && ! -f petclinic.jsa ]] || [[ "$LABEL" == "leyden" && ! -f petclinic.aot ]] || [[ "$LABEL" == "crac" && ! -d petclinic-crac ]]; then
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

# Function to get the appropriate startup message based on label
get_startup_message() {
  local label="$1"
  case "$label" in
  "crac")
    echo "Spring-managed lifecycle restart completed"
    ;;
  *)
    echo "Started PetClinicApplication in"
    ;;
  esac
}

# Function to extract startup time from log based on label
extract_startup_time() {
  local label="$1"
  local log_file="$2"
  case "$label" in
  "crac")
    # For CRaC, look for "(restored JVM running for X ms)" message
    local line=$(grep -m1 "restored JVM running for" "$log_file")
    if [[ $line =~ running\ for\ ([0-9]+)\ ms ]]; then
      # Convert milliseconds to seconds
      local ms="${BASH_REMATCH[1]}"
      local seconds=$(awk "BEGIN {printf \"%.3f\", $ms/1000}")
      echo "$seconds"
    else
      echo "N/A"
    fi
    ;;
  *)
    # For other labels, extract time from "Started PetClinicApplication in X.XXX seconds"
    local line=$(grep -m1 "Started PetClinicApplication in" "$log_file")
    if [[ $line =~ in\ ([0-9.]+)\ seconds ]]; then
      echo "${BASH_REMATCH[1]}"
    else
      echo "N/A"
    fi
    ;;
  esac
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
  NATIVE_PIDS=$(pgrep -f "build/native/nativeCompile/spring-petclinic" | grep -v "$$" | grep -v "benchmark.sh")
  if [[ -n "$NATIVE_PIDS" ]]; then
    echo "${indent}Found existing native spring-petclinic processes: $NATIVE_PIDS"

    # For GraalVM, be very conservative about cleanup
    if [[ "$LABEL" == "graalvm" ]]; then
      # Check if this is a training run (indicated by TRAINING_MODE parameter)
      if [[ "$TRAINING_MODE" == "training" ]]; then
        echo "${indent}  Skipping native process cleanup during GraalVM training"
      else
        # For GraalVM benchmark runs, skip cleanup entirely since training already cleaned up
        echo "${indent}  Skipping native process cleanup during GraalVM benchmark (training already cleaned up)"
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

# --- Special training run for CDS, Leyden, and CRaC ---
if [[ "$LABEL" == "cds" && ! -f petclinic.jsa ]]; then
  echo "Training run CDS (creates petclinic.jsa)"

  # Delete existing CDS cache file if it exists
  if [[ -f petclinic.jsa ]]; then
    echo "    Deleting existing CDS cache: petclinic.jsa"
    rm -f petclinic.jsa
  fi

  cds_cmd="java -XX:ArchiveClassesAtExit=petclinic.jsa -jar $JAR_PATH"
  echo "    Command: $cds_cmd"
  train_start=$(date +%s)
  $cds_cmd >"$LOG_FILE" 2>&1 &
  pid=$!
  while ! grep -qm1 "Started PetClinicApplication in" "$LOG_FILE"; do sleep 1; done
  hit_urls
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  train_end=$(date +%s)
  train_duration=$(awk "BEGIN {print ($train_end-$train_start)}")
  printf "Training run took %.1f seconds\n" "$train_duration"
  echo "  CDS training run complete. Proceeding with benchmark measurements."
elif [[ "$LABEL" == "leyden" && ! -f petclinic.aot ]]; then
  echo "Training run Leyden (creates petclinic.aot in two steps)"

  # Delete existing AOT cache file if it exists
  if [[ -f petclinic.aot ]]; then
    echo "    Deleting existing Leyden AOT cache: petclinic.aot"
    rm -f petclinic.aot
  fi

  train_start=$(date +%s)

  # Step 1: Record mode - collect AOT configuration
  echo "    Step 1: Recording AOT configuration..."
  record_cmd="java -XX:AOTMode=record -XX:AOTConfiguration=petclinic.aotconf -jar $JAR_PATH"
  echo "    Command: $record_cmd"

  # Run without resource limits to avoid memory allocation failures
  $record_cmd >"$LOG_FILE" 2>&1 &
  pid=$!

  # Find the actual Java process to kill
  for _ in {1..10}; do
    app_pid=$(pgrep -P "$pid" java) && break || sleep 0.5
  done

  # Wait for startup with shorter timeout (30 seconds for training run)
  timeout_counter=0
  while ! grep -qm1 "Started PetClinicApplication in" "$LOG_FILE"; do
    sleep 1
    timeout_counter=$((timeout_counter + 1))

    # Force flush the log file
    sync "$LOG_FILE" 2>/dev/null || true

    if [[ $timeout_counter -ge 30 ]]; then
      echo "    Timeout waiting for application to start (30s)"
      echo "    Last few lines of log:"
      tail -5 "$LOG_FILE" | sed 's/^/      /'
      break
    fi
    # Check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "    Process terminated unexpectedly"
      echo "    Last few lines of log:"
      tail -10 "$LOG_FILE" | sed 's/^/      /'
      break
    fi
  done

  # Check if we actually found the startup message
  if grep -q "Started PetClinicApplication in" "$LOG_FILE"; then
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
    $create_cmd >"$LOG_FILE" 2>&1 &
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
    tail -10 "$LOG_FILE" | sed 's/^/      /'
  fi

  echo "  Leyden training run complete. Proceeding with benchmark measurements."
  train_end=$(date +%s)
  train_duration=$(awk "BEGIN {print ($train_end-$train_start)}")
  printf "Training run took %.1f seconds\n" "$train_duration"
elif [[ "$LABEL" == "crac" ]]; then
  echo "  CRaC (creates checkpoint)"

  # Check CRaC system requirements first
  if ! check_crac_requirements; then
    echo "❌ CRaC system requirements not met. Skipping CRaC benchmark."
    exit 1
  fi

  # Clean up any existing processes before starting (with proper indentation)
  cleanup_processes "    "

  echo "    Command: $TRAIN_CMD"
  train_start=$(date +%s)
  $TRAIN_CMD >"$LOG_FILE" 2>&1 &
  pid=$!

  # For CRaC with sudo, we need to find the actual Java process
  # The sudo process will be the parent, and the Java process will be its child
  echo "    Waiting for application to start..."
  timeout_counter=0
  app_pid=""
  while [[ $timeout_counter -lt 60 ]]; do
    # First try to find the Java process that's a child of the sudo process
    if [[ -n "$pid" ]]; then
      # Find Java process that's a child of the sudo process
      app_pid=$(pgrep -P "$pid" java 2>/dev/null | head -1)
      if [[ -n "$app_pid" ]]; then
        echo "    Found Java process PID from sudo process: $app_pid"
        break
      fi
    fi

    # Try to extract PID from Spring Boot startup log
    if grep -q "Starting PetClinicApplication.*with PID" "$LOG_FILE"; then
      log_pid=$(grep "Starting PetClinicApplication.*with PID" "$LOG_FILE" | tail -1 | grep -o "with PID [0-9]*" | awk '{print $3}')
      if [[ -n "$log_pid" ]]; then
        app_pid="$log_pid"
        echo "    Found application PID from log: $app_pid"
        break
      fi
    fi

    # Also check if application has started
    if grep -q "Started PetClinicApplication in" "$LOG_FILE"; then
      echo "    Application started successfully"
      # If we haven't found the PID yet, try one more time to find it
      if [[ -z "$app_pid" && -n "$pid" ]]; then
        app_pid=$(pgrep -P "$pid" java 2>/dev/null | head -1)
        if [[ -n "$app_pid" ]]; then
          echo "    Found Java process PID after startup: $app_pid"
        fi
      fi
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
    tail -10 "$LOG_FILE" | sed 's/^/      /'
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "    CRaC training failed - skipping benchmark"
    exit 1
  fi

  # Verify the process is still running
  if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "    Error: Application process $app_pid is no longer running"
    echo "    Process details:"
    echo "      PID: $app_pid"
    echo "      Background process PID: $pid"
    echo "      Background process status: $(kill -0 "$pid" 2>/dev/null && echo "running" || echo "terminated")"
    echo "    Available Java processes:"
    pgrep -f java | while read p; do
      echo "      PID $p: $(ps -p $p -o user=,cmd= 2>/dev/null | head -1)"
    done
    echo "    Last few lines of log:"
    tail -15 "$LOG_FILE" | sed 's/^/      /'
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
  echo "    Using jcmd to initiate checkpoint on process $app_pid"
  jcmd "$app_pid" JDK.checkpoint >/tmp/jcmd.log 2>&1
  jcmd_exit_code=$?

  if [[ $jcmd_exit_code -eq 0 ]]; then
    echo "    Checkpoint command executed successfully"
  else
    echo "    Warning: jcmd checkpoint command failed with exit code $jcmd_exit_code"
    echo "    jcmd output:"
    cat /tmp/jcmd.log | sed 's/^/      /'
    echo "    Process status check:"
    if kill -0 "$app_pid" 2>/dev/null; then
      echo "      Process $app_pid is still running"
      echo "      Process owner: $(ps -p "$app_pid" -o user= 2>/dev/null)"
      echo "      Process command: $(ps -p "$app_pid" -o cmd= 2>/dev/null | head -1)"
    else
      echo "      Process $app_pid has terminated"
    fi
  fi

  # Wait for checkpoint to complete - give it more time
  echo "    Waiting for checkpoint to complete..."
  checkpoint_wait=0
  max_checkpoint_wait=60 # Increased from 30 to 60 seconds
  while [[ $checkpoint_wait -lt $max_checkpoint_wait ]]; do
    # Check if the application process is still running
    if ! kill -0 "$app_pid" 2>/dev/null; then
      echo "    Warning: Application process $app_pid has terminated during checkpoint"
      break
    fi

    if [[ -d petclinic-crac ]] && [[ "$(ls -A petclinic-crac 2>/dev/null)" ]]; then
      # Check if there are files other than log files
      non_log_files=$(find petclinic-crac -type f ! -name "*.log" 2>/dev/null | wc -l)
      if [[ $non_log_files -gt 0 ]]; then
        echo "    Checkpoint directory has non-log files after ${checkpoint_wait}s"
        break
      else
        echo "    Checkpoint directory exists but only contains log files, waiting for actual checkpoint data..."
      fi
    fi
    sleep 1
    checkpoint_wait=$((checkpoint_wait + 1))
    if [[ $((checkpoint_wait % 5)) -eq 0 ]]; then
      echo "    Still waiting for checkpoint... (${checkpoint_wait}s elapsed)"
      # Show checkpoint directory contents for debugging
      if [[ -d petclinic-crac ]]; then
        echo "    Current checkpoint directory contents:"
        ls -lh petclinic-crac | sed 's/^/      /'
      fi
    fi
  done

  # Verify checkpoint directory was created and has content
  if [[ -d petclinic-crac ]]; then
    if [[ "$(ls -A petclinic-crac 2>/dev/null)" ]]; then
      # Check if there are non-log files
      non_log_files=$(find petclinic-crac -type f ! -name "*.log" 2>/dev/null | wc -l)
      if [[ $non_log_files -gt 0 ]]; then
        echo "    Checkpoint directory created successfully: $(ls -lh petclinic-crac)"
        echo "    Checkpoint directory contents:"
        ls -lh petclinic-crac | sed 's/^/      /'
        echo "    Non-log files found: $non_log_files"

        # Additional verification: check for "warp: Checkpoint successful!" message in log
        if grep -q "warp: Checkpoint successful!" "$LOG_FILE"; then
          echo "    ✅ Checkpoint success confirmed in application log"
        else
          echo "    ⚠️  Warning: 'warp: Checkpoint successful!' message not found in application log"
          echo "    Last few lines of application log:"
          tail -10 "$LOG_FILE" | sed 's/^/      /'
        fi
      else
        echo "    Error: Checkpoint directory petclinic-crac exists but only contains log files"
        echo "    Application may have terminated during checkpoint creation"
        echo "    Checkpoint directory contents:"
        ls -lh petclinic-crac | sed 's/^/      /'
        echo "    jcmd output:"
        cat /tmp/jcmd.log | sed 's/^/      /'
        echo "    CRIU log files (if any):"
        find petclinic-crac -name "*.log" -exec echo "      {}:" \; -exec head -20 {} \; 2>/dev/null || echo "      No CRIU log files found"
        echo "    Last few lines of application log:"
        tail -15 "$LOG_FILE" | sed 's/^/      /'
        kill -TERM "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        echo "    CRaC training failed - skipping benchmark"
        exit 1
      fi
    else
      echo "    Error: Checkpoint directory petclinic-crac is empty"
      echo "    Application may have terminated during checkpoint creation"
      echo "    jcmd output:"
      cat /tmp/jcmd.log | sed 's/^/      /'
      echo "    Last few lines of application log:"
      tail -15 "$LOG_FILE" | sed 's/^/      /'
      kill -TERM "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      echo "    CRaC training failed - skipping benchmark"
      exit 1
    fi
  else
    echo "    Error: Checkpoint directory petclinic-crac was not created"
    echo "    Application may have terminated during checkpoint creation"
    echo "    jcmd output:"
    cat /tmp/jcmd.log | sed 's/^/      /'
    echo "    Last few lines of application log:"
    tail -15 "$LOG_FILE" | sed 's/^/      /'
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "    CRaC training failed - skipping benchmark"
    exit 1
  fi

  # Kill the application
  echo "    Terminating application process..."
  if kill -0 "$app_pid" 2>/dev/null; then
    echo "    Sending TERM signal to application process $app_pid"
    kill -TERM "$app_pid" 2>/dev/null
    sleep 2
    # Force kill if still running
    if kill -0 "$app_pid" 2>/dev/null; then
      echo "    Force killing application process $app_pid"
      kill -9 "$app_pid" 2>/dev/null
    fi
  else
    echo "    Application process $app_pid has already terminated"
  fi
  wait "$pid" 2>/dev/null
  train_end=$(date +%s)
  train_duration=$(awk "BEGIN {print ($train_end-$train_start)}")
  printf "Training run took %.1f seconds\n" "$train_duration"
  echo "  CRaC training run complete. Proceeding with benchmark measurements."
elif [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]]; then
  echo "  GraalVM (instrumented binary)"

  # Clean up existing profiling data before training
  if [[ -d "src/pgo-profiles/main" ]]; then
    echo "    Cleaning up existing profiling data in src/pgo-profiles/main/"
    rm -rf src/pgo-profiles/main/*
    echo "    Profiling directory cleaned"
  else
    echo "    Creating profiling directory src/pgo-profiles/main/"
    mkdir -p src/pgo-profiles/main
  fi

  # Clean up any existing default.iprof in current directory
  if [[ -f "default.iprof" ]]; then
    echo "    Deleting existing default.iprof in current directory"
    rm -f default.iprof
  fi

  echo "    Command: $TRAIN_CMD"
  train_start=$(date +%s)

  $TRAIN_CMD >"$LOG_FILE" 2>&1 &
  pid=$!
  echo "    GraalVM process PID: $pid"

  # Find the actual application process to kill (instrumented binary)
  # Use a more reliable method to find the process we just started
  echo "    Looking for GraalVM application process..."
  app_pid=""

  # Method 1: Look for child processes of our background process
  for _ in {1..5}; do
    app_pid=$(pgrep -P "$pid" 2>/dev/null | head -1)
    [[ -n "$app_pid" ]] && break
    sleep 0.5
  done

  # Method 2: If no child process found, look for the instrumented binary
  # but be more specific about timing
  if [[ -z "$app_pid" ]]; then
    for _ in {1..10}; do
      # Get all instrumented processes and find the most recent one
      all_pids=$(pgrep -f "build/native/nativeCompile/spring-petclinic-instrumented" 2>/dev/null)
      if [[ -n "$all_pids" ]]; then
        # Find the most recently started process
        for candidate_pid in $all_pids; do
          # Check if this process was started very recently (within last 10 seconds)
          if ps -p "$candidate_pid" -o etime= 2>/dev/null | grep -q "^[0-9]*:[0-9]$"; then
            app_pid="$candidate_pid"
            break
          fi
        done
        [[ -n "$app_pid" ]] && break
      fi
      sleep 0.5
    done
  fi

  if [[ -n "$app_pid" ]]; then
    echo "    Found GraalVM app process PID: $app_pid"
  else
    echo "    Warning: Could not find specific GraalVM app process, will use background process $pid"
  fi

  # Wait for startup with timeout and debug output
  echo "    Waiting for application to start..."
  timeout_counter=0
  while ! grep -qm1 "Started PetClinicApplication in" "$LOG_FILE"; do
    sleep 1
    timeout_counter=$((timeout_counter + 1))

    # Force flush the log file
    sync "$LOG_FILE" 2>/dev/null || true

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
      tail -10 "$LOG_FILE" | sed 's/^/      /'
      break
    fi

    # Check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "    Background process terminated unexpectedly"
      echo "    Last few lines of log:"
      tail -15 "$LOG_FILE" | sed 's/^/      /'
      break
    fi
  done

  # Check if we actually found the startup message
  if grep -q "Started PetClinicApplication in" "$LOG_FILE"; then
    echo "    Application started successfully"
    # For training runs, we don't need to be as strict about URL errors
    # Just hit the URLs to generate profiling data, even if some fail
    echo "    Hitting URLs for profiling data generation..."
    hit_urls
  else
    echo "    Warning: Could not detect application startup, but continuing..."
    echo "    Attempting to hit URLs anyway for profiling data..."
    hit_urls
  fi

  # Kill the actual application process, fallback to background process if needed
  echo "    Terminating GraalVM process..."
  if [[ -n "$app_pid" ]]; then
    # Verify the process is still running and is the one we expect
    if kill -0 "$app_pid" 2>/dev/null; then
      # Double-check this is actually the instrumented binary
      if ps -p "$app_pid" -o cmd= 2>/dev/null | grep -q "spring-petclinic-instrumented"; then
        echo "    Killing app process $app_pid (verified instrumented binary)"
        kill -TERM "$app_pid" 2>/dev/null
        sleep 2
        # Force kill if still running
        if kill -0 "$app_pid" 2>/dev/null; then
          echo "    Force killing app process $app_pid"
          kill -9 "$app_pid" 2>/dev/null
        fi
      else
        echo "    Warning: Process $app_pid is not the expected instrumented binary, using background process"
        echo "    Killing background process $pid"
        kill -TERM "$pid" 2>/dev/null
      fi
    else
      echo "    App process $app_pid has already terminated, using background process"
      echo "    Killing background process $pid"
      kill -TERM "$pid" 2>/dev/null
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
  echo "  GraalVM training run complete. Returning control to compile-and-run.sh for rebuild."
  exit 0
fi

# ---------------- Warm-up phase ---------------------
echo "Starting $WARMUPS warm-up run$([[ $WARMUPS -eq 1 ]] && echo '' || echo 's')…"

for ((i = 1; i <= WARMUPS; i++)); do
  echo "  Warm-up $i"
  set_log_file "warmup"
  $APP_CMD >"$LOG_FILE" 2>&1 &
  pid=$!

  # Find the actual application process to kill (same logic as benchmark loop)
  if [[ "$LABEL" == "graalvm" ]]; then
    # For native executables, look for the correct spring-petclinic process
    for _ in {1..10}; do
      app_pid=$(pgrep -f "build/native/nativeCompile/spring-petclinic" | grep -v "$pid" | grep -v "$$" | grep -v "benchmark.sh" | head -1)
      [[ -n "$app_pid" ]] && break
      sleep 0.5
    done
  elif [[ "$LABEL" == "crac" ]]; then
    # For CRaC, the Java process is not a child of the background process
    # Look for the Java process that's running the CRaC restore command
    for _ in {1..10}; do
      app_pid=$(pgrep -f "java.*CRaCRestoreFrom=petclinic-crac" | grep -v "$pid" | head -1)
      [[ -n "$app_pid" ]] && break
      sleep 0.5
    done
  else
    # For Java applications, look for the Java process
    for _ in {1..5}; do
      app_pid=$(pgrep -P "$pid" java) && break || sleep 0.3
    done
  fi

  # Get the appropriate startup message for this label
  startup_message=$(get_startup_message "$LABEL")

  # Wait for startup with timeout (60 seconds)
  timeout_counter=0
  while ! grep -qm1 "$startup_message" "$LOG_FILE"; do
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

  # Kill the actual application process, fallback to background process if needed
  if [[ -n "$app_pid" ]]; then
    echo "    Killing app process $app_pid"
    kill -TERM "$app_pid" 2>/dev/null
    sleep 1
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
  elif [[ "$LABEL" == "crac" ]]; then
    # For CRaC, the Java process is not a child of the time process
    # Look for the Java process that's running the CRaC restore command
    for _ in {1..10}; do
      app_pid=$(pgrep -f "java.*CRaCRestoreFrom=petclinic-crac" | grep -v "$tpid" | head -1)
      [[ -n "$app_pid" ]] && break
      sleep 0.5
    done
  else
    # For Java applications, look for the Java process
    for _ in {1..5}; do
      app_pid=$(pgrep -P "$tpid" java) && break || sleep 0.3
    done
  fi

  # Get the appropriate startup message for this label
  startup_message=$(get_startup_message "$LABEL")

  # Wait for startup with timeout (60 seconds)
  timeout_counter=0
  while ! grep -qm1 "$startup_message" "$LOG_FILE"; do
    sleep 1
    timeout_counter=$((timeout_counter + 1))
    if [[ $timeout_counter -ge 60 ]]; then
      echo "    Timeout waiting for application to start (60s)"
      break
    fi
  done

  if [[ $timeout_counter -lt 60 ]]; then
    s_time=$(extract_startup_time "$LABEL" "$LOG_FILE")
    hit_urls # --- load generator ---
  else
    s_time="N/A"
  fi

  # Kill the actual application process, fallback to time process if needed
  if [[ -n "$app_pid" ]]; then
    echo "    Killing app process $app_pid"
    kill -TERM "$app_pid" 2>/dev/null
    sleep 1
    # Force kill if still running
    if kill -0 "$app_pid" 2>/dev/null; then
      echo "    Force killing app process $app_pid"
      kill -9 "$app_pid" 2>/dev/null
    fi
  else
    echo "    Killing time process $tpid"
    kill -TERM "$tpid" 2>/dev/null
  fi
  wait "$tpid" 2>/dev/null
  echo "    Run $i completed successfully"

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

  # Display memory in MB for screen output, but keep KB for CSV
  if [[ "$m_rss" == "N/A" ]]; then
    printf "    %ss, %s\n" "$s_time" "$m_rss"
  else
    m_rss_mb=$(awk "BEGIN {printf \"%.1f\", $m_rss/1024}")
    printf "    %ss, %.1f MB\n" "$s_time" "$m_rss_mb"
  fi

  # Add debugging information
  echo "    Debug: Run $i finished, continuing to next run..."
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

#!/bin/bash
# Usage: ./benchmark.sh <JAR_PATH> <LABEL> [-Dspring.aot.enabled=true] [training]

# ---------------- Parameters & checks ----------------
JAR_PATH="$1"
LABEL="$2"
AOT_FLAG="${3:-}"       # optional third param
TRAINING_MODE="${4:-}"  # optional fourth param for training mode
SIZE_APP_MB="${5:-}"    # optional 5th param: application size in MB
SIZE_EXTRA_MB="${6:-}"  # optional 6th param: extra artifacts size in MB

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
    echo "      sudo add-apt-repository \"deb https://archive.ubuntu.com/ubuntu \$(lsb_release -cs)-backports main\""
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
elif [[ "$LABEL" == "cds" && ! -f petclinic.jsa ]] || [[ "$LABEL" == "leyden" && ! -f petclinic.aot ]] || [[ "$LABEL" == "crac" && (! -d petclinic-crac || ! -f petclinic-crac/*.img) ]]; then
  set_log_file "training"
else
  set_log_file "benchmark"
fi

# ---------------- Parameter Variables ---------------------
# Standard JVM parameters shared across variants for consistency
# Training and benchmark runs use identical params except where technical constraints differ

# Base JVM parameters (without AOT)
# Heap: initial 256m, max 768m for reduced memory footprint
BASE_JVM_PARAMS="-Xms256m -Xmx768m -XX:+UseG1GC -Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags -Dspring.profiles.active=postgres"

# Base JVM parameters with AOT enabled
BASE_JVM_PARAMS_WITH_AOT="-Xms256m -Xmx768m -XX:+UseG1GC -Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags -Dspring.aot.enabled=true -Dspring.profiles.active=postgres"

# CRaC-specific parameters
# Training: Includes GC for fresh JVM start with full heap/GC configuration
CRAC_TRAINING_PARAMS="-Xms256m -Xmx768m -XX:+UseG1GC -Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags -Dspring.aot.enabled=false -Dspring.profiles.active=postgres -Dspring.datasource.hikari.allow-pool-suspension=true"
# Restore: heap, Spring properties, and datasource settings are restored from the checkpoint;
# only specify a fresh GC log so this run's GC metrics are captured independently
CRAC_RESTORE_PARAMS="-Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags"

# GraalVM parameters (native binary - uses native image GC logging)
# Note: Native images don't support JVM heap parameters like -Xms/-Xmx
# Memory is controlled via build-time settings (see compile-and-run.sh)
# GC output goes to stdout and lands in the app log; extract_gc_counts reads it from there.
# The native executable ignores -Xlog:gc:file=..., so there is no separate GC log file.
GRAALVM_PARAMS="-XX:+PrintGC -XX:+VerboseGC -Dspring.profiles.active=postgres"

# ---------------- Command Definitions ---------------------
if [[ "$LABEL" == "graalvm" ]]; then
  APP_CMD="./build/native/nativeCompile/spring-petclinic $GRAALVM_PARAMS"
  TRAIN_CMD="./build/native/nativeCompile/spring-petclinic-instrumented $GRAALVM_PARAMS"
elif [[ "$LABEL" == "crac" ]]; then
  # For CRaC, use different commands for training (checkpoint creation) and benchmark (restore)
  # Use CRaCEngine=warp to avoid requiring elevated privileges
  # Checkpoint creation: use -jar with relative path
  # Checkpoint restore: use -XX:CRaCRestoreFrom WITHOUT -jar (checkpoint contains all state)
  # IMPORTANT: Training and restore use DIFFERENT parameters:
  #  - Training: includes -XX:+UseG1GC (fresh JVM start)
  #  - Restore: NO GC flag (GC configuration restored from checkpoint)
  APP_CMD="java $CRAC_RESTORE_PARAMS -XX:CRaCRestoreFrom=petclinic-crac -XX:CRaCEngine=warp"
  TRAIN_CMD="java $CRAC_TRAINING_PARAMS -XX:CRaCCheckpointTo=petclinic-crac -XX:CRaCEngine=warp -jar $JAR_PATH"
elif [[ "$LABEL" == "leyden" ]]; then
  # For Leyden, training and benchmark use identical base parameters
  APP_CMD="java $BASE_JVM_PARAMS_WITH_AOT -XX:AOTCache=petclinic.aot -jar $JAR_PATH"
  TRAIN_CMD="java $BASE_JVM_PARAMS_WITH_AOT -XX:AOTCache=petclinic.aot -jar $JAR_PATH"
else
  # Baseline, Tuning, and CDS variants
  # Use BASE_JVM_PARAMS with AOT_FLAG to control AOT setting
  APP_CMD="java $BASE_JVM_PARAMS ${AOT_FLAG} -jar $JAR_PATH"
  TRAIN_CMD="java $BASE_JVM_PARAMS ${AOT_FLAG} -jar $JAR_PATH"
fi
# JDK track (set by compile-and-run.sh): 25 keeps the historic file names, other tracks get a suffix.
JDK_TRACK="${JDK_TRACK:-25}"
case "$JDK_TRACK" in
25 | 27) ;;
*)
  echo "JDK_TRACK must be 25 or 27 (got '$JDK_TRACK')" >&2
  exit 1
  ;;
esac
CSV_SUFFIX=""
if [[ "$JDK_TRACK" != "25" ]]; then
  CSV_SUFFIX="_jdk${JDK_TRACK}"
fi
WARMUPS="${BENCH_WARMUPS:-3}"
RUNS="${BENCH_RUNS:-7}"
if ! [[ "$WARMUPS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: BENCH_WARMUPS must be a non-negative integer (got '$WARMUPS')" >&2
  exit 1
fi
if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || (( 10#$RUNS < 3 )); then
  echo "ERROR: BENCH_RUNS must be an integer >= 3 (got '$RUNS')" >&2
  exit 1
fi
WARMUPS=$((10#$WARMUPS))
RUNS=$((10#$RUNS))
# Smoke tests (non-default run counts) write their own CSV, so they never overwrite an
# official result and can't be mistaken for one.
SMOKE_SUFFIX=""
if [[ "$WARMUPS" -ne 3 || "$RUNS" -ne 7 ]]; then
  SMOKE_SUFFIX="_smoke"
fi
CSV_FILE="result_${LABEL}${CSV_SUFFIX}${SMOKE_SUFFIX}.csv"

# Debug information for configuration
echo "DEBUG: Configuration set:"
echo "  WARMUPS: $WARMUPS"
echo "  RUNS: $RUNS"
echo "  CSV_FILE: $CSV_FILE"
if [[ -n "$SMOKE_SUFFIX" ]]; then
  echo "NOTE: non-default run counts (smoke test): WARMUPS=$WARMUPS, RUNS=$RUNS. Writing $CSV_FILE."
fi
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
if [[ "$LABEL" == "graalvm" && "$TRAINING_MODE" == "training" ]] || [[ "$LABEL" == "cds" && ! -f petclinic.jsa ]] || [[ "$LABEL" == "leyden" && ! -f petclinic.aot ]] || [[ "$LABEL" == "crac" && (! -d petclinic-crac || ! -f petclinic-crac/*.img) ]]; then
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

# ---------- failure cleanup used by every failure path in hit_urls ----------
# Stops the application the same way the callers do after a normal run (SIGTERM, then
# SIGKILL if still alive), so nothing keeps port 8080, and removes cache files that the
# failed run may have left behind. It does not exit; the caller exits afterwards.
# Usage: stop_app_after_failure "<reason>"
stop_app_after_failure() {
  local reason="${1:-failure}"
  # The tracked app process is stopped first; the launcher process is the fallback (tpid in
  # the benchmark phase, pid in training and warm-up runs). SIGTERM first keeps a CRaC
  # process shutting down normally; no checkpoint exists yet when hit_urls runs in the CRaC
  # training run.
  local stop_pid="${app_pid:-}"
  local launcher_pid="${tpid:-${pid:-}}"
  if [[ -n "$stop_pid" ]] && { [[ "$stop_pid" == "$$" ]] || [[ "$stop_pid" == "$PPID" ]] || [[ "$stop_pid" == "1" ]]; }; then
    stop_pid=""
  fi
  if [[ -n "$launcher_pid" ]] && { [[ "$launcher_pid" == "$$" ]] || [[ "$launcher_pid" == "$PPID" ]] || [[ "$launcher_pid" == "1" ]]; }; then
    launcher_pid=""
  fi
  # Only kill app_pid if it is the launcher or a descendant of it (walk up at most 3 levels),
  # so a stale or pgrep -f fallback PID that belongs to some other java process is left alone.
  if [[ -n "$stop_pid" && "$stop_pid" != "$launcher_pid" ]]; then
    local walk_pid="$stop_pid" is_descendant=false
    for _ in 1 2 3; do
      walk_pid=$(ps -o ppid= -p "$walk_pid" 2>/dev/null | tr -d '[:space:]')
      [[ -z "$walk_pid" ]] && break
      if [[ -n "$launcher_pid" && "$walk_pid" == "$launcher_pid" ]]; then
        is_descendant=true
        break
      fi
    done
    if [[ "$is_descendant" != "true" ]]; then
      echo "    Skipping kill of PID $stop_pid: it is not the launcher process or one of its descendants"
      stop_pid=""
    fi
  fi
  echo "    Stopping the application after the failure ($reason)..."
  [[ -n "$stop_pid" ]] && kill -TERM "$stop_pid" 2>/dev/null
  [[ -n "$launcher_pid" ]] && kill -TERM "$launcher_pid" 2>/dev/null
  sleep 2
  [[ -n "$stop_pid" ]] && kill -0 "$stop_pid" 2>/dev/null && kill -9 "$stop_pid" 2>/dev/null
  [[ -n "$launcher_pid" ]] && kill -0 "$launcher_pid" 2>/dev/null && kill -9 "$launcher_pid" 2>/dev/null
  [[ -n "$launcher_pid" ]] && wait "$launcher_pid" 2>/dev/null
  wait_for_port_free 30

  # This runs on ANY hit_urls failure, not only in training runs: also after a failed warm-up
  # or measured run. Stopping the app can make a CDS/Leyden run write its cache from the
  # failed or broken run, so do not benchmark a bad archive.
  # - CDS: petclinic.jsa is removed so the next run retrains it. CDS skips training when the
  #   archive exists. A retrain is cheap, and compile-and-run.sh deletes the archive before
  #   every cds run anyway.
  # - Leyden: only the leftover intermediate petclinic.aotconf is removed, never
  #   petclinic.aot.
  if [[ "$LABEL" == "cds" && -f petclinic.jsa ]]; then
    rm -f petclinic.jsa
    echo "    Removed petclinic.jsa so the next run rebuilds the archive"
  elif [[ "$LABEL" == "leyden" && -f petclinic.aotconf ]]; then
    rm -f petclinic.aotconf
    echo "    Removed leftover petclinic.aotconf"
  fi
}

# ---------- function reused by warm-ups & benchmarks ----------
hit_urls() {
  # First, wait for the application to be ready by checking the root URL
  echo "    Waiting for application to be ready..."
  readiness_timeout=60
  readiness_counter=0
  local process_died=false
  while [[ $readiness_counter -lt $readiness_timeout ]]; do
    # Note: curl writes "000" on connection failure; the plain subshell captures that correctly
    # without the old "|| echo 000" that caused double-000 output
    status=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080" 2>/dev/null)
    if [[ "$status" == "200" ]]; then
      echo "    Application is ready (status: $status)"
      break
    fi
    sleep 1
    readiness_counter=$((readiness_counter + 1))
    # Fast-fail: detect if the tracked process has already exited
    local check_pid="${app_pid:-${pid:-}}"
    if [[ -n "$check_pid" ]] && ! kill -0 "$check_pid" 2>/dev/null; then
      process_died=true
      break
    fi
    if [[ $((readiness_counter % 5)) -eq 0 ]]; then
      echo "    Still waiting for application readiness... ($readiness_counter seconds elapsed, status: $status)"
    fi
  done

  if [[ $readiness_counter -ge $readiness_timeout ]] || [[ "$process_died" == "true" ]]; then
    if [[ "$process_died" == "true" ]]; then
      echo "    ❌ ERROR: Application process has exited unexpectedly."
    else
      echo "    ❌ ERROR: Application readiness timeout reached (60 seconds). Application failed to start."
    fi
    echo "    Check the log file for errors: $LOG_FILE"
    echo "    Last lines of application log:"
    tail -30 "$LOG_FILE" 2>/dev/null | sed 's/^/      /' || echo "      (log file empty or missing)"
    stop_app_after_failure "readiness failure"
    exit 1
  fi

  # Now call the actual URLs (repeated 5x to generate more garbage)
  # Status guard: every URL must return 200, except /oups (the deliberate crash demo page),
  # which must return 500. Any other status means the build is broken (e.g. a native image
  # missing reflection hints returns 500 on most pages), so the run must fail instead of
  # being timed and recorded as a success. The check applies to training runs as well.
  local unexpected=()
  local expected_status
  printf '    Calling URLs: ' # four-space indent
  for round in {1..5}; do
    for url in "${URLS[@]}"; do
      sleep 3  # Pause between URL requests
      status=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)
      printf '%s ' "$status"
      # Abort if connection failed
      if [[ "$status" == "000" ]]; then
        echo
        echo "    ❌ ERROR: Application stopped responding (HTTP status 000)"
        echo "    Check the log file for errors: $LOG_FILE"
        stop_app_after_failure "no response"
        exit 1
      fi
      expected_status="200"
      [[ "$url" == */oups ]] && expected_status="500"
      if [[ "$status" != "$expected_status" ]]; then
        unexpected+=("$url=$status")
      fi
    done
  done
  echo # newline

  if [[ ${#unexpected[@]} -gt 0 ]]; then
    local summary
    summary=$(printf '%s\n' "${unexpected[@]}" | sort | uniq -c |
      awk '{c=$1; $1=""; sub(/^ /,""); printf "%s%s (x%d)", (NR>1 ? ", " : ""), $0, c}')
    echo "    ❌ ERROR: ${#unexpected[@]} unexpected HTTP status code(s): $summary"
    echo "    Check the log file for errors: $LOG_FILE"
    echo "    Last lines of application log:"
    tail -30 "$LOG_FILE" 2>/dev/null | sed 's/^/      /' || echo "      (log file empty or missing)"
    stop_app_after_failure "unexpected HTTP status"
    exit 1
  fi
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

# Function to get current swap usage
get_swap_used() {
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: use sysctl to get swap usage
    local swap_info=$(sysctl vm.swapusage 2>/dev/null)
    if [[ $swap_info =~ used\ =\ ([0-9.]+)([MG]) ]]; then
      local value="${BASH_REMATCH[1]}"
      local unit="${BASH_REMATCH[2]}"
      # Convert to MB
      if [[ "$unit" == "G" ]]; then
        echo "$(awk "BEGIN {printf \"%.0f\", $value * 1024}")"
      else
        echo "$(awk "BEGIN {printf \"%.0f\", $value}")"
      fi
    else
      echo "0"
    fi
  else
    # Linux: use /proc/meminfo
    local swap_total=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')
    local swap_free=$(grep "^SwapFree:" /proc/meminfo | awk '{print $2}')
    if [[ -n "$swap_total" && -n "$swap_free" ]]; then
      local swap_used=$((swap_total - swap_free))
      # Convert from KB to MB
      echo "$((swap_used / 1024))"
    else
      echo "0"
    fi
  fi
}

# Function to extract PID from log file
extract_pid_from_log() {
  local log_file="$1"
  local label="$2"

  case "$label" in
  "graalvm")
    # For GraalVM, look for "Started PetClinicApplication" with PID in log level
    local line=$(grep -m1 "Started PetClinicApplication" "$log_file")
    if [[ $line =~ INFO\ ([0-9]+)\ --- ]]; then
      echo "${BASH_REMATCH[1]}"
    else
      echo ""
    fi
    ;;
  "crac")
    # For CRaC, look for "Starting PetClinicApplication" with PID in log level
    local line=$(grep -m1 "Starting PetClinicApplication" "$log_file")
    if [[ $line =~ INFO\ ([0-9]+)\ --- ]]; then
      echo "${BASH_REMATCH[1]}"
    else
      echo ""
    fi
    ;;
  *)
    # For other labels, look for "Started PetClinicApplication" with PID in log level
    local line=$(grep -m1 "Started PetClinicApplication" "$log_file")
    if [[ $line =~ INFO\ ([0-9]+)\ --- ]]; then
      echo "${BASH_REMATCH[1]}"
    else
      echo ""
    fi
    ;;
  esac
}

# Function to extract GC counts from GraalVM Native Image logs
# The native executable prints its -XX:+PrintGC / -XX:+VerboseGC output to stdout, so the GC
# lines sit in the app log next to the Spring log lines. They carry [X.XXXs] process-uptime
# stamps, so startup vs benchmark GCs split at the uptime when the app reported "Started".
# Counting rule matches extract_gc_counts for the JVM variants: every GC log line that mentions
# "Pause". G1 logs a start line and an end line per pause, so the columns count pause log
# lines (about twice the number of pauses), the same way for every variant.
extract_gc_counts_graalvm() {
  local app_log="$1"
  local gc_log="$2"

  # If GC log doesn't exist, return 0,0
  if [[ ! -f "$gc_log" ]]; then
    echo "0,0"
    return
  fi

  # GC pause lines in either format:
  #   G1 (--gc=G1): [0.472s][info][gc,start ] GC(1) Pause Young (Concurrent Start) (G1 Evacuation Pause)
  #   Serial:       [0.196s] GC(0) Pause Full GC (Collect on allocation) 32.50M->5.50M 16.560ms
  # Try the G1 format first and fall back to Serial only when it finds nothing, so a missing
  # "Using G1" header line can't silently turn the G1 counts into 0/0.
  local pause_lines
  pause_lines=$(grep -E '^\[[0-9]+\.[0-9]+s\]\[[a-z]+\]\[gc[^]]*\].*Pause' "$gc_log")
  if [[ -z "$pause_lines" ]]; then
    pause_lines=$(grep -E '^\[[0-9]+\.[0-9]+s\] .*(Pause Full GC|Pause Incremental GC)' "$gc_log")
  fi
  if [[ -z "$pause_lines" ]]; then
    echo "0,0"
    return
  fi

  # Uptime at startup, e.g. "Started PetClinicApplication in 0.615 seconds (process running
  # for 0.619)". The GC stamps are process uptime, so prefer the "process running for" value.
  local startup_time
  startup_time=$(grep -o "process running for [0-9.]\+" "$app_log" 2>/dev/null | grep -o "[0-9.]\+" | head -1)
  if [[ -z "$startup_time" ]]; then
    startup_time=$(grep -o "Started PetClinicApplication in [0-9.]\+ seconds" "$app_log" 2>/dev/null | grep -o "[0-9.]\+" | head -1)
  fi
  if [[ -z "$startup_time" ]]; then
    # Can't determine startup time, return all as benchmark GCs
    echo "0,$(printf '%s\n' "$pause_lines" | wc -l | tr -d ' ')"
    return
  fi

  local startup_count=0
  local benchmark_count=0
  while IFS= read -r line; do
    # Extract timestamp in format [X.XXXs]
    local gc_time=$(echo "$line" | grep -oE '^\[[0-9]+\.[0-9]+s\]' | grep -oE '[0-9]+\.[0-9]+')
    if [[ -n "$gc_time" ]]; then
      # Compare using awk for floating point comparison
      if awk -v gc="$gc_time" -v startup="$startup_time" 'BEGIN { exit (gc <= startup) ? 0 : 1 }'; then
        ((startup_count++))
      else
        ((benchmark_count++))
      fi
    fi
  done <<<"$pause_lines"

  echo "${startup_count},${benchmark_count}"
}

# Function to extract GC counts from logs
# Returns two numbers separated by comma: startup_gcs,benchmark_gcs
extract_gc_counts() {
  local label="$1"
  local app_log="$2"
  local gc_log="$3"

  # For GraalVM Native Image, use specialized parsing. Its GC lines are in the app log
  # (stdout), not in a separate GC log file.
  if [[ "$label" == "graalvm" ]]; then
    extract_gc_counts_graalvm "$app_log" "$app_log"
    return
  fi

  # If GC log doesn't exist, return 0,0
  if [[ ! -f "$gc_log" ]]; then
    echo "0,0"
    return
  fi

  # Get startup timestamp from app log
  local startup_line=$(grep "Started PetClinicApplication\|Spring-managed lifecycle restart completed" "$app_log" | head -1)
  if [[ -z "$startup_line" ]]; then
    echo "0,0"
    return
  fi

  # Extract timestamp
  local startup_ts=$(echo "$startup_line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' | head -1)
  if [[ -z "$startup_ts" ]]; then
    echo "0,0"
    return
  fi

  # Convert to epoch for comparison
  local startup_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${startup_ts%.*}" +%s 2>/dev/null || date -d "$startup_ts" +%s 2>/dev/null || echo "0")
  if [[ "$startup_epoch" == "0" ]]; then
    echo "0,0"
    return
  fi

  # Count GC pause events before and after startup
  local startup_count=0
  local benchmark_count=0

  while IFS= read -r line; do
    local gc_ts=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' | head -1)
    if [[ -n "$gc_ts" ]]; then
      local gc_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${gc_ts%.*}" +%s 2>/dev/null || date -d "$gc_ts" +%s 2>/dev/null || echo "0")
      if [[ "$gc_epoch" != "0" ]]; then
        if [[ $gc_epoch -lt $startup_epoch ]]; then
          ((startup_count++))
        else
          ((benchmark_count++))
        fi
      fi
    fi
  done < <(grep "Pause" "$gc_log" | grep -E "\[gc")

  echo "${startup_count},${benchmark_count}"
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

# Wait for port 8080 to be released after killing the app
wait_for_port_free() {
  local timeout="${1:-30}"
  local counter=0
  while ss -tlnp 2>/dev/null | grep -q ':8080 '; do
    sleep 1
    counter=$((counter + 1))
    if [[ $((counter % 5)) -eq 0 ]]; then
      echo "    Waiting for port 8080 to be released... (${counter}s)"
    fi
    if [[ $counter -ge $timeout ]]; then
      echo "    Warning: port 8080 still occupied after ${timeout}s, terminating"
      local stuck_pid
      stuck_pid=$(jcmd 2>/dev/null | grep -i "petclinic" | awk '{print $1}' | head -1)
      [[ -z "$stuck_pid" ]] && stuck_pid=$(pgrep -f "java .*-jar.*spring-petclinic" 2>/dev/null | head -1)
      [[ -z "$stuck_pid" ]] && stuck_pid=$(ss -tlnp 2>/dev/null | grep ':8080' | grep -oE 'pid=[0-9]+' | grep -oE '[0-9]+' | head -1)
      # Safety: refuse to kill self, parent, or init
      if [[ -n "$stuck_pid" ]] && { [[ "$stuck_pid" == "$$" ]] || [[ "$stuck_pid" == "$PPID" ]] || [[ "$stuck_pid" == "1" ]]; }; then
        echo "    WARNING: stuck PID detection returned $stuck_pid (self/parent/init); ignoring"
        stuck_pid=""
      fi
      if [[ -n "$stuck_pid" ]]; then
        echo "    Sending SIGTERM to PID $stuck_pid (preserves CRaC checkpoint integrity)"
        kill -TERM "$stuck_pid" 2>/dev/null || true
        sleep 5
        if kill -0 "$stuck_pid" 2>/dev/null; then
          echo "    Force-killing PID $stuck_pid (SIGTERM ignored)"
          kill -9 "$stuck_pid" 2>/dev/null || true
        fi
      fi
      break
    fi
  done
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

  cds_cmd="java $BASE_JVM_PARAMS_WITH_AOT -XX:ArchiveClassesAtExit=petclinic.jsa -jar $JAR_PATH"
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
  record_cmd="java $BASE_JVM_PARAMS_WITH_AOT -XX:AOTMode=record -XX:AOTConfiguration=petclinic.aotconf -jar $JAR_PATH"
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
    create_cmd="java $BASE_JVM_PARAMS_WITH_AOT -XX:AOTMode=create -XX:AOTConfiguration=petclinic.aotconf -XX:AOTCache=petclinic.aot -jar $JAR_PATH"
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
elif [[ "$LABEL" == "crac" && (! -d petclinic-crac || ! -f petclinic-crac/*.img) ]]; then
  echo "  CRaC (creates checkpoint)"

  # Check CRaC system requirements first
  if ! check_crac_requirements; then
    echo "❌ CRaC system requirements not met. Skipping CRaC benchmark."
    exit 1
  fi

  # Clean up any existing processes before starting (with proper indentation)
  cleanup_processes "    "

  # A killed or timed-out earlier checkpoint can leave a core.img.* temp file behind, which
  # would make this training run fail the completeness check. Start from a clean directory.
  if [[ -e petclinic-crac ]]; then
    echo "    Removing old checkpoint directory petclinic-crac before training"
    rm -rf petclinic-crac || { echo "    ERROR: cannot remove old checkpoint directory petclinic-crac"; exit 1; }
  fi

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

  # Wait for checkpoint to complete.
  # The warp engine (hardcoded via -XX:CRaCEngine=warp) writes the image to a temp file
  # petclinic-crac/core.img.<random>, logs "warp: Checkpoint successful!" early, but keeps
  # writing the image afterwards and renames it to core.img only when done. Sending TERM
  # before that rename gets the shutdown captured in the image, so every restore exits
  # immediately. Hence: wait for the success message, the final core.img, no temp file,
  # and a core.img size that is stable between two consecutive 1-second checks.
  echo "    Waiting for checkpoint to complete..."
  checkpoint_wait=0
  max_checkpoint_wait=120 # Raised from 60: the image is ~240 MB and written to a slow disk on small servers
  checkpoint_complete=false
  prev_core_size=-2
  while [[ $checkpoint_wait -lt $max_checkpoint_wait ]]; do
    # Check if the application process is still running
    if ! kill -0 "$app_pid" 2>/dev/null; then
      echo "    Warning: Application process $app_pid has terminated during checkpoint"
      break
    fi

    core_size=-1
    if [[ -f petclinic-crac/core.img ]]; then
      core_size=$(wc -c <petclinic-crac/core.img 2>/dev/null | tr -d '[:space:]')
      [[ "$core_size" =~ ^[0-9]+$ ]] || core_size=-1
    fi
    if grep -q "warp: Checkpoint successful!" "$LOG_FILE" 2>/dev/null &&
      [[ $core_size -gt 0 ]] &&
      ! compgen -G "petclinic-crac/core.img.*" >/dev/null &&
      [[ $core_size -eq $prev_core_size ]]; then
      echo "    Checkpoint image complete after ${checkpoint_wait}s (core.img ${core_size} bytes, size stable)"
      checkpoint_complete=true
      break
    fi
    prev_core_size=$core_size
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

  # Timed out with the application still running: the image is not complete, do not benchmark
  if [[ "$checkpoint_complete" != "true" ]] && kill -0 "$app_pid" 2>/dev/null; then
    echo "    Error: Checkpoint image was not complete after ${max_checkpoint_wait}s"
    echo "    Checkpoint directory contents:"
    ls -lh petclinic-crac 2>&1 | sed 's/^/      /'
    echo "    Last few lines of application log:"
    tail -15 "$LOG_FILE" | sed 's/^/      /'
    kill -TERM "$pid" 2>/dev/null
    kill -TERM "$app_pid" 2>/dev/null
    sleep 2
    kill -0 "$app_pid" 2>/dev/null && kill -9 "$app_pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "    CRaC training failed - skipping benchmark"
    exit 1
  fi

  # The application exited by itself (older CRaC builds do that after checkpointing):
  # re-check the completion predicate once, with one extra 1-second check for a stable size
  if [[ "$checkpoint_complete" != "true" ]]; then
    recheck_size_1=-1
    if [[ -f petclinic-crac/core.img ]]; then
      recheck_size_1=$(wc -c <petclinic-crac/core.img 2>/dev/null | tr -d '[:space:]')
      [[ "$recheck_size_1" =~ ^[0-9]+$ ]] || recheck_size_1=-1
    fi
    sleep 1
    recheck_size_2=-1
    if [[ -f petclinic-crac/core.img ]]; then
      recheck_size_2=$(wc -c <petclinic-crac/core.img 2>/dev/null | tr -d '[:space:]')
      [[ "$recheck_size_2" =~ ^[0-9]+$ ]] || recheck_size_2=-1
    fi
    if grep -q "warp: Checkpoint successful!" "$LOG_FILE" 2>/dev/null &&
      [[ $recheck_size_1 -gt 0 ]] &&
      ! compgen -G "petclinic-crac/core.img.*" >/dev/null &&
      [[ $recheck_size_1 -eq $recheck_size_2 ]]; then
      echo "    Checkpoint image complete after ${checkpoint_wait}s (core.img ${recheck_size_2} bytes, size stable)"
      checkpoint_complete=true
    else
      echo "    Error: Application exited before the checkpoint image was complete"
      echo "    Checkpoint directory contents:"
      ls -lh petclinic-crac 2>&1 | sed 's/^/      /'
      echo "    Last few lines of application log:"
      tail -15 "$LOG_FILE" | sed 's/^/      /'
      kill -TERM "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      echo "    CRaC training failed - skipping benchmark"
      exit 1
    fi
  fi

  # Verify checkpoint directory was created and has content
  if [[ -d petclinic-crac ]]; then
    if [[ "$(ls -A petclinic-crac 2>/dev/null)" ]]; then
      # Require the final core.img and no leftover core.img.* temp file (see comment above)
      non_log_files=$(find petclinic-crac -type f ! -name "*.log" 2>/dev/null | wc -l)
      if [[ -f petclinic-crac/core.img ]] && ! compgen -G "petclinic-crac/core.img.*" >/dev/null; then
        echo "    Checkpoint directory created successfully: $(ls -lh petclinic-crac)"
        echo "    Checkpoint directory contents:"
        ls -lh petclinic-crac | sed 's/^/      /'
        echo "    Non-log files found: $non_log_files"

        # Additional verification: check for "warp: Checkpoint successful!" message in log
        if grep -q "warp: Checkpoint successful!" "$LOG_FILE"; then
          echo "    ✅ Checkpoint success confirmed in application log"
        else
          echo "    Error: 'warp: Checkpoint successful!' message not found in application log"
          echo "    Last few lines of application log:"
          tail -15 "$LOG_FILE" | sed 's/^/      /'
          kill -TERM "$pid" 2>/dev/null
          wait "$pid" 2>/dev/null
          echo "    CRaC training failed - skipping benchmark"
          exit 1
        fi
      else
        echo "    Error: Checkpoint directory petclinic-crac exists but has no final core.img (or a core.img.* temp file remains)"
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
    # Hit the URLs to generate profiling data. The status guard in hit_urls also applies to
    # training runs: unexpected HTTP status codes stop the application and fail the run.
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
  # Launch application in background
  $APP_CMD >"$LOG_FILE" 2>&1 &
  pid=$!

  # Find the actual application process to kill
  if [[ "$LABEL" == "graalvm" ]]; then
    # For native executables, extract PID from log file
    echo "    Waiting for application to start and extract PID from log..."
    timeout_counter=0
    while [[ $timeout_counter -lt 30 ]]; do
      app_pid=$(extract_pid_from_log "$LOG_FILE" "$LABEL")
      if [[ -n "$app_pid" ]]; then
        echo "    Found GraalVM app process PID from log: $app_pid"
        break
      fi
      sleep 1
      timeout_counter=$((timeout_counter + 1))
    done

    # Fallback to pgrep if PID extraction failed
    if [[ -z "$app_pid" ]]; then
      echo "    Warning: Could not extract PID from log, falling back to pgrep..."
      for _ in {1..10}; do
        app_pid=$(pgrep -f "build/native/nativeCompile/spring-petclinic" | grep -v "$pid" | grep -v "$$" | grep -v "benchmark.sh" | head -1)
        [[ -n "$app_pid" ]] && break
        sleep 0.5
      done
    fi
  elif [[ "$LABEL" == "crac" ]]; then
    # The restored process has the original training cmdline (-jar spring-petclinic*),
    # not CRaCRestoreFrom. Port 8080 is not yet in LISTEN until Spring lifecycle
    # callbacks finish, so ss-based detection is deferred to after startup.
    for _ in {1..10}; do
      app_pid=$(pgrep -P "$pid" java 2>/dev/null | head -1)
      [[ -n "$app_pid" ]] && break
      app_pid=$(pgrep -f "java .*-jar.*spring-petclinic" 2>/dev/null | head -1)
      [[ -n "$app_pid" ]] && break
      sleep 0.5
    done
    # Safety: refuse to ever kill our own script, our parent shell, or PID 1
    if [[ -n "$app_pid" ]] && { [[ "$app_pid" == "$$" ]] || [[ "$app_pid" == "$PPID" ]] || [[ "$app_pid" == "1" ]]; }; then
      echo "    WARNING: PID detection returned $app_pid (self/parent/init); ignoring"
      app_pid=""
    fi
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
    # For CRaC: retry PID detection now that the restored process is fully up
    # (port 8080 is in LISTEN state and Spring lifecycle is complete)
    if [[ "$LABEL" == "crac" && -z "$app_pid" ]]; then
      app_pid=$(jcmd 2>/dev/null | grep -i "petclinic" | awk '{print $1}' | head -1)
      [[ -z "$app_pid" ]] && app_pid=$(pgrep -f "java .*-jar.*spring-petclinic" 2>/dev/null | head -1)
      [[ -z "$app_pid" ]] && app_pid=$(ss -tlnp 2>/dev/null | grep ':8080' | grep -oE 'pid=[0-9]+' | grep -oE '[0-9]+' | head -1)
      # Safety: refuse to ever kill our own script, our parent shell, or PID 1
      if [[ -n "$app_pid" ]] && { [[ "$app_pid" == "$$" ]] || [[ "$app_pid" == "$PPID" ]] || [[ "$app_pid" == "1" ]]; }; then
        echo "    WARNING: PID detection returned $app_pid (self/parent/init); ignoring"
        app_pid=""
      fi
      [[ -n "$app_pid" ]] && echo "    Found CRaC app PID after startup: $app_pid"
    fi
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
  if [[ "$LABEL" == "crac" ]]; then
    wait_for_port_free 30
  fi
done

# ---------------- Benchmark phase ---------------------
echo "Starting $RUNS benchmark runs…"
echo "Run,Startup Time (s),Max Memory (MB),Startup GCs,Benchmark GCs,Ran at,Size App (MB),Size Extra (MB)" >"$CSV_FILE"

# Capture swap usage before benchmark
SWAP_BEFORE=$(get_swap_used)
echo "Swap usage before benchmark: ${SWAP_BEFORE} MB"

declare -a times mems startup_gcs benchmark_gcs
for ((i = 1; i <= RUNS; i++)); do
  echo "  Run $i"
  set_log_file "benchmark"
  : >"$LOG_FILE"
  # Capture start timestamp in ISO 8601 format
  start_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # Launch application with time measurement
  if [[ "$(uname)" == "Darwin" ]]; then
    /usr/bin/time -l stdbuf -oL $APP_CMD >"$LOG_FILE" 2>/tmp/time_out.log &
  else
    /usr/bin/time -v -o /tmp/time_out.log stdbuf -oL $APP_CMD >"$LOG_FILE" 2>&1 &
  fi
  tpid=$!

  # Find the actual application process to kill
  if [[ "$LABEL" == "graalvm" ]]; then
    # For native executables, extract PID from log file
    echo "    Waiting for application to start and extract PID from log..."
    timeout_counter=0
    while [[ $timeout_counter -lt 30 ]]; do
      app_pid=$(extract_pid_from_log "$LOG_FILE" "$LABEL")
      if [[ -n "$app_pid" ]]; then
        echo "    Found GraalVM app process PID from log: $app_pid"
        break
      fi
      sleep 1
      timeout_counter=$((timeout_counter + 1))
    done

    # Fallback to pgrep if PID extraction failed
    if [[ -z "$app_pid" ]]; then
      echo "    Warning: Could not extract PID from log, falling back to pgrep..."
      for _ in {1..10}; do
        app_pid=$(pgrep -f "build/native/nativeCompile/spring-petclinic" | grep -v "$tpid" | grep -v "$$" | grep -v "benchmark.sh" | head -1)
        [[ -n "$app_pid" ]] && break
        sleep 0.5
      done
    fi
  elif [[ "$LABEL" == "crac" ]]; then
    # The restored process has the original training cmdline (-jar spring-petclinic*),
    # not CRaCRestoreFrom. Port 8080 is not yet in LISTEN until Spring lifecycle
    # callbacks finish, so ss-based detection is deferred to after startup.
    for _ in {1..10}; do
      app_pid=$(pgrep -P "$tpid" java 2>/dev/null | head -1)
      [[ -n "$app_pid" ]] && break
      app_pid=$(pgrep -f "java .*-jar.*spring-petclinic" 2>/dev/null | head -1)
      [[ -n "$app_pid" ]] && break
      sleep 0.5
    done
    # Safety: refuse to ever kill our own script, our parent shell, or PID 1
    if [[ -n "$app_pid" ]] && { [[ "$app_pid" == "$$" ]] || [[ "$app_pid" == "$PPID" ]] || [[ "$app_pid" == "1" ]]; }; then
      echo "    WARNING: PID detection returned $app_pid (self/parent/init); ignoring"
      app_pid=""
    fi
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
    # For CRaC: retry PID detection now that the restored process is fully up
    # (port 8080 is in LISTEN state and Spring lifecycle is complete)
    if [[ "$LABEL" == "crac" && -z "$app_pid" ]]; then
      app_pid=$(jcmd 2>/dev/null | grep -i "petclinic" | awk '{print $1}' | head -1)
      [[ -z "$app_pid" ]] && app_pid=$(pgrep -f "java .*-jar.*spring-petclinic" 2>/dev/null | head -1)
      [[ -z "$app_pid" ]] && app_pid=$(ss -tlnp 2>/dev/null | grep ':8080' | grep -oE 'pid=[0-9]+' | grep -oE '[0-9]+' | head -1)
      # Safety: refuse to ever kill our own script, our parent shell, or PID 1
      if [[ -n "$app_pid" ]] && { [[ "$app_pid" == "$$" ]] || [[ "$app_pid" == "$PPID" ]] || [[ "$app_pid" == "1" ]]; }; then
        echo "    WARNING: PID detection returned $app_pid (self/parent/init); ignoring"
        app_pid=""
      fi
      [[ -n "$app_pid" ]] && echo "    Found CRaC app PID after startup: $app_pid"
    fi
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
  if [[ "$LABEL" == "crac" ]]; then
    wait_for_port_free 30
  fi
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
  else
    # Convert KB to MB with 1 decimal place
    m_rss=$(awk "BEGIN {printf \"%.1f\", $m_rss/1024}")
  fi

  # Extract GC counts
  gc_counts=$(extract_gc_counts "$LABEL" "$LOG_FILE" "/tmp/gc_${LABEL}.log")
  startup_gc=$(echo "$gc_counts" | cut -d',' -f1)
  benchmark_gc=$(echo "$gc_counts" | cut -d',' -f2)

  # Ensure we have valid GC count values
  if [[ -z "$startup_gc" ]]; then
    startup_gc="N/A"
  fi
  if [[ -z "$benchmark_gc" ]]; then
    benchmark_gc="N/A"
  fi

  echo "$i,$s_time,$m_rss,$startup_gc,$benchmark_gc,$start_timestamp,," >>"$CSV_FILE"
  times+=("$s_time")
  mems+=("$m_rss")
  startup_gcs+=("$startup_gc")
  benchmark_gcs+=("$benchmark_gc")

  # Display memory in MB for screen output
  if [[ "$m_rss" == "N/A" ]]; then
    printf "    %ss, %s\n" "$s_time" "$m_rss"
  else
    printf "    %ss, %s MB\n" "$s_time" "$m_rss"
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
avg_startup_gc=$(trimmed_mean "${startup_gcs[@]}")
avg_benchmark_gc=$(trimmed_mean "${benchmark_gcs[@]}")

# Capture calculation timestamp in ISO 8601 format
calc_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "A,$avg_time,$avg_mem,$avg_startup_gc,$avg_benchmark_gc,$calc_timestamp,$SIZE_APP_MB,$SIZE_EXTRA_MB" >>"$CSV_FILE"

# Check swap usage after benchmark
SWAP_AFTER=$(get_swap_used)
SWAP_DELTA=$((SWAP_AFTER - SWAP_BEFORE))

echo -e "\n--- Swap Usage ---"
echo "Swap before benchmark: ${SWAP_BEFORE} MB"
echo "Swap after benchmark:  ${SWAP_AFTER} MB"
echo "Swap delta:            ${SWAP_DELTA} MB"

if [[ $SWAP_DELTA -gt 0 ]]; then
  echo "WARNING: Swap space increased by ${SWAP_DELTA} MB during benchmark!"
  echo "This indicates the system may have run out of physical memory."
elif [[ $SWAP_BEFORE -gt 0 ]]; then
  echo "Note: System started with ${SWAP_BEFORE} MB swap in use (not caused by this benchmark)"
else
  echo "OK: No swap space was used during the benchmark."
fi

# ---------------- Show results -------------------------
echo -e "\n--- Benchmark Results ---"
cat "$CSV_FILE"

#!/usr/bin/env bash
# Run all 6 Spring PetClinic benchmark scenarios remotely from a local Mac.
#
# Usage:
#   ./run-benchmarks.sh              # run all 6 scenarios
#   ./run-benchmarks.sh baseline cds # run only the listed scenarios

set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Configuration — change these as needed
# ────────────────────────────────────────────────────────────────
SSH_KEY="${SSH_KEY:-$HOME/.ssh/AWS-Better-Projects-Faster-GmbH.pem}"
SMALL_HOST="ubuntu@ec2-18-192-45-97.eu-central-1.compute.amazonaws.com"
BIG_HOST="ubuntu@ec2-18-195-174-209.eu-central-1.compute.amazonaws.com"
PROJECT_DIR="/home/ubuntu/projects/spring-petclinic"
SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o BatchMode=yes)
JAVA_TEM="25.0.3-tem"
JAVA_CRAC="25.crac-zulu"
JAVA_GRAAL="25.0.3-graal"
LOCAL_TMP="/tmp/bm-run-$(date +%Y%m%d-%H%M%S)"

# t3.2xlarge: 32 GB RAM, 8 vCPUs — hardcoded for the big server
BIG_GRAAL_JVM_ARGS="-Xmx24g"
BIG_GRAAL_HEAP="26214m"   # ~80 % of 32 GB in MB
BIG_GRAAL_PARALLELISM="8"

# ────────────────────────────────────────────────────────────────
# Scenario metadata
# ────────────────────────────────────────────────────────────────
get_display_name() {
  case "$1" in
    baseline) echo "Baseline" ;;
    tuning)   echo "Spring Boot Tuning" ;;
    cds)      echo "Class Data Sharing" ;;
    leyden)   echo "Project Leyden" ;;
    crac)     echo "CRaC" ;;
    graalvm)  echo "GraalVM Native Image" ;;
    *)        echo "$1" ;;
  esac
}

is_valid_scenario() {
  case "$1" in
    baseline|tuning|cds|leyden|crac|graalvm) return 0 ;;
    *) return 1 ;;
  esac
}

ALL_SCENARIOS=(baseline tuning cds leyden crac graalvm)

# ────────────────────────────────────────────────────────────────
# CLI: optional list of scenarios to run
# ────────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  REQUESTED=("${ALL_SCENARIOS[@]}")
else
  REQUESTED=("$@")
fi

# Validate requested scenario names
for s in "${REQUESTED[@]}"; do
  if ! is_valid_scenario "$s"; then
    echo "ERROR: Unknown scenario '${s}'. Valid: ${ALL_SCENARIOS[*]}"
    exit 1
  fi
done

# ────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

# SSH to small server and run a raw command (no SDKman sourcing)
ssh_small_raw() {
  ssh "${SSH_OPTS[@]}" "$SMALL_HOST" "$@"
}

# SSH to big server and run a raw command (no SDKman sourcing)
ssh_big_raw() {
  ssh "${SSH_OPTS[@]}" "$BIG_HOST" "$@"
}

# SSH to small server, source SDKman, switch Java, then run command.
# Usage: ssh_small_java <java_version> <bash_command>
ssh_small_java() {
  local java_version="$1"
  local cmd="$2"
  local full_cmd
  full_cmd="export SDKMAN_DIR=\"\$HOME/.sdkman\" && source \"\$HOME/.sdkman/bin/sdkman-init.sh\" && sdk use java ${java_version} 2>/dev/null && ${cmd}"
  ssh "${SSH_OPTS[@]}" "$SMALL_HOST" "bash -l -c $(printf '%q' "$full_cmd")"
}

# SSH to big server, source SDKman, switch Java, then run command.
# Usage: ssh_big_java <java_version> <bash_command>
ssh_big_java() {
  local java_version="$1"
  local cmd="$2"
  local full_cmd
  full_cmd="export SDKMAN_DIR=\"\$HOME/.sdkman\" && source \"\$HOME/.sdkman/bin/sdkman-init.sh\" && sdk use java ${java_version} 2>/dev/null && ${cmd}"
  ssh "${SSH_OPTS[@]}" "$BIG_HOST" "bash -l -c $(printf '%q' "$full_cmd")"
}

# SCP from small server → local
# Usage: scp_from_small <remote_path> <local_path>
scp_from_small() {
  local remote_path="$1"
  local local_path="$2"
  scp "${SSH_OPTS[@]}" "${SMALL_HOST}:${remote_path}" "$local_path"
}

# SCP from local → small server
# Usage: scp_to_small <local_path> <remote_path>
scp_to_small() {
  local local_path="$1"
  local remote_path="$2"
  scp "${SSH_OPTS[@]}" "$local_path" "${SMALL_HOST}:${remote_path}"
}

# SCP from big server → local
# Usage: scp_from_big <remote_path> <local_path>
scp_from_big() {
  local remote_path="$1"
  local local_path="$2"
  scp "${SSH_OPTS[@]}" "${BIG_HOST}:${remote_path}" "$local_path"
}

# SCP from local → big server
# Usage: scp_to_big <local_path> <remote_path>
scp_to_big() {
  local local_path="$1"
  local remote_path="$2"
  scp "${SSH_OPTS[@]}" "$local_path" "${BIG_HOST}:${remote_path}"
}

# ────────────────────────────────────────────────────────────────
# Scenario runners
# ────────────────────────────────────────────────────────────────

run_standard_scenario() {
  local label="$1"
  local java_version="$2"
  local display_name; display_name=$(get_display_name "$label")

  log "=== ${display_name}: start ==="
  local t_start
  t_start=$(date +%s)

  ssh_small_java "$java_version" "cd ${PROJECT_DIR} && ./compile-and-run.sh gradle ${label}"

  local t_end
  t_end=$(date +%s)
  log "=== ${display_name}: done ($(( t_end - t_start ))s) ==="

  log "Collecting result_${label}.csv from small server..."
  scp_from_small "${PROJECT_DIR}/result_${label}.csv" "${LOCAL_TMP}/result_${label}.csv"
}

run_graalvm_scenario() {
  local display_name; display_name=$(get_display_name "graalvm")
  log "=== ${display_name}: start ==="
  local t_start
  t_start=$(date +%s)

  # Step G1 — Build instrumented binary on big server
  log "[graalvm] G1: building instrumented binary on big server..."
  ssh_big_java "$JAVA_GRAAL" \
    "cd ${PROJECT_DIR} && \
     SPRING_PROFILES_ACTIVE=postgres ./gradlew \
       -Dorg.gradle.jvmargs='${BIG_GRAAL_JVM_ARGS}' \
       --build-cache --parallel \
       clean nativeCompile \
       --pgo-instrument \
       --build-args='--gc=G1' \
       --build-args='-R:MaxHeapSize=128m' \
       --build-args='-J-Xmx${BIG_GRAAL_HEAP}' \
       --build-args='--parallelism=${BIG_GRAAL_PARALLELISM}' \
       --jvm-args-native='-Xmx128m'"

  # Step G2 — Copy instrumented binary: big → local → small
  log "[graalvm] G2: copying instrumented binary big → local → small..."
  scp_from_big \
    "${PROJECT_DIR}/build/native/nativeCompile/spring-petclinic-instrumented" \
    "${LOCAL_TMP}/spring-petclinic-instrumented"

  ssh_small_raw "mkdir -p ${PROJECT_DIR}/build/native/nativeCompile"
  scp_to_small \
    "${LOCAL_TMP}/spring-petclinic-instrumented" \
    "${PROJECT_DIR}/build/native/nativeCompile/spring-petclinic-instrumented"

  # Step G3 — Training run on small server
  log "[graalvm] G3: running PGO training on small server..."
  ssh_small_java "$JAVA_GRAAL" \
    "cd ${PROJECT_DIR} && \
     ./benchmark.sh \
       build/native/nativeCompile/spring-petclinic-instrumented \
       graalvm \
       '-Dspring.aot.enabled=true' \
       training \
       '' ''"

  # Step G4 — Copy PGO profile: small → local → big
  log "[graalvm] G4: copying default.iprof small → local → big..."
  scp_from_small "${PROJECT_DIR}/default.iprof" "${LOCAL_TMP}/default.iprof"

  ssh_big_raw "mkdir -p ${PROJECT_DIR}/src/pgo-profiles/main"
  scp_to_big "${LOCAL_TMP}/default.iprof" "${PROJECT_DIR}/src/pgo-profiles/main/default.iprof"

  # Step G5 — Build optimized binary on big server
  log "[graalvm] G5: building optimized binary on big server..."
  ssh_big_java "$JAVA_GRAAL" \
    "cd ${PROJECT_DIR} && \
     SPRING_PROFILES_ACTIVE=postgres ./gradlew \
       -Dorg.gradle.jvmargs='${BIG_GRAAL_JVM_ARGS}' \
       --build-cache --parallel \
       clean nativeCompile \
       --build-args='--gc=G1' \
       --build-args='-R:MaxHeapSize=128m' \
       --build-args='-J-Xmx${BIG_GRAAL_HEAP}' \
       --build-args='--parallelism=${BIG_GRAAL_PARALLELISM}' \
       --jvm-args-native='-Xmx128m'"

  # Step G6 — Copy optimized binary: big → local → small
  log "[graalvm] G6: copying optimized binary big → local → small..."
  scp_from_big \
    "${PROJECT_DIR}/build/native/nativeCompile/spring-petclinic" \
    "${LOCAL_TMP}/spring-petclinic"

  scp_to_small \
    "${LOCAL_TMP}/spring-petclinic" \
    "${PROJECT_DIR}/build/native/nativeCompile/spring-petclinic"

  # Measure artifact sizes on small server for CSV output
  local graal_app_size graal_extra_size
  graal_app_size=$(ssh_small_raw "du -sk ${PROJECT_DIR}/build/native/nativeCompile/spring-petclinic 2>/dev/null | cut -f1 || echo 0" | awk '{printf "%.1f", $1/1024}')
  graal_extra_size=$(ssh_small_raw "du -sk ${PROJECT_DIR}/src/pgo-profiles/main/default.iprof 2>/dev/null | cut -f1 || echo 0" | awk '{printf "%.1f", $1/1024}')

  # Step G7 — Benchmark on small server
  log "[graalvm] G7: running benchmark on small server..."
  ssh_small_java "$JAVA_GRAAL" \
    "cd ${PROJECT_DIR} && \
     ./benchmark.sh \
       build/native/nativeCompile/spring-petclinic \
       graalvm \
       '-Dspring.aot.enabled=true' \
       '' \
       '${graal_app_size}' '${graal_extra_size}'"

  # Step G8 — Collect results
  log "[graalvm] G8: collecting result_graalvm.csv from small server..."
  scp_from_small "${PROJECT_DIR}/result_graalvm.csv" "${LOCAL_TMP}/result_graalvm.csv"

  local t_end
  t_end=$(date +%s)
  log "=== ${display_name}: done ($(( t_end - t_start ))s) ==="
}

# ────────────────────────────────────────────────────────────────
# Results parsing and summary table
# ────────────────────────────────────────────────────────────────

print_summary() {
  local header_scenario="Scenario"
  local header_startup="Startup (s)"
  local header_mem="Max Mem (MB)"
  local header_sgc="Startup GCs"
  local header_bgc="Benchmark GCs"

  local sep_scenario="--------------------"
  local sep_startup="------------"
  local sep_mem="-------------"
  local sep_sgc="------------"
  local sep_bgc="---------------"

  printf "\n"
  printf "%-20s | %12s | %13s | %12s | %15s\n" \
    "$header_scenario" "$header_startup" "$header_mem" "$header_sgc" "$header_bgc"
  printf "%-20s-+-%12s-+-%13s-+-%12s-+-%15s\n" \
    "$sep_scenario" "$sep_startup" "$sep_mem" "$sep_sgc" "$sep_bgc"

  for label in "${ALL_SCENARIOS[@]}"; do
    # Only print scenarios that were requested and have a result CSV
    local requested=false
    for r in "${REQUESTED[@]}"; do
      [[ "$r" == "$label" ]] && requested=true && break
    done
    [[ "$requested" == false ]] && continue

    local csv_file="${LOCAL_TMP}/result_${label}.csv"
    if [[ ! -f "$csv_file" ]]; then
      printf "%-20s | %12s | %13s | %12s | %15s\n" \
        "$(get_display_name "$label")" "N/A" "N/A" "N/A" "N/A"
      continue
    fi

    # Row A = trimmed mean: Run,Startup Time (s),Max Memory (MB),Startup GCs,Benchmark GCs,Ran at,Size App (MB),Size Extra (MB)
    local a_row
    a_row=$(grep '^A,' "$csv_file" | head -n1 || true)

    if [[ -z "$a_row" ]]; then
      printf "%-20s | %12s | %13s | %12s | %15s\n" \
        "$(get_display_name "$label")" "no row A" "N/A" "N/A" "N/A"
      continue
    fi

    # Parse CSV fields (positional — no special characters expected in values)
    local startup max_mem startup_gcs benchmark_gcs
    startup=$(echo "$a_row"      | cut -d',' -f2)
    max_mem=$(echo "$a_row"      | cut -d',' -f3)
    startup_gcs=$(echo "$a_row"  | cut -d',' -f4)
    benchmark_gcs=$(echo "$a_row"| cut -d',' -f5)

    printf "%-20s | %12s | %13s | %12s | %15s\n" \
      "$(get_display_name "$label")" "$startup" "$max_mem" "$startup_gcs" "$benchmark_gcs"
  done
  printf "\n"
  echo "Full CSV files saved in: ${LOCAL_TMP}/"
}

# ────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────

mkdir -p "$LOCAL_TMP"
log "Results directory: ${LOCAL_TMP}"
log "Scenarios to run: ${REQUESTED[*]}"
echo

TOTAL_START=$(date +%s)

for scenario in "${REQUESTED[@]}"; do
  case "$scenario" in
    baseline | tuning | cds | leyden)
      run_standard_scenario "$scenario" "$JAVA_TEM"
      ;;
    crac)
      run_standard_scenario "crac" "$JAVA_CRAC"
      ;;
    graalvm)
      run_graalvm_scenario
      ;;
  esac
  echo
done

TOTAL_END=$(date +%s)
log "All scenarios complete. Total time: $(( TOTAL_END - TOTAL_START ))s"

print_summary

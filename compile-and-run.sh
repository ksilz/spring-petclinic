#!/usr/bin/env bash
# Build Spring-Boot variants and benchmark them.
#
# Usage examples
#   ./build_and_benchmark.sh                  # gradle, all stages
#   ./build_and_benchmark.sh maven            # maven, all stages
#   ./build_and_benchmark.sh crac             # gradle, only CRaC
#   ./build_and_benchmark.sh maven leyden     # maven, only Leyden

set -euo pipefail

JAR_NAME_PART="spring-petclinic-4.0.0-SNAPSHOT"
JAR_NAME="$JAR_NAME_PART.jar"

# ────────────────────────────────────────────────────────────────
# 1. Parse CLI: build system + optional single stage label
# ────────────────────────────────────────────────────────────────
BUILD_SYS="gradle"
STAGE_FILTER=""

case "${1:-}" in
gradle | maven)
  BUILD_SYS=$1
  STAGE_FILTER=${2:-}
  ;;
"") ;; # no args
*) STAGE_FILTER=$1 ;;
esac

ALL_LABELS=(baseline tuning cds leyden crac graalvm)
REQUESTED=("${STAGE_FILTER:-${ALL_LABELS[*]}}")

# ────────────────────────────────────────────────────────────────
# 2. Tooling sanity
# ────────────────────────────────────────────────────────────────
[[ -x ./benchmark.sh ]] || {
  echo "benchmark.sh not executable"
  exit 1
}

if [[ $BUILD_SYS == gradle ]]; then
  [[ -x ./gradlew ]] || {
    echo "./gradlew not executable"
    exit 1
  }
else
  command -v mvn >/dev/null || {
    echo "'mvn' not in PATH"
    exit 1
  }
fi

# ────────────────────────────────────────────────────────────────
# 3. SDKMAN (optional)
# ────────────────────────────────────────────────────────────────
# Note: This script requires specific Java versions. Use SDKMAN to manage them:
#   sdk install java <version> && sdk use java <version>

# ────────────────────────────────────────────────────────────────
# 4. Memory calculation for GraalVM
# ────────────────────────────────────────────────────────────────
# Calculate 80% of available memory for GraalVM native-image
get_graalvm_max_heap() {
  local total_mem_mb
  if [[ "$(uname)" == "Darwin" ]]; then
    total_mem_mb=$(($(sysctl -n hw.memsize) / 1024 / 1024))
  elif [[ "$(uname)" == "Linux" ]]; then
    # /proc/meminfo reports MemTotal in KB, convert to MB
    total_mem_mb=$(awk '/MemTotal/ {print int($2/1)}' /proc/meminfo)
    total_mem_mb=$((total_mem_mb / 1024))
  else
    total_mem_mb=8192
  fi
  local heap_mb=$((total_mem_mb * 80 / 100))
  # Minimum 2048MB
  if [[ $heap_mb -lt 2048 ]]; then
    heap_mb=2048
  fi
  echo "${heap_mb}m"
}

# Get the number of available CPUs for parallel builds
get_cpu_count() {
  local cpu_count
  if [[ "$(uname)" == "Darwin" ]]; then
    cpu_count=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")
  elif [[ "$(uname)" == "Linux" ]]; then
    cpu_count=$(nproc 2>/dev/null || echo "4")
  else
    cpu_count=4
  fi
  echo "$cpu_count"
}

# Calculate size of application and extra artifacts for a variant
# Returns: "app_size_mb extra_size_mb" (space-separated, in MB with 1 decimal)
get_variant_sizes() {
  local label=$1
  local app_kb=0
  local extra_kb=0

  case "$label" in
    baseline)
      # App: JAR file, Extra: none
      if [[ -f "build/libs/${JAR_NAME}" ]]; then
        app_kb=$(du -sk "build/libs/${JAR_NAME}" | cut -f1)
      fi
      ;;
    tuning)
      # App: Extracted directory, Extra: none
      if [[ -d "${JAR_NAME%.jar}" ]]; then
        app_kb=$(du -sk "${JAR_NAME%.jar}" | cut -f1)
      fi
      ;;
    cds)
      # App: Extracted directory, Extra: CDS archive
      if [[ -d "${JAR_NAME%.jar}" ]]; then
        app_kb=$(du -sk "${JAR_NAME%.jar}" | cut -f1)
      fi
      if [[ -f "petclinic.jsa" ]]; then
        extra_kb=$(du -sk "petclinic.jsa" | cut -f1)
      fi
      ;;
    leyden)
      # App: Extracted directory, Extra: AOT cache
      if [[ -d "${JAR_NAME%.jar}" ]]; then
        app_kb=$(du -sk "${JAR_NAME%.jar}" | cut -f1)
      fi
      if [[ -f "petclinic.aot" ]]; then
        extra_kb=$(du -sk "petclinic.aot" | cut -f1)
      fi
      ;;
    crac)
      # App: JAR, Extra: checkpoint directory
      if [[ -f "build/libs/${JAR_NAME}" ]]; then
        app_kb=$(du -sk "build/libs/${JAR_NAME}" | cut -f1)
      fi
      if [[ -d "petclinic-crac" ]]; then
        extra_kb=$(du -sk "petclinic-crac" | cut -f1)
      fi
      ;;
    graalvm)
      # App: Native binary, Extra: PGO profile
      if [[ -f "build/native/nativeCompile/spring-petclinic" ]]; then
        app_kb=$(du -sk "build/native/nativeCompile/spring-petclinic" | cut -f1)
      fi
      if [[ -f "src/pgo-profiles/main/default.iprof" ]]; then
        extra_kb=$(du -sk "src/pgo-profiles/main/default.iprof" | cut -f1)
      fi
      ;;
  esac

  # Convert KB to MB with 1 decimal place
  local app_mb=$(awk "BEGIN {printf \"%.1f\", $app_kb/1024}")
  local extra_mb=$(awk "BEGIN {printf \"%.1f\", $extra_kb/1024}")

  echo "$app_mb $extra_mb"
}

GRAALVM_MAX_HEAP=$(get_graalvm_max_heap)
CPU_COUNT=$(get_cpu_count)
GRAALVM_GRADLE_ARGS="-Xmx24g"
GRAALVM_NATIVE_ARGS="-Xmx${GRAALVM_MAX_HEAP} -H:+UseG1GC"

# ────────────────────────────────────────────────────────────────
# 5. Variant metadata
# ────────────────────────────────────────────────────────────────
declare -A NAME PARAMETERS JAVA EXPECT CMD OUT_DIR JAR_PATH

NAME[baseline]="Baseline"
NAME[tuning]="Spring Boot Tuning"
NAME[cds]="Class Data Sharing"
NAME[leyden]="Project Leyden"
NAME[crac]="CRaC"
NAME[graalvm]="GraalVM Native Image"

JAVA[baseline]='25.0.1-tem'
EXPECT[baseline]='25'
JAVA[tuning]='25.0.1-tem'
EXPECT[tuning]='25'
JAVA[cds]='25.0.1-tem'
EXPECT[cds]='25'
JAVA[leyden]='25.0.1-tem'
EXPECT[leyden]='25'
JAVA[crac]='25.crac-zulu'
EXPECT[crac]='25'
JAVA[graalvm]='25.0.1-graal'
EXPECT[graalvm]='25'

JAR_PATH[baseline]="build/libs/${JAR_NAME}"
JAR_PATH[tuning]="${JAR_NAME%.jar}/${JAR_NAME}"
JAR_PATH[cds]="${JAR_NAME%.jar}/${JAR_NAME}"
JAR_PATH[leyden]="${JAR_NAME%.jar}/${JAR_NAME}"
JAR_PATH[crac]="build/libs/${JAR_NAME}"
JAR_PATH[graalvm]="build/libs/${JAR_NAME}"

PARAMETERS[baseline]='-Dspring.aot.enabled=false'
PARAMETERS[tuning]='-Dspring.aot.enabled=true'
PARAMETERS[cds]='-Dspring.aot.enabled=true -XX:SharedArchiveFile=petclinic.jsa'
PARAMETERS[leyden]='-Dspring.aot.enabled=true -XX:AOTCache=petclinic.aot'
PARAMETERS[crac]='-Dspring.aot.enabled=false -XX:CRaCCheckpointTo=petclinic-crac'
PARAMETERS[graalvm]='-Dspring.aot.enabled=true'

if [[ $BUILD_SYS == gradle ]]; then
  CMD[baseline]="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=-Xmx768m --build-cache --parallel clean bootJar"
  CMD[tuning]="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=-Xmx768m --build-cache --parallel clean bootJar && java -Djarmode=tools -jar build/libs/${JAR_NAME} extract --force"
  CMD[cds]="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=-Xmx768m --build-cache --parallel clean bootJar && java -Djarmode=tools -jar build/libs/${JAR_NAME} extract --force"
  CMD[leyden]="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=-Xmx768m --build-cache --parallel clean bootJar && java -Djarmode=tools -jar build/libs/${JAR_NAME} extract --force"
  CMD[crac]="SPRING_PROFILES_ACTIVE=postgres ./gradlew --no-daemon -Dorg.gradle.jvmargs=-Xmx768m --build-cache --parallel clean bootJar -Pcrac=true"
  if [[ "$(uname)" == "Linux" ]]; then
    CMD[graalvm]="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=\"${GRAALVM_GRADLE_ARGS}\" --build-cache --parallel clean nativeCompile --pgo-instrument --build-args='--gc=G1' --build-args='-R:MaxHeapSize=128m' --build-args='-J-Xmx${GRAALVM_MAX_HEAP}' --build-args='--parallelism=${CPU_COUNT}' --jvm-args-native=\"-Xmx128m\""
  else
    CMD[graalvm]="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=\"${GRAALVM_GRADLE_ARGS}\" --build-cache --parallel clean nativeCompile --pgo-instrument --build-args='-J-Xmx${GRAALVM_MAX_HEAP}' --build-args='--parallelism=${CPU_COUNT}' --build-args='-R:MaxHeapSize=128m' --jvm-args-native=\"-Xmx128m\""
  fi

  OUT_DIR[gradle]="build/libs"
  OUT_DIR[tuning]="${JAR_NAME%.jar}"

else # ── Maven commands ──
  MAVEN_JAR_FLAG="-DfinalName=spring-petclinic"

  CMD[baseline]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[tuning]="mvn -B clean package -DskipTests -Dspring.aot.enabled=true $MAVEN_JAR_FLAG && java -Djarmode=tools -jar target/${JAR_NAME} extract --force"
  CMD[cds]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[leyden]="mvn -B clean package -DskipTests -Dspring.aot.enabled=true $MAVEN_JAR_FLAG"
  CMD[crac]="mvn -B clean package -DskipTests -Pcrac=true $MAVEN_JAR_FLAG"
  if [[ "$(uname)" == "Linux" ]]; then
    CMD[graalvm]="mvn -B clean -Pnative -DskipTests native:compile $MAVEN_JAR_FLAG"
  else
    CMD[graalvm]="mvn -B clean -Pnative -DskipTests native:compile $MAVEN_JAR_FLAG"
  fi

  OUT_DIR[maven]="target"
  OUT_DIR[tuning]="${JAR_NAME%.jar}"
fi

# ────────────────────────────────────────────────────────────────
# 6. Main loop
# ────────────────────────────────────────────────────────────────
executed_stages=()

for label in "${REQUESTED[@]}"; do
  if [[ ! -v NAME[$label] ]]; then
    echo "Unknown label: $label"
    continue
  fi

  stage="${NAME[$label]}"
  expected="${EXPECT[$label]}"

  # ----- Java selection ---------------------------------------------------
  current_java_version=$(java --version 2>&1 | head -n1 | grep -oE '[0-9]+' | head -n1)
  java_version_output=$(java --version 2>&1)

  echo "Current Java:"
  echo "$java_version_output" | head -3
  echo

  if [[ "$label" == "graalvm" ]]; then
    if echo "$java_version_output" | grep -q "Oracle GraalVM"; then
      echo "=== $stage ($BUILD_SYS, current Java) ==="
      echo "GraalVM memory allocation: $GRAALVM_GRADLE_ARGS"
      echo
    else
      jdk="${JAVA[$label]}"
      echo "The GraalVM Native Image scenario needs GraalVM Oracle 25. But you currently run:"
      echo "$java_version_output"
      echo
      echo "If you have SDKMAN, you can install and use the needed Java version easily:"
      echo "  sdk install java $jdk && sdk use java $jdk"
      echo
      continue
    fi
  elif [[ "$label" == "crac" ]]; then
    # Check for Linux
    if [[ "$(uname)" != "Linux" ]]; then
      echo "The CRaC scenario requires Linux. But you currently run on $(uname)."
      echo
      continue
    fi

    # Check for Java 24
    if [[ "$current_java_version" != "$expected" ]]; then
      jdk="${JAVA[$label]}"
      echo "The CRaC scenario needs Java $expected. But you currently run Java $current_java_version here."
      echo
      echo "If you have SDKMAN, you can install and use the needed Java version easily:"
      echo "  sdk install java $jdk && sdk use java $jdk"
      echo
      continue
    fi

    # Check for CRaC support
    # First check if the JVM version string indicates CRaC support
    if echo "$java_version_output" | grep -q "CRaC"; then
      echo "=== $stage ($BUILD_SYS, current Java) ==="
      echo
    # Then check for CRaC-related JVM flags
    elif java -XX:+UnlockExperimentalVMOptions -XX:+PrintFlagsFinal 2>&1 | grep -q "CRaC\|checkpoint"; then
      echo "=== $stage ($BUILD_SYS, current Java) ==="
      echo
    else
      echo "The CRaC scenario requires a CRaC-enabled JVM. But your current JVM doesn't support CRaC."
      echo "Current JVM:"
      echo "$java_version_output"
      echo
      echo "You need a CRaC-enabled JVM like Azul Zulu CRaC or similar."
      echo
      continue
    fi
  elif [[ "$current_java_version" == "$expected" ]]; then
    echo "=== $stage ($BUILD_SYS, current Java) ==="
    echo
  else
    jdk="${JAVA[$label]}"
    echo "The $stage scenario needs Java $expected. But you currently run Java $current_java_version here."
    echo
    echo "If you have SDKMAN, you can install and use the needed Java version easily:"
    echo "  sdk install java $jdk && sdk use java $jdk"
    echo
    continue
  fi

  # ----- build ------------------------------------------------------------
  echo
  echo "****************************************************************"
  echo
  echo " BUILDING APPLICATION"
  echo
  echo "-> ${CMD[$label]}" | sed 's/ && / \&\& \\\n    /g'
  echo
  echo "****************************************************************"
  echo

  build_start=$(date +%s)
  eval "${CMD[$label]}"
  build_end=$(date +%s)
  build_duration=$(awk "BEGIN {print ($build_end-$build_start)}")
  printf "Build step took %.1f seconds\n" "$build_duration"

  # Clean up AOT/CDS cache if needed
  if [[ "$label" == "cds" ]]; then
    if [[ -f petclinic.jsa ]]; then
      echo "Deleting existing CDS cache: petclinic.jsa"
      rm -f petclinic.jsa
      echo
    fi
  elif [[ "$label" == "leyden" ]]; then
    if [[ -f petclinic.aot ]]; then
      echo "Deleting existing Leyden AOT cache: petclinic.aot"
      rm -f petclinic.aot
      echo
    fi
  fi

  # ----- benchmark --------------------------------------------------------
  if [[ "$label" == "graalvm" ]]; then
    # For training run, check for instrumented binary
    train_path="build/native/nativeCompile/spring-petclinic-instrumented"
    if [[ ! -f $train_path ]]; then
      echo "Expected ${train_path} not found – skipping benchmark."
      echo
      continue
    fi
    # First run: training run for PGO
    ./benchmark.sh "$train_path" "$label" "${PARAMETERS[$label]}" training "" ""
    # Move default.iprof to src/pgo-profiles/main, create dir if needed
    if [[ -f default.iprof ]]; then
      mkdir -p src/pgo-profiles/main
      mv -f default.iprof src/pgo-profiles/main/
      echo "Moved default.iprof to src/pgo-profiles/main/"
    fi
    # Rebuild optimized native image
    echo "Rebuilding optimized native image..."
    if [[ "$(uname)" == "Linux" ]]; then
      rebuild_cmd="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=\"${GRAALVM_GRADLE_ARGS}\" --build-cache --parallel clean nativeCompile --build-args='--gc=G1' --build-args='-R:MaxHeapSize=128m' --build-args='-J-Xmx${GRAALVM_MAX_HEAP}' --build-args='--parallelism=${CPU_COUNT}' --jvm-args-native=\"-Xmx128m\""
    else
      rebuild_cmd="SPRING_PROFILES_ACTIVE=postgres ./gradlew -Dorg.gradle.jvmargs=\"${GRAALVM_GRADLE_ARGS}\" --build-cache --parallel clean nativeCompile --build-args='-J-Xmx${GRAALVM_MAX_HEAP}' --build-args='--parallelism=${CPU_COUNT}' --build-args='-R:MaxHeapSize=128m' --jvm-args-native=\"-Xmx128m\""
    fi
    echo "-> $rebuild_cmd"
    echo
    rebuild_start=$(date +%s)
    eval "$rebuild_cmd"
    rebuild_end=$(date +%s)
    rebuild_duration=$(awk "BEGIN {print ($rebuild_end-$rebuild_start)}")
    printf "GraalVM rebuild took %.1f seconds\n" "$rebuild_duration"
    # Check for the optimized binary after rebuild
    jar_path="build/native/nativeCompile/spring-petclinic"
    if [[ ! -f $jar_path ]]; then
      echo "Expected ${jar_path} not found after rebuild – skipping benchmark."
      echo
      continue
    fi
    # Calculate artifact sizes for this variant
    read variant_app_size variant_extra_size <<< $(get_variant_sizes "$label")
    echo "Artifact sizes - App: ${variant_app_size} MB, Extra: ${variant_extra_size} MB"
    # Second run: actual benchmark
    ./benchmark.sh "$jar_path" "$label" "${PARAMETERS[$label]}" "" "$variant_app_size" "$variant_extra_size"
  else
    jar_path="${JAR_PATH[$label]}"
    if [[ ! -f $jar_path ]]; then
      echo "Expected ${jar_path} not found – skipping benchmark."
      echo
      continue
    fi
    # Calculate artifact sizes for this variant
    read variant_app_size variant_extra_size <<< $(get_variant_sizes "$label")
    echo "Artifact sizes - App: ${variant_app_size} MB, Extra: ${variant_extra_size} MB"
    ./benchmark.sh "$jar_path" "$label" "${PARAMETERS[$label]}" "" "$variant_app_size" "$variant_extra_size"
  fi
  executed_stages+=("$label")
  echo
done

# Only show results message if stages were executed
if [[ ${#executed_stages[@]} -gt 0 ]]; then
  csv_files=""
  for stage in "${executed_stages[@]}"; do
    # Only count CSVs that were modified in the last 5 minutes (i.e., from this run)
    if [[ -f "result_${stage}.csv" && $(find "result_${stage}.csv" -mmin -5) ]]; then
      csv_files="$csv_files result_${stage}.csv"
    fi
  done
  if [[ -n "$csv_files" ]]; then
    echo "Done. Result CSVs:$csv_files"
  fi
fi

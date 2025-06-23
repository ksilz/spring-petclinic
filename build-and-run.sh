#!/usr/bin/env bash
# Build Spring-Boot variants and benchmark them.
#
# Usage examples
#   ./build_and_benchmark.sh                  # gradle, all stages
#   ./build_and_benchmark.sh maven            # maven, all stages
#   ./build_and_benchmark.sh crac             # gradle, only CRaC
#   ./build_and_benchmark.sh maven leyden     # maven, only Leyden

set -euo pipefail

JAR_NAME="spring-petclinic-3.5.0.jar"

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
# 4. Variant metadata
# ────────────────────────────────────────────────────────────────
declare -A NAME PARAMETERS JAVA EXPECT CMD OUT_DIR

NAME[baseline]="Baseline"
NAME[tuning]="Spring Boot Tuning"
NAME[cds]="Class Data Sharing"
NAME[leyden]="Project Leyden"
NAME[crac]="CRaC"
NAME[graalvm]="GraalVM Native Image"

PARAMETERS[baseline]='-Dspring.aot.enabled=false'
PARAMETERS[tuning]='-Dspring.aot.enabled=true'
PARAMETERS[cds]='-Dspring.aot.enabled=false'
PARAMETERS[leyden]='-Dspring.aot.enabled=true'
PARAMETERS[crac]='-Dspring.aot.enabled=false'
PARAMETERS[graalvm]='-Dspring.aot.enabled=true'

JAVA[baseline]='21.0.7-tem'
EXPECT[baseline]='21'
JAVA[tuning]='21.0.7-tem'
EXPECT[tuning]='21'
JAVA[cds]='21.0.7-tem'
EXPECT[cds]='21'
JAVA[leyden]='25.ea.27-open'
EXPECT[leyden]='25'
JAVA[crac]='24.0.1-zulu-crac'
EXPECT[crac]='24'
JAVA[graalvm]='24.0.1-graalce'
EXPECT[graalvm]='24'

if [[ $BUILD_SYS == gradle ]]; then
  CMD[baseline]="./gradlew clean bootJar"
  CMD[tuning]="./gradlew clean bootJar && \
               java -Djarmode=tools -jar build/libs/${JAR_NAME} extract"
  CMD[cds]="./gradlew clean bootJar"
  CMD[leyden]="./gradlew clean bootJar"
  CMD[crac]="./gradlew clean bootJar"
  CMD[graalvm]="./gradlew clean nativeCompile"

  OUT_DIR[gradle]="build/libs"
else # ── Maven commands ──
  MAVEN_JAR_FLAG="-DfinalName=spring-petclinic"

  CMD[baseline]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[tuning]="mvn -B clean package -DskipTests -Dspring.aot.enabled=true $MAVEN_JAR_FLAG && \
               java -Djarmode=tools -jar target/${JAR_NAME} extract"
  CMD[cds]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[leyden]="mvn -B clean package -DskipTests -Dspring.aot.enabled=true $MAVEN_JAR_FLAG"
  CMD[crac]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[graalvm]="mvn -B -Pnative -DskipTests native:compile $MAVEN_JAR_FLAG"

  OUT_DIR[maven]="target"
fi

# ────────────────────────────────────────────────────────────────
# 5. Main loop
# ────────────────────────────────────────────────────────────────
for label in "${REQUESTED[@]}"; do
  if [[ ! -v NAME[$label] ]]; then
    echo "Unknown label: $label"
    continue
  fi

  stage="${NAME[$label]}"
  expected="${EXPECT[$label]}"

  # ----- Java selection ---------------------------------------------------
  current_java_version=$(java --version 2>&1 | head -n1 | grep -oE '[0-9]+' | head -n1)
  if [[ "$current_java_version" == "$expected" ]]; then
    echo "=== $stage ($BUILD_SYS, current Java) ==="
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
  echo "-> ${CMD[$label]}"
  eval "${CMD[$label]}"

  jar_path="${OUT_DIR[$BUILD_SYS]}/${JAR_NAME}"
  if [[ ! -f $jar_path ]]; then
    echo "Expected ${jar_path} not found – skipping benchmark."
    echo
    continue
  fi

  # ----- benchmark --------------------------------------------------------
  if [[ "${PARAMETERS[$label]}" == "-Dspring.aot.enabled=true" ]]; then
    ./benchmark.sh "$jar_path" "$label" -Dspring.aot.enabled=true
  else
    ./benchmark.sh "$jar_path" "$label"
  fi
  echo
done

# Only show results message if CSV files exist
if ls *_results.csv 1>/dev/null 2>&1; then
  csv_files=$(ls *_results.csv | tr '\n' ' ')
  echo "Done. Result CSVs: $csv_files"
fi

#!/usr/bin/env bash
# Build Spring-Boot variants and benchmark them.
#
# Usage examples
#   ./build_and_benchmark.sh                  # gradle, all stages
#   ./build_and_benchmark.sh maven            # maven, all stages
#   ./build_and_benchmark.sh crac             # gradle, only CRaC
#   ./build_and_benchmark.sh maven leyden     # maven, only Leyden

set -euo pipefail

JAR_NAME_PART="spring-petclinic-3.5.0"
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
# 4. Variant metadata
# ────────────────────────────────────────────────────────────────
declare -A NAME PARAMETERS JAVA EXPECT CMD OUT_DIR JAR_PATH

NAME[baseline]="Baseline"
NAME[tuning]="Spring Boot Tuning"
NAME[cds]="Class Data Sharing"
NAME[leyden]="Project Leyden"
NAME[crac]="CRaC"
NAME[graalvm]="GraalVM Native Image"

JAVA[baseline]='21.0.7-tem'
EXPECT[baseline]='21'
JAVA[tuning]='21.0.7-tem'
EXPECT[tuning]='21'
JAVA[cds]='21.0.7-tem'
EXPECT[cds]='21'
JAVA[leyden]='25.ea.28-open'
EXPECT[leyden]='25'
JAVA[crac]='24.0.1-zulu-crac'
EXPECT[crac]='24'
JAVA[graalvm]='24.0.1-graalce'
EXPECT[graalvm]='24'

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
PARAMETERS[crac]='-Dspring.aot.enabled=false'
PARAMETERS[graalvm]='-Dspring.aot.enabled=true'

if [[ $BUILD_SYS == gradle ]]; then
  CMD[baseline]="./gradlew clean bootJar"
  CMD[tuning]="./gradlew clean bootJar && java -Djarmode=tools -jar build/libs/${JAR_NAME} extract --force"
  CMD[cds]="./gradlew clean bootJar && java -Djarmode=tools -jar build/libs/${JAR_NAME} extract --force"
  CMD[leyden]="./gradlew clean bootJar && java -Djarmode=tools -jar build/libs/${JAR_NAME} extract --force"
  CMD[crac]="./gradlew clean bootJar"
  CMD[graalvm]="./gradlew clean nativeCompile"

  OUT_DIR[gradle]="build/libs"
  OUT_DIR[tuning]="${JAR_NAME%.jar}"

else # ── Maven commands ──
  MAVEN_JAR_FLAG="-DfinalName=spring-petclinic"

  CMD[baseline]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[tuning]="mvn -B clean package -DskipTests -Dspring.aot.enabled=true $MAVEN_JAR_FLAG && java -Djarmode=tools -jar target/${JAR_NAME} extract --force"
  CMD[cds]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[leyden]="mvn -B clean package -DskipTests -Dspring.aot.enabled=true $MAVEN_JAR_FLAG"
  CMD[crac]="mvn -B clean package -DskipTests $MAVEN_JAR_FLAG"
  CMD[graalvm]="mvn -B -Pnative -DskipTests native:compile $MAVEN_JAR_FLAG"

  OUT_DIR[maven]="target"
  OUT_DIR[tuning]="${JAR_NAME%.jar}"
fi

# ────────────────────────────────────────────────────────────────
# 5. Main loop
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
  echo

  if [[ "$current_java_version" == "$expected" ]]; then
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


  eval "${CMD[$label]}"

  jar_path="${JAR_PATH[$label]}"

  if [[ ! -f $jar_path ]]; then
    echo "Expected ${jar_path} not found – skipping benchmark."
    echo
    continue
  fi

  # ----- benchmark --------------------------------------------------------
  ./benchmark.sh "$jar_path" "$label" "${PARAMETERS[$label]}"
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

# Plan: CREATE-BENCHMARK-RUNNER-SCRIPT

**Branch:** create-benchmark-runner-script
**Date:** 2026-05-01

## Goal

Create `run-benchmarks.sh` in the project root. The script runs all 6 benchmark scenarios remotely from a local Mac and produces a summary table.

## Script Structure

### Top-level Configuration

Constants at the top of the script (easy to change):
- `SSH_KEY`: `~/.ssh/AWS-Better-Projects-Faster-GmbH.pem`
- `SMALL_SERVER`: `ubuntu@ec2-18-192-45-97.eu-central-1.compute.amazonaws.com`
- `BIG_SERVER`: `ubuntu@ec2-18-195-174-209.eu-central-1.compute.amazonaws.com`
- `PROJECT_DIR`: `/home/ubuntu/projects/spring-petclinic`
- `SSH_OPTS`: `-i ${SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=no`
- Java versions: `JAVA_TEM=25.0.3-tem`, `JAVA_CRAC=25.crac-zulu`, `JAVA_GRAAL=25.0.3-graal`
- `RESULTS_DIR`: local temp dir for CSVs (e.g. `/tmp/benchmark-results-<timestamp>`)

### CLI Arguments

```
Usage: ./run-benchmarks.sh [scenario...]
  No args → run all 6 scenarios
  With args → run only those scenarios (e.g. baseline crac graalvm)
```

### Helper Functions

**`ssh_small <command>`**: SSH to small server, source SDKman, run command.
**`ssh_big <command>`**: SSH to big server, source SDKman, run command.
**`ssh_small_java <java_version> <command>`**: SSH to small, source SDKman, set Java to version, run command.
**`ssh_big_java <java_version> <command>`**: SSH to big, source SDKman, set Java to version, run command.
**`scp_from_small <remote_path> <local_path>`**: Copy file from small server to Mac.
**`scp_to_small <local_path> <remote_path>`**: Copy file from Mac to small server.
**`scp_from_big <remote_path> <local_path>`**: Copy file from big server to Mac.
**`scp_to_big <local_path> <remote_path>`**: Copy file from Mac to big server.

SDKman source snippet (all SSH functions include it):
```bash
export SDKMAN_DIR="$HOME/.sdkman"
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk use java <version> 2>/dev/null
```

### Non-GraalVM Scenarios (baseline, tuning, cds, leyden, crac)

For each scenario:
1. SSH to small server with correct Java version:
   - `baseline`, `tuning`, `cds`, `leyden` → Java `25.0.3-tem`
   - `crac` → Java `25.crac-zulu`
2. In project dir: `./compile-and-run.sh gradle <label>`
3. Wait for completion (long-running — 10–30 min each)
4. SCP `result_<label>.csv` from small server to `$RESULTS_DIR/`

### GraalVM Scenario

Multi-step workflow split between big server (compile) and small server (run):

**Step G1 — Build instrumented binary on big server:**
```bash
ssh_big_java 25.0.3-graal "cd $PROJECT_DIR && \
  SPRING_PROFILES_ACTIVE=postgres ./gradlew \
  -Dorg.gradle.jvmargs='-Xmx24g' --build-cache --parallel \
  clean nativeCompile --pgo-instrument \
  --build-args='--gc=G1' \
  --build-args='-R:MaxHeapSize=128m' \
  --build-args='-J-Xmx<80%_ram>m' \
  --build-args='--parallelism=<cpu_count>' \
  --jvm-args-native='-Xmx128m'"
```
Output: `$PROJECT_DIR/build/native/nativeCompile/spring-petclinic-instrumented`

**Step G2 — Copy instrumented binary: big → Mac → small:**
```
scp_from_big <PROJECT_DIR>/build/native/nativeCompile/spring-petclinic-instrumented /tmp/graalvm-instrumented
ssh_small "mkdir -p $PROJECT_DIR/build/native/nativeCompile"
scp_to_small /tmp/graalvm-instrumented <PROJECT_DIR>/build/native/nativeCompile/spring-petclinic-instrumented
```

**Step G3 — Run training on small server:**
```bash
ssh_small_java 25.0.3-graal "cd $PROJECT_DIR && \
  ./benchmark.sh \
    build/native/nativeCompile/spring-petclinic-instrumented \
    graalvm \
    '-Dspring.aot.enabled=true' \
    training \
    '' ''"
```
Output: `$PROJECT_DIR/default.iprof`

**Step G4 — Copy PGO profile: small → Mac → big:**
```
scp_from_small <PROJECT_DIR>/default.iprof /tmp/default.iprof
ssh_big "mkdir -p $PROJECT_DIR/src/pgo-profiles/main"
scp_to_big /tmp/default.iprof <PROJECT_DIR>/src/pgo-profiles/main/default.iprof
```

**Step G5 — Build optimized binary on big server:**
```bash
ssh_big_java 25.0.3-graal "cd $PROJECT_DIR && \
  SPRING_PROFILES_ACTIVE=postgres ./gradlew \
  -Dorg.gradle.jvmargs='-Xmx24g' --build-cache --parallel \
  clean nativeCompile \
  --build-args='--gc=G1' \
  --build-args='-R:MaxHeapSize=128m' \
  --build-args='-J-Xmx<80%_ram>m' \
  --build-args='--parallelism=<cpu_count>'"
```
Output: `$PROJECT_DIR/build/native/nativeCompile/spring-petclinic`

**Step G6 — Copy optimized binary: big → Mac → small:**
```
scp_from_big <PROJECT_DIR>/build/native/nativeCompile/spring-petclinic /tmp/graalvm-optimized
scp_to_small /tmp/graalvm-optimized <PROJECT_DIR>/build/native/nativeCompile/spring-petclinic
```

**Step G7 — Run benchmark on small server:**
```bash
ssh_small_java 25.0.3-graal "cd $PROJECT_DIR && \
  ./benchmark.sh \
    build/native/nativeCompile/spring-petclinic \
    graalvm \
    '-Dspring.aot.enabled=true' \
    '' \
    '<app_size_mb>' '<extra_size_mb>'"
```
Output: `$PROJECT_DIR/result_graalvm.csv`

**Step G8 — Retrieve results:**
```
scp_from_small <PROJECT_DIR>/result_graalvm.csv <RESULTS_DIR>/result_graalvm.csv
```

### Results Summary

After all scenarios complete:
1. For each CSV file in `$RESULTS_DIR/`:
   - Find row starting with `A,` (trimmed mean)
   - Parse: startup time, max memory, startup GCs, benchmark GCs
2. Print formatted table:

```
Scenario             | Startup (s) | Max Mem (MB) | Startup GCs | Benchmark GCs
---------------------|-------------|--------------|-------------|---------------
Baseline             |         2.1 |          512 |           3 |             7
Spring Boot Tuning   |         1.8 |          498 |           2 |             5
CDS                  |         1.2 |          490 |           1 |             4
Leyden               |         1.0 |          485 |           0 |             3
CRaC                 |         0.2 |          470 |           0 |             2
GraalVM Native Image |         0.1 |           75 |           0 |             0
```

## Execution Flow

```
run-benchmarks.sh
  ├── [baseline]  → SSH small (Java 25.0.3-tem) → compile-and-run.sh gradle baseline
  ├── [tuning]    → SSH small (Java 25.0.3-tem) → compile-and-run.sh gradle tuning
  ├── [cds]       → SSH small (Java 25.0.3-tem) → compile-and-run.sh gradle cds
  ├── [leyden]    → SSH small (Java 25.0.3-tem) → compile-and-run.sh gradle leyden
  ├── [crac]      → SSH small (Java 25.crac-zulu) → compile-and-run.sh gradle crac
  ├── [graalvm]   → big: build instrumented
  │                → big→Mac→small: copy instrumented
  │                → small: benchmark.sh training → default.iprof
  │                → small→Mac→big: copy default.iprof
  │                → big: build optimized
  │                → big→Mac→small: copy optimized binary
  │                → small: benchmark.sh → result_graalvm.csv
  └── Summary table from all result_*.csv row A
```

## Files Changed

- **New**: `run-benchmarks.sh` in project root (executable)

## Notes

- `set -euo pipefail` for error handling
- Each scenario step logs to stdout with timestamps
- `compile-and-run.sh` handles Java version validation; if Java is wrong, it prints a message and skips. So pre-setting Java via SDKman is critical.
- SDKman's `sdk use java` only works within the same shell session — must source SDKman in every SSH command
- GraalVM memory args: dynamically calculated on big server via `get_graalvm_max_heap` equivalent or hardcoded to `24g` for t3.2xlarge (32 GB RAM)

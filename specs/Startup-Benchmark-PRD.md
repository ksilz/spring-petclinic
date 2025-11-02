# Spring Boot Startup Benchmark System

## Overview

A benchmarking system for measuring Spring Boot application startup performance across five optimization techniques. Two coordinated bash scripts automate building, training, and performance measurement of Spring PetClinic variants.

**Components**:
- **compile-and-run.sh** - Orchestrates build → train → measure workflow
- **benchmark.sh** - Executes training runs, warm-ups, and performance measurements

## Optimization Variants

| Variant | Description | Startup Time | Java Version |
|---------|-------------|--------------|--------------|
| baseline | Standard Spring Boot (AOT disabled) | ~3-5s | 25 |
| tuning | Spring Boot with AOT enabled | ~2-4s | 25 |
| cds | Class Data Sharing with AOT | ~1.5-3s | 25 |
| leyden | OpenJDK Leyden AOT cache | ~1-2s | 25 |
| crac | Coordinated Restore at Checkpoint | ~0.5-1s | 25 (CRaC-enabled) |
| graalvm | Native image with PGO | ~0.3-0.8s | 25 (GraalVM) |

---

## compile-and-run.sh

### Usage

```bash
# Run all stages with Gradle (default)
./compile-and-run.sh

# Run specific stage
./compile-and-run.sh crac
./compile-and-run.sh graalvm

# Use Maven
./compile-and-run.sh maven leyden
```

### Workflow

For each variant:

1. **Validate Java Version**
   - Check current Java matches required version
   - Display SDKMAN install commands if mismatch
   - Skip variant if incompatible

2. **Build**
   - Execute Gradle/Maven build command
   - Extract JAR layers for tuning/cds/leyden variants
   - Clean existing caches (CDS/Leyden)

3. **Benchmark**
   - Call `benchmark.sh` with appropriate parameters
   - For GraalVM: Run training → rebuild with PGO → benchmark

4. **Report Results**
   - Display CSV file names for executed stages

### Key Features

**Java Version Requirements**:
- Detects version mismatches
- Provides exact SDKMAN commands for installation
- Special validation for GraalVM (checks for "Oracle GraalVM") and CRaC (Linux only, checks for CRaC support)

**GraalVM PGO Workflow**:
```bash
# 1. Build instrumented binary
./gradlew -Dorg.gradle.jvmargs="-Xmx24g" \
  nativeCompile --pgo-instrument \
  --build-args='-J-Xmx${GRAALVM_MAX_HEAP}' \
  --build-args='--parallelism=4' \
  --build-args='-R:MaxHeapSize=128m' \
  --jvm-args-native="-Xmx128m"

# 2. Run training to generate profile
./benchmark.sh <instrumented-binary> graalvm <params> training
# Generates default.iprof

# 3. Move profile to source directory
mv default.iprof src/pgo-profiles/main/

# 4. Rebuild with profile (using PGO data)
./gradlew -Dorg.gradle.jvmargs="-Xmx24g" \
  nativeCompile \
  --build-args='-J-Xmx${GRAALVM_MAX_HEAP}' \
  --build-args='--parallelism=4' \
  --build-args='-R:MaxHeapSize=128m' \
  --jvm-args-native="-Xmx128m"

# Linux also includes: --build-args='--gc=G1'

# 5. Benchmark optimized binary
./benchmark.sh <optimized-binary> graalvm <params>
```

**GraalVM Build Parameters**:
- `--pgo-instrument`: Creates instrumented binary for profiling
- `-J-Xmx${GRAALVM_MAX_HEAP}`: JVM heap for native-image build process (85% of system memory)
- `--parallelism=4`: Uses 4 parallel compilation threads
- `-R:MaxHeapSize=128m`: Runtime heap limit for the native binary
- `--jvm-args-native="-Xmx128m"`: JVM args passed to the native binary at runtime
- `--gc=G1`: Use G1 GC (Linux only, not supported on macOS)

**Memory Configuration** (GraalVM):
- Dynamically calculates 85% of system memory for native-image build process
- Bounds: 2048 MB minimum, 131072 MB maximum
- Gradle JVM: 24 GB (`-Xmx24g`)
- Native-image build process: calculated value (`-J-Xmx${GRAALVM_MAX_HEAP}`)
- Native binary runtime: 128 MB (`-R:MaxHeapSize=128m`, enforced via `--jvm-args-native="-Xmx128m"`)

**Platform Detection**:
- Linux: Includes `--gc=G1` for GraalVM
- macOS: Excludes G1 flag
- CRaC: Linux only (requires kernel support)

---

## benchmark.sh

### Usage

```bash
# Standard benchmark
./benchmark.sh <JAR_PATH> <LABEL> [JVM_PARAMS]

# GraalVM training
./benchmark.sh <JAR_PATH> graalvm <PARAMS> training

# Auto-detects need for CDS/Leyden/CRaC training
```

### Parameters

| Param | Description | Example |
|-------|-------------|---------|
| JAR_PATH | Path to JAR or binary | `build/libs/spring-petclinic-3.5.0.jar` |
| LABEL | Variant identifier | `baseline`, `crac`, `graalvm` |
| JVM_PARAMS | Runtime parameters | `-Dspring.aot.enabled=true` |
| TRAINING_MODE | Optional training flag | `training` |

### Workflow

#### 1. Training Runs (if needed)

**IMPORTANT**: All training runs MUST use the same Java parameters as production/benchmark runs for consistency. Training-specific flags are added to the standard parameter set.

**CDS Training**:
```bash
# Run with archive creation - uses same heap/GC settings as production
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_cds.log:time,uptime,level,tags \
  -Dspring.aot.enabled=true \
  -Dspring.profiles.active=postgres \
  -XX:ArchiveClassesAtExit=petclinic.jsa -jar <JAR>

# Wait for startup → hit URLs → terminate
# Output: petclinic.jsa (~50-100 MB)
```

**Leyden Training** (2-step):
```bash
# Step 1: Record AOT configuration - uses same heap/GC settings
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_leyden.log:time,uptime,level,tags \
  -Dspring.aot.enabled=true \
  -Dspring.profiles.active=postgres \
  -XX:AOTMode=record -XX:AOTConfiguration=petclinic.aotconf -jar <JAR>

# Step 2: Create AOT cache from configuration - uses same heap/GC settings
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_leyden.log:time,uptime,level,tags \
  -Dspring.aot.enabled=true \
  -Dspring.profiles.active=postgres \
  -XX:AOTMode=create \
  -XX:AOTConfiguration=petclinic.aotconf \
  -XX:AOTCache=petclinic.aot -jar <JAR>

# Output: petclinic.aot (~100-200 MB)
```

**CRaC Training**:
```bash
# 1. Start application - uses full heap/GC settings for fresh JVM start
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_crac.log:time,uptime,level,tags \
  -Dspring.aot.enabled=false \
  -Dspring.profiles.active=postgres \
  -Dspring.datasource.hikari.allow-pool-suspension=true \
  -XX:CRaCCheckpointTo=petclinic-crac \
  -XX:CRaCEngine=warp -jar <JAR>

# 2. Wait for startup → hit URLs

# 3. Take checkpoint
jcmd <PID> JDK.checkpoint

# 4. Wait for checkpoint completion
# Output: petclinic-crac/ directory (~500 MB - 1 GB)
```

**GraalVM Training**:
```bash
# Run instrumented binary (native binary doesn't use JVM heap params)
# Memory is controlled via build-time settings: -R:MaxHeapSize=128m
./spring-petclinic-instrumented -Dspring.profiles.active=postgres

# Wait for startup → hit URLs → terminate
# Output: default.iprof (~10-50 MB)
# Moved to src/pgo-profiles/main/ by compile-and-run.sh
```

#### 2. Warm-up Phase

- Executes **3 warm-up runs**
- Stabilizes JVM and primes caches
- Each run: start → wait for ready → hit URLs → terminate

#### 3. Benchmark Phase

- Executes **7 benchmark runs**
- Measures startup time, memory, and GC counts for each run
- Tracks swap usage before and after benchmark
- Writes results to CSV

**Measurement Process**:
```bash
# Capture swap usage before benchmark
SWAP_BEFORE=$(get_swap_used)

# Start with time measurement
/usr/bin/time -v $APP_CMD &

# Extract startup time from log
# Standard: "Started PetClinicApplication in X.XXX seconds"
# CRaC: "Spring-managed lifecycle restart completed"
#       and "restored JVM running for X ms"

# Hit URLs to load application (11 URLs x 5 rounds = 55 requests)

# Terminate and extract memory
# Linux: "Maximum resident set size (kbytes)"
# macOS: "peak memory footprint" (bytes → KB)

# Extract GC counts from /tmp/gc_${LABEL}.log
# - Startup GCs: pauses before "Started PetClinicApplication"
# - Benchmark GCs: pauses after startup

# Check swap usage after benchmark
SWAP_AFTER=$(get_swap_used)
SWAP_DELTA=$((SWAP_AFTER - SWAP_BEFORE))

# Write to CSV: Run,Startup Time,Memory,Startup GCs,Benchmark GCs,Timestamp
```

#### 4. Statistical Analysis

**Trimmed Mean**:
- Removes min and max values (outliers)
- Calculates average of remaining runs
- Requires minimum 3 data points
- Written as row "A" in CSV

### URL Load Simulation

**11 endpoints tested** (repeated 5x for more garbage generation):
- Owner search and pagination
- Owner details
- Vet listings with pagination
- Error page

**Execution**:
- 60-second readiness check (HTTP 200 on root)
- 1-second pause between URLs
- 11 URLs × 5 rounds = 55 total requests
- Total execution: ~55 seconds

### Process Management

**Cleanup Strategy**:
- Kills existing `spring-petclinic` processes before warm-ups
- Prevents port conflicts (8080)

**PID Tracking** (variant-specific):
- GraalVM: Extract from Spring Boot log or pgrep by binary name
- CRaC: Search for process with `CRaCRestoreFrom` parameter
- Standard: Find Java child process

**Termination**:
1. Graceful: `kill -TERM <PID>` + 1-2s wait (varies by variant)
2. Force: `kill -9 <PID>` if still running after graceful attempt

---

## Output Files

### Build Artifacts

| File/Directory | Size | Description |
|----------------|------|-------------|
| `build/libs/*.jar` | 50-100 MB | Application JAR |
| `petclinic.jsa` | 50-100 MB | CDS cache |
| `petclinic.aot` | 100-200 MB | Leyden AOT cache |
| `petclinic.aotconf` | 1-5 MB | Leyden configuration (intermediate, deleted after use) |
| `petclinic-crac/` | 500 MB - 1 GB | CRaC checkpoint directory |
| `build/native/nativeCompile/spring-petclinic` | 100-150 MB | GraalVM optimized binary |
| `build/native/nativeCompile/spring-petclinic-instrumented` | 100-150 MB | GraalVM instrumented binary (for training) |
| `src/pgo-profiles/main/default.iprof` | 10-50 MB | GraalVM PGO profile |
| `/tmp/gc_*.log` | 1-10 MB | GC logs per variant |
| `/tmp/app_*.log` | 1-10 MB | Application logs per phase |

### Benchmark Results

**CSV Format** (`result_{label}.csv`):
```csv
Run,Startup Time (s),Max Memory (KB),Startup GCs,Benchmark GCs,Ran at
1,0.352,156432,5,12,2025-11-02T10:15:23Z
2,0.341,154288,4,11,2025-11-02T10:16:45Z
...
7,0.361,157088,5,13,2025-11-02T10:24:12Z
A,0.353,155968,4.8,11.8,2025-11-02T10:24:15Z  # Trimmed mean
```

**Columns**:
- **Run**: Run number (1-7) or "A" for average
- **Startup Time (s)**: Seconds from process start to "Started PetClinicApplication"
- **Max Memory (KB)**: Peak memory footprint in kilobytes
- **Startup GCs**: Number of garbage collection pauses during startup
- **Benchmark GCs**: Number of GC pauses during URL load simulation
- **Ran at**: ISO 8601 timestamp when the run started

---

## Platform Compatibility

| Variant | Linux | macOS | Windows |
|---------|-------|-------|---------|
| baseline, tuning, cds, leyden | ✅ | ✅ | ❌ |
| crac | ✅ | ❌ | ❌ |
| graalvm | ✅ | ✅ | ❌ |

**CRaC Requirements** (Linux only):
- CRIU installed (`apt install criu`)
- Java 25 with CRaC support (e.g., Azul Zulu CRaC)
- Either root privileges OR CRaCEngine=warp

**GraalVM Platform Differences**:
- Linux: Uses `--gc=G1` flag
- macOS: Excludes G1 flag

---

## Parameter Consistency Strategy

### Overview

Training and benchmark runs use **shared parameter variables** to ensure consistency across all variants. The benchmark.sh script defines these variables at the top to minimize drift and configuration errors.

### Parameter Variables

```bash
# Base JVM parameters (without AOT)
BASE_JVM_PARAMS="-Xms256m -Xmx768m -XX:+UseG1GC -Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags -Dspring.profiles.active=postgres"

# Base JVM parameters with AOT enabled
BASE_JVM_PARAMS_WITH_AOT="-Xms256m -Xmx768m -XX:+UseG1GC -Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags -Dspring.aot.enabled=true -Dspring.profiles.active=postgres"

# CRaC Training: Includes GC for fresh JVM start with full heap/GC configuration
CRAC_TRAINING_PARAMS="-Xms256m -Xmx768m -XX:+UseG1GC -Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags -Dspring.aot.enabled=false -Dspring.profiles.active=postgres -Dspring.datasource.hikari.allow-pool-suspension=true"

# CRaC Restore: NO -XX:+UseG1GC flag (GC config restored from checkpoint), but still logs GC
CRAC_RESTORE_PARAMS="-Xms256m -Xmx768m -Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags -Dspring.aot.enabled=false -Dspring.profiles.active=postgres -Dspring.datasource.hikari.allow-pool-suspension=true"

# GraalVM: Native binary (uses native image GC logging, no JVM heap params)
GRAALVM_PARAMS="-Dspring.profiles.active=postgres"
```

### Consistency Rules

#### ✅ Variants with Identical Training/Benchmark Parameters

These variants use **identical base parameters** for both training and benchmark runs:

1. **Baseline & Tuning** - Use `BASE_JVM_PARAMS` with AOT flag toggle
2. **CDS** - Uses `BASE_JVM_PARAMS_WITH_AOT` + archive-specific flags
3. **Leyden** - Uses `BASE_JVM_PARAMS_WITH_AOT` + AOT mode flags
4. **GraalVM** - Uses `GRAALVM_PARAMS` for both instrumented and optimized binaries

**Rationale:** These variants load cached/compiled artifacts but the JVM starts fresh, so all parameters can and should match.

#### ❌ CRaC: Training ≠ Benchmark (Technical Constraint)

CRaC is **the only variant** where training and benchmark parameters differ:

| Phase | Parameters | Reason |
|-------|-----------|--------|
| **Training** (Checkpoint) | `CRAC_TRAINING_PARAMS`<br/>Includes `-XX:+UseG1GC` | Fresh JVM start requires full heap/GC configuration |
| **Benchmark** (Restore) | `CRAC_RESTORE_PARAMS`<br/>NO `-XX:+UseG1GC` | GC configuration is restored from checkpoint state;<br/>specifying GC flags would conflict with restored state |

**Technical Background:**
- During checkpoint creation, the entire JVM state (heap, GC configuration, thread state) is serialized
- During restore, this state is loaded back into memory
- The GC algorithm and configuration are **part of the checkpointed state** and cannot be overridden
- Heap size parameters are included for clarity but the actual heap state comes from the checkpoint

---

## Configuration

### Runtime Parameters

**Parameter Consistency Requirement**: Training runs and production/benchmark runs MUST use identical Java parameters (heap size, GC settings, system properties) except where technical constraints require differences (CRaC restore). Only training-specific operational flags (e.g., `-XX:ArchiveClassesAtExit`, `-XX:AOTMode=record`) differ between training and production modes.

**Common Settings**:
- Heap: `-Xms256m -Xmx768m` (JVM variants only)
- GC: `-XX:+UseG1GC` (except CRaC restore)
- GC Logging: `-Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags`
- Profile: `-Dspring.profiles.active=postgres`

```bash
# baseline
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_baseline.log:time,uptime,level,tags \
  -Dspring.profiles.active=postgres \
  -Dspring.aot.enabled=false -jar <JAR>

# tuning
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_tuning.log:time,uptime,level,tags \
  -Dspring.profiles.active=postgres \
  -Dspring.aot.enabled=true -jar <JAR>

# cds
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_cds.log:time,uptime,level,tags \
  -Dspring.profiles.active=postgres \
  -Dspring.aot.enabled=true \
  -XX:SharedArchiveFile=petclinic.jsa -jar <JAR>

# leyden
java -Xms256m -Xmx768m -XX:+UseG1GC \
  -Xlog:gc*:file=/tmp/gc_leyden.log:time,uptime,level,tags \
  -Dspring.profiles.active=postgres \
  -Dspring.aot.enabled=true \
  -XX:AOTCache=petclinic.aot -jar <JAR>

# crac (restore)
# NOTE: NO -XX:+UseG1GC flag - GC configuration restored from checkpoint
java -Xms256m -Xmx768m \
  -Xlog:gc*:file=/tmp/gc_crac.log:time,uptime,level,tags \
  -Dspring.profiles.active=postgres \
  -Dspring.aot.enabled=false \
  -Dspring.datasource.hikari.allow-pool-suspension=true \
  -XX:CRaCRestoreFrom=petclinic-crac \
  -XX:CRaCEngine=warp

# graalvm (native)
# Memory controlled at build time: -R:MaxHeapSize=128m
./spring-petclinic -Dspring.profiles.active=postgres
```

### Benchmark Configuration

```bash
WARMUPS=3     # Number of warm-up runs
RUNS=7        # Number of benchmark runs
```

---

## Troubleshooting

### Common Issues

**Java version mismatch**:
```bash
sdk install java 25-tem
sdk use java 25-tem
```

**CRIU not installed** (CRaC):
```bash
sudo apt install criu
```

**Port 8080 in use**:
```bash
pkill -f "spring-petclinic"
```

**GraalVM out of memory**:
- Reduce heap in script or free up system memory
- Minimum 8 GB RAM recommended

### Debug Logs

```bash
# Application logs (different for each phase)
cat /tmp/app_training.log    # Training runs
cat /tmp/app_warmup.log       # Warm-up runs
cat /tmp/app_benchmark.log    # Benchmark runs

# GC logs (per variant)
cat /tmp/gc_baseline.log
cat /tmp/gc_tuning.log
cat /tmp/gc_cds.log
cat /tmp/gc_leyden.log
cat /tmp/gc_crac.log
cat /tmp/gc_graalvm.log

# Time command output
cat /tmp/time_out.log

# CRaC checkpoint
cat /tmp/jcmd.log
```

### Verify Artifacts

```bash
ls -lh petclinic.jsa                          # CDS
ls -lh petclinic.aot                          # Leyden
ls -lh petclinic-crac/                        # CRaC
ls -lh build/native/nativeCompile/            # GraalVM
```

---

## Performance Expectations

### Typical Execution Times

| Variant | Build | Training | Benchmark (3 warm + 7 runs) | Total |
|---------|-------|----------|------------------------------|-------|
| baseline | 30-60s | - | 5-10 min | 6-11 min |
| tuning | 30-60s | - | 5-10 min | 6-11 min |
| cds | 30-60s | 30-45s | 4-8 min | 5-10 min |
| leyden | 30-60s | 60-120s | 3-6 min | 4-9 min |
| crac | 30-60s | 45-90s | 2-5 min | 3-7 min |
| graalvm | 60-120s | 90s + rebuild 120-300s | 1-3 min | 5-10 min |

### Resource Requirements

- **Memory**: 2-4 GB (standard), 8-16 GB (GraalVM)
- **Disk**: 10 GB recommended
- **CPU**: 2-4 cores (standard), 4-8 cores (GraalVM)

---

## Advanced Features

### GC Monitoring

All JVM-based variants log garbage collection activity to `/tmp/gc_${LABEL}.log` using the JVM's unified logging system:

```bash
-Xlog:gc*:file=/tmp/gc_${LABEL}.log:time,uptime,level,tags
```

The benchmark script automatically:
- Counts GC pauses during startup (before "Started PetClinicApplication")
- Counts GC pauses during benchmark phase (after startup)
- Records both counts in the CSV output

**Note**: CRaC restore includes GC logging (`-Xlog:gc*`) even though it omits the `-XX:+UseG1GC` flag, because the GC configuration is restored from the checkpoint but we still want to log its activity.

### Swap Usage Monitoring

The benchmark script tracks system swap usage to detect memory pressure:

**macOS**: Uses `sysctl vm.swapusage` to read swap metrics
**Linux**: Reads `/proc/meminfo` for `SwapTotal` and `SwapFree`

After each benchmark completes, the script displays:
```
--- Swap Usage ---
Swap before benchmark: 0 MB
Swap after benchmark:  0 MB
Swap delta:            0 MB
OK: No swap space was used during the benchmark.
```

If swap usage increased during the benchmark, it indicates the system ran out of physical memory, which may affect benchmark accuracy.

### Log File Management

The benchmark script uses separate log files for different phases:

- **Training**: `/tmp/app_training.log` - For CDS/Leyden/CRaC checkpoint creation
- **Warmup**: `/tmp/app_warmup.log` - For warm-up runs
- **Benchmark**: `/tmp/app_benchmark.log` - For actual benchmark measurements

This separation helps with debugging by isolating output from different phases.

### CRaC System Requirements Check

For CRaC benchmarks, the script performs comprehensive pre-flight checks:

1. **Platform**: Confirms Linux (kernel support required)
2. **CRIU**: Verifies CRIU is installed with version detection
3. **Privileges**: Checks for root or appropriate capabilities
4. **Capabilities**: Uses `capsh` to verify `CAP_SYS_ADMIN` if available

If requirements aren't met, the script provides detailed installation instructions for multiple Linux distributions.

### Enhanced Process Tracking and Debugging

The benchmark script includes extensive debugging output and process tracking:

**Debug Output**:
```bash
DEBUG: Script started with parameters:
  JAR_PATH: build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar
  LABEL: baseline
  AOT_FLAG: -Dspring.aot.enabled=false
  TRAINING_MODE:
  SCRIPT_START_TIME: 1730544123
  PID: 12345
```

**Process Discovery**:
- GraalVM: Extracts PID from Spring Boot log, falls back to pgrep with timing checks
- CRaC: Looks for process with `CRaCRestoreFrom` parameter, validates checkpoint creation
- Standard: Finds Java child process of background shell

**Checkpoint Verification** (CRaC):
- Waits up to 60 seconds for checkpoint completion
- Validates checkpoint directory contains non-log files
- Checks for "warp: Checkpoint successful!" message in logs
- Shows detailed error messages with log excerpts if checkpoint fails

**Timeout Handling**:
- Training runs: 30-120 second timeouts with progress updates
- Benchmark runs: 60 second timeouts for startup
- Periodic status messages every 5-10 seconds during long operations

---

## Known Limitations

1. **Leyden** - May cause system hangs on Linux during AOT cache generation
2. **CRaC** - Linux only, requires CRIU, complex process tracking
3. **GraalVM** - Memory intensive, long build times, platform-specific flags
4. **Fixed timings** - 1-second delays between URLs, 3 warm-ups, 7 runs (not configurable via CLI)
5. **No Windows support** - Linux/macOS only
6. **Swap warnings** - Benchmarks warn if swap usage increases during testing (indicates memory pressure)

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
./gradlew nativeCompile --pgo-instrument

# 2. Run training to generate profile
./benchmark.sh <instrumented-binary> graalvm <params> training
# Generates default.iprof

# 3. Move profile to source directory
mv default.iprof src/pgo-profiles/main/

# 4. Rebuild with profile
./gradlew nativeCompile --build-args="--gc=G1"

# 5. Benchmark optimized binary
./benchmark.sh <optimized-binary> graalvm <params>
```

**Memory Configuration** (GraalVM):
- Dynamically calculates 85% of system memory
- Bounds: 2048 MB minimum, 131072 MB maximum
- Gradle JVM: 1 GB, Native image: calculated value

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
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=true \
  -XX:ArchiveClassesAtExit=petclinic.jsa \
  --spring.profiles.active=postgres -jar <JAR>

# Wait for startup → hit URLs → terminate
# Output: petclinic.jsa (~50-100 MB)
```

**Leyden Training** (2-step):
```bash
# Step 1: Record AOT configuration - uses same heap/GC settings
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=true \
  -XX:AOTMode=record -XX:AOTConfiguration=petclinic.aotconf \
  --spring.profiles.active=postgres -jar <JAR>

# Step 2: Create AOT cache from configuration - uses same heap/GC settings
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=true \
  -XX:AOTMode=create \
  -XX:AOTConfiguration=petclinic.aotconf \
  -XX:AOTCache=petclinic.aot \
  --spring.profiles.active=postgres -jar <JAR>

# Output: petclinic.aot (~100-200 MB)
```

**CRaC Training**:
```bash
# 1. Start application - uses full heap/GC settings for fresh JVM start
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=false \
  -XX:CRaCCheckpointTo=petclinic-crac \
  -XX:CRaCEngine=warp \
  --spring.profiles.active=postgres \
  --spring.datasource.hikari.allow-pool-suspension=true \
  -jar <JAR>

# 2. Wait for startup → hit URLs

# 3. Take checkpoint
jcmd <PID> JDK.checkpoint

# 4. Wait for checkpoint completion
# Output: petclinic-crac/ directory (~500 MB - 1 GB)
```

**GraalVM Training**:
```bash
# Run instrumented binary - uses same heap settings as production
./spring-petclinic-instrumented -Xms512m -Xmx1g \
  --spring.profiles.active=postgres

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
- Measures startup time and memory for each run
- Writes results to CSV

**Measurement Process**:
```bash
# Start with time measurement
/usr/bin/time -v $APP_CMD &

# Extract startup time from log
# Standard: "Started PetClinicApplication in X.XXX seconds"
# CRaC: "restored JVM running for X ms"

# Hit URLs to load application

# Terminate and extract memory
# Linux: "Maximum resident set size (kbytes)"
# macOS: "peak memory footprint" (bytes → KB)

# Write to CSV: Run,Startup Time,Memory
```

#### 4. Statistical Analysis

**Trimmed Mean**:
- Removes min and max values (outliers)
- Calculates average of remaining runs
- Requires minimum 3 data points
- Written as row "A" in CSV

### URL Load Simulation

**11 endpoints tested**:
- Owner search and pagination
- Owner details
- Vet listings with pagination
- Error page

**Execution**:
- 60-second readiness check (HTTP 200 on root)
- 3-second pause between URLs
- Total execution: ~33 seconds

### Process Management

**Cleanup Strategy**:
- Kills existing `spring-petclinic` processes before warm-ups
- Prevents port conflicts (8080)

**PID Tracking** (variant-specific):
- GraalVM: Extract from Spring Boot log or pgrep by binary name
- CRaC: Search for process with `CRaCRestoreFrom` parameter
- Standard: Find Java child process

**Termination**:
1. Graceful: `kill -TERM <PID>` + 1s wait
2. Force: `kill -9 <PID>` if still running

---

## Output Files

### Build Artifacts

| File/Directory | Size | Description |
|----------------|------|-------------|
| `build/libs/*.jar` | 50-100 MB | Application JAR |
| `petclinic.jsa` | 50-100 MB | CDS cache |
| `petclinic.aot` | 100-200 MB | Leyden cache |
| `petclinic-crac/` | 500 MB - 1 GB | CRaC checkpoint |
| `build/native/nativeCompile/spring-petclinic` | 100-150 MB | GraalVM binary |
| `src/pgo-profiles/main/default.iprof` | 10-50 MB | GraalVM profile |

### Benchmark Results

**CSV Format** (`result_{label}.csv`):
```csv
Run,Startup Time (s),Max Memory (KB)
1,0.352,156432
2,0.341,154288
...
7,0.361,157088
A,0.353,155968  # Trimmed mean
```

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
BASE_JVM_PARAMS="-Xms512m -Xmx1g -XX:+UseG1GC --spring.profiles.active=postgres"

# Base JVM parameters with AOT enabled
BASE_JVM_PARAMS_WITH_AOT="-Xms512m -Xmx1g -XX:+UseG1GC -Dspring.aot.enabled=true --spring.profiles.active=postgres"

# CRaC Training: Includes GC for fresh JVM start
CRAC_TRAINING_PARAMS="-Xms512m -Xmx1g -XX:+UseG1GC -Dspring.aot.enabled=false --spring.profiles.active=postgres --spring.datasource.hikari.allow-pool-suspension=true"

# CRaC Restore: NO GC flag (restored from checkpoint)
CRAC_RESTORE_PARAMS="-Xms512m -Xmx1g -Dspring.aot.enabled=false --spring.profiles.active=postgres --spring.datasource.hikari.allow-pool-suspension=true"

# GraalVM: Native binary (no JVM-specific GC flag)
GRAALVM_PARAMS="-Xms512m -Xmx1g --spring.profiles.active=postgres"
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

```bash
# baseline
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=false -jar <JAR>

# tuning
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=true -jar <JAR>

# cds
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=true \
  -XX:SharedArchiveFile=petclinic.jsa -jar <JAR>

# leyden
java -Xms512m -Xmx1g -XX:+UseG1GC \
  -Dspring.aot.enabled=true \
  -XX:AOTCache=petclinic.aot -jar <JAR>

# crac (restore)
# NOTE: NO -XX:+UseG1GC flag - GC configuration restored from checkpoint
java -Xms512m -Xmx1g \
  -Dspring.aot.enabled=false \
  -XX:CRaCRestoreFrom=petclinic-crac \
  -XX:CRaCEngine=warp \
  --spring.datasource.hikari.allow-pool-suspension=true

# graalvm (native)
./spring-petclinic -Xms512m -Xmx1g
```

All variants use: `--spring.profiles.active=postgres`

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
# Application logs
cat /tmp/app_training.log    # Training runs
cat /tmp/app_benchmark.log   # Benchmark runs

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

## Known Limitations

1. **Leyden** - May cause system hangs on Linux during AOT cache generation
2. **CRaC** - Linux only, requires CRIU, complex process tracking
3. **GraalVM** - Memory intensive, long build times, platform-specific flags
4. **Fixed timings** - 3-second delays between URLs, 3 warm-ups, 7 runs (not configurable)
5. **No Windows support** - Linux/macOS only

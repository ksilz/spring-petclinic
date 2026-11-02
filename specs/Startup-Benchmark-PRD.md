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
- `-J-Xmx${GRAALVM_MAX_HEAP}`: JVM heap for native-image build process (80% of system memory)
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
# Output: petclinic-crac/ directory, ~230-400 MB (observed 232.6 MB on JDK 25, 397.4 MB on JDK 27, t3.small, 2026-10-31)
```

The checkpoint counts as complete only when all of the following hold: `warp: Checkpoint successful!` is logged, the final `core.img` exists, no `core.img.<random>` temp file remains, and the `core.img` size is unchanged across two consecutive 1-second checks. If this does not happen within 120 seconds, training fails (exit 1). Before CRaC training, `benchmark.sh` removes any old `petclinic-crac/` directory.

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
- 3-second pause between URLs (`sleep 3` before each request)
- 11 URLs × 5 rounds = 55 total requests
- Total execution: ~165 seconds of request pauses (55 requests x 3 s) plus application startup
- Any URL other than `/oups` that returns a status other than 200 fails the run (`/oups` must return 500). The guard also applies to training runs. `hit_urls` fails on an unexpected status, on no response (000), or on a readiness failure (timeout, or the process exiting early). On any of them the application is stopped (TERM, then KILL), port 8080 is awaited, and for CDS `petclinic.jsa` is removed (also after a warm-up or measured-run failure, so the next run retrains), for Leyden a leftover `petclinic.aotconf` is removed.

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
| `petclinic-crac/` | 230-400 MB | CRaC checkpoint directory |
| `build/native/nativeCompile/spring-petclinic` | 100-150 MB | GraalVM optimized binary |
| `build/native/nativeCompile/spring-petclinic-instrumented` | 100-150 MB | GraalVM instrumented binary (for training) |
| `src/pgo-profiles/main/default.iprof` | 10-50 MB | GraalVM PGO profile |
| `/tmp/gc_*.log` | 1-10 MB | GC logs per JVM variant (the GraalVM GC lines go to the app log) |
| `/tmp/app_*.log` | 1-10 MB | Application logs per phase |

### Benchmark Results

**CSV file names**:
- Track 25: `result_<label>.csv`. Track 27: `result_<label>_jdk27.csv`.
- Smoke test (`BENCH_WARMUPS`/`BENCH_RUNS` other than 3/7): `_smoke` is added, e.g. `result_<label>_smoke.csv` or `result_<label>_jdk27_smoke.csv`. A smoke test never overwrites an official result.

**CSV Format** (example from the May 2026 baseline run, shortened):
```csv
Run,Startup Time (s),Max Memory (MB),Startup GCs,Benchmark GCs,Ran at,Size App (MB),Size Extra (MB)
1,12.68,442.0,34,6,2026-05-01T20:30:28Z,,
...
7,13.493,450.3,34,8,2026-05-01T20:49:02Z,,
A,13.3166,448.36,34,6.2,2026-05-01T20:52:08Z,66.5,0.0
```

**Columns**:
- **Run**: Run number (1 to `RUNS`) or "A" for the trimmed mean (drops min and max)
- **Startup Time (s)**: Seconds Spring Boot reports in "Started PetClinicApplication in X seconds" (CRaC: "restored JVM running for X ms")
- **Max Memory (MB)**: Peak memory from `/usr/bin/time` (Linux: maximum resident set size; macOS: peak memory footprint)
- **Startup GCs**: GC pause log lines before "Started". G1 writes a start and an end line per pause, so this is about twice the number of pauses. All variants use this rule. GraalVM reads its GC lines from the app log, because the native executable prints them to stdout.
- **Benchmark GCs**: GC pause log lines after "Started", during the URL load simulation (same rule)
- **Ran at**: ISO 8601 timestamp when the run started
- **Size App (MB)** / **Size Extra (MB)**: Artifact sizes, only in the A row

---

## Tested Versions

Versions used in the 2026-10-31 verification run (see below) and in the May 2026 run it is compared with. The official run of 2026-11-01 used the same JDKs, GraalVM, Spring Boot and Gradle, but CycloneDX 3.5.1 and the hosts after their 2026-11-01 updates and reboot: PostgreSQL 16.15 on the small server, kernel 7.0.0-1014-aws, glibc 2.39-0ubuntu8.9 (details: `docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27/versions-*.txt`).

| Item | Track 25 | Track 27 | Old run (May 2026) |
|---|---|---|---|
| Spring Boot | 4.1.2 | 4.1.2 | 4.0.3 |
| Gradle | 9.5.1 | 9.5.1 | 9.2.1 |
| GraalVM native build tools | 1.1.2 | 1.1.2 | 0.11.5 |
| CycloneDX Gradle plugin | 3.2.4 | 3.2.4 | 3.2.0 |
| baseline, tuning, cds, leyden JDK | Temurin 25.0.5+8 (`openjdk 25.0.5 2026-10-20 LTS`, build 25.0.5+8-LTS), SDKMAN `25.0.5.0+8-tem` | Temurin 27+35 (`openjdk 27 2026-09-15`, build 27+35), SDKMAN `27.0.0.0+35-tem` | JDK 25.0.3-tem |
| crac JDK | Zulu CRaC 25.0.4.1 (`Zulu25.36+205-CRaC-CA`, build 25.0.4.1+1-LTS), SDKMAN `25.0.4.1-crac+1-zulu` | Zulu CRaC 27 (`Zulu27.28+101-CRaC-CA`, build 27+35), SDKMAN `27.0.0.0-crac+35-zulu` | CRaC 25.0.2.crac-zulu |
| graalvm | Oracle GraalVM 25.0.5.0.3+1.1 (build 25.0.5.0.3+1-LTS-jvmci-b01), `native-image 25.0.5.0.3 2026-10-25`, SDKMAN `25.0.5.0+3-graal` | n/a (no GraalVM release for JDK 27) | GraalVM 25.0.3-graal |
| CRIU | 4.1.1 (CRaC engine: warp) | 4.1.1 (CRaC engine: warp) | unknown |
| PostgreSQL | 16.13 on the small server (benchmarks); 18.3 on the big server (GraalVM PGO training run only) | same | unknown |
| Run host | AWS t3.small, 2 vCPU Intel Xeon Platinum 8259CL @ 2.50GHz, 1.9 GB RAM, 2 GB swap | same | same host |
| Native build host | AWS t3.2xlarge, 8 vCPU Intel Xeon Platinum 8259CL @ 2.50GHz, 31 GB RAM, no swap | n/a | unknown |
| OS (both hosts) | Ubuntu 24.04.4 LTS, kernel 6.17.0-1013-aws, glibc 2.39 (Ubuntu GLIBC 2.39-0ubuntu8.7) | same | unknown |

The GraalVM native image is built on the big server (build host) and copied to the small server (run host). All other variants are built and run on the small server.

After this run, the CycloneDX Gradle plugin went to 3.5.1 (`53d0ad6`). 3.5.1 builds the native image without the 3.2.4 workaround and embeds the same SBOM.

---

## Official Run 2026-11-01

The full benchmark for the W-JAX 2026 talk: Spring Boot 4.1.2, JDK 25 and JDK 27, default run counts (3 warm-ups + 7 measured runs), small server; GraalVM native executable built with PGO on the big server. All 11 variants passed. German report with all results, charts and the numbers for Keynote: [`docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27/benchmark-bericht.html`](../docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27/benchmark-bericht.html); raw data and method notes in the folder's [README](../docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27/README.md).

Row A (trimmed mean) per variant:

| Variant | JDK 25 startup | JDK 27 startup | JDK 25 memory | JDK 27 memory | JDK 25 GCs startup / benchmark | JDK 27 GCs startup / benchmark |
|---|---|---|---|---|---|---|
| Baseline | 13.756 s | 13.991 s | 442 MB | 469 MB | 34 / 5 | 34 / 2.4 |
| Tuning | 9.240 s | 9.588 s | 411 MB | 481 MB | 28 / 2 | 26.4 / 1.2 |
| Tuning + CDS | 5.629 s | 5.935 s | 399 MB | 371 MB | 4 / 2 | 4.4 / 1.6 |
| Tuning + Leyden | 4.331 s | 4.088 s | 370 MB | 346 MB | 3 / 1 | 2.8 / 1.2 |
| CRaC | 0.077 s | 0.091 s | 387 MB | 375 MB | 0 / 0 | 0 / 0 |
| GraalVM | 0.354 s | n/a | 200 MB | n/a | 8 / 8 | n/a |

Notes:
- Tuning + CDS on JDK 27 was measured twice (first attempt A 6.022 s, rerun A 5.935 s); it scatters more than the other variants on this host. The table shows the rerun.
- GraalVM now runs `schema.sql` and `data.sql` at startup like the JVM variants (finding 5 below), and its GC columns are measured (finding 6), so it differs from the May 2026 slides (0.287 s, 0 / 0).
- Preparations: duplicate database indexes removed (findings 5 and 10), apt timers disabled on both servers, servers rebooted (finding 11). The apt timers stay disabled until the user re-enables them.

## Verification Run 2026-10-31 (not the official benchmark)

This was a smoke test after the upgrade to Spring Boot 4.1.2, JDK 25.0.5 and JDK 27. It is NOT the official benchmark. Each variant had 1 warm-up and 3 measured runs (`BENCH_WARMUPS=1 BENCH_RUNS=3`), and the row `A` is the trimmed mean, which equals the median with 3 runs. The comparison column comes from the May 2026 run (Spring Boot 4.0.3, 3 warm-ups, 7 runs). Both runs used the same host, the small server. Do not quote these numbers as final results.

Full details, logs and CSV files: [`docs/benchmark-results/2026-10-31-verification-boot-4.1.2/README.md`](../docs/benchmark-results/2026-10-31-verification-boot-4.1.2/README.md).

### (a) Old (May 2026, Boot 4.0.3, JDK 25.0.3) vs new track 25 (Boot 4.1.2, JDK 25.0.5)

Startup times in seconds. Old: 7 runs. New: 3 runs (verification run, 1 warm-up + 3 runs).

| Variant | Old median | Old min-max | New median | New min-max | Change (median) | Old mem MB | New mem MB |
|---|---|---|---|---|---|---|---|
| baseline | 13.437 | 12.680-14.186 | 14.696 | 14.205-15.111 | +9% | 450 | 440 |
| tuning | 8.902 | 8.722-9.031 | 9.586 | 9.344-9.798 | +8% | 414 | 410 |
| cds | 5.596 | 5.322-6.381 | 5.863 | 5.798-5.865 | +5% | 397 | 393 |
| leyden | 4.204 | 4.138-4.411 | 4.637 | 4.608-5.256 | +10% | 358 | 352 |
| crac | 0.089 | 0.077-0.237 | 0.082 | 0.075-0.087 | -8% | 376 | 372 |
| graalvm | 0.278 | 0.270-0.328 | 0.611 | 0.604-0.697 | +120% | 198 | 201 |

### (b) Track 25 (JDK 25.0.5) vs track 27 (JDK 27), five common variants

Both: 1 warm-up + 3 runs (verification run). Startup times in seconds.

| Variant | 25 median | 25 min-max | 27 median | 27 min-max | Change (median) | 25 mem MB | 27 mem MB |
|---|---|---|---|---|---|---|---|
| baseline | 14.696 | 14.205-15.111 | 15.981 | 14.218-16.340 | +9% | 440 | 628 |
| tuning | 9.586 | 9.344-9.798 | 9.516 | 9.292-9.543 | -1% | 410 | 457 |
| cds | 5.863 | 5.798-5.865 | 5.876 | 5.703-5.956 | +0% | 393 | 367 |
| leyden | 4.637 | 4.608-5.256 | 4.256 | 4.210-4.316 | -8% | 352 | 356 |
| crac | 0.082 | 0.075-0.087 | 0.084 | 0.079-0.090 | +2% | 372 | 369 |

The graalvm "Startup GCs" and "Benchmark GCs" columns were not measured in this run (script issue, fixed afterwards, see finding 6). The 0/0 values in its CSV are not data.

### Findings

1. The GraalVM native build was broken by CycloneDX Gradle plugin 3.2.4. Fixed in `62e0b4e` with a workaround. Since `53d0ad6` the plugin is 3.5.1, which needs no workaround.
2. CRaC training race: `benchmark.sh` treated the checkpoint as finished as soon as any file appeared in `petclinic-crac/`. Zulu CRaC 25.0.4.1 (warp) writes `core.img.<random>` and renames it to `core.img` at the end. TERM sent mid-write baked the shutdown into the image, so every restore exited. Fixed in `8c005d0` and `87cf7b6`.
3. The GraalVM native image lacked reflection registrations for Thymeleaf `Strings.listJoin`, `Numbers.sequence` and `Temporals.format`. That gave HTTP 500 on 9 of 11 pages, also during PGO training. Fixed in `6b52de8`.
4. The benchmark accepted HTTP 500 pages as success, because `hit_urls` only aborted on 000. Fixed in `70ce917`: every URL must return 200 except `/oups` (500).
5. Explained on 2026-11-01: the GraalVM startup on the small server is 0.611 s now vs 0.278 s in May (A/B: 0.629 s vs 0.283 s), but 0.295 s on the big server. Cause:
   - The new executable runs `schema.sql` and `data.sql` at startup, like every JVM variant always did (`spring.sql.init.mode=always`). The May executable never ran them: before upstream commit `a2c2ef9` (resource hints for `db/*/*`, merged with the upgrade) the scripts were not in the native image.
   - `data.sql` is slow on the small server, because its `petclinic` database carries 4,137 duplicate indexes (591 copies each on five tables, 1,182 on `pets`; the big server: 74 per table). The old `schema.sql` created an unnamed copy of every index on each startup. The new `schema.sql` uses named `CREATE INDEX IF NOT EXISTS`, but the old copies stay. On a clean database the same `data.sql` takes 14-15 ms. The big server's fast startup is consistent with its fewer copies (`data.sql` was not timed there).
   - Measured on the small server (5 interleaved rounds, medians): new executable 0.648 s on the `petclinic` database (`data.sql` 281-457 ms), 0.357 s on a clean database (`data.sql` 14-15 ms), 0.323 s without SQL init; May executable 0.292 s. So about 0.29 s is database state, about 0.03 s is the scripts themselves, about 0.03 s (+10%) is the rest of the upgrade.
   - The May 2026 graalvm result skipped the SQL scripts, so it is not comparable with the other variants.
   - Details: [verification README, "Follow-up 2026-11-01"](../docs/benchmark-results/2026-10-31-verification-boot-4.1.2/README.md#follow-up-2026-11-01).
6. Pre-existing, fixed on 2026-11-01 (`de3b237`, `b78735e`): the GraalVM "Startup GCs" and "Benchmark GCs" columns were always 0/0. `benchmark.sh` put `2>/tmp/gc_graalvm.log` inside `APP_CMD`, so the shell passed it to the executable as a plain argument. The redirect would not have helped anyway: the native executable prints its GC lines to stdout and ignores `-Xlog:gc:file=...`. `benchmark.sh` now reads them from the app log and counts them like the JVM variants. The 0/0 values in the May 2026 and in this run's CSVs are not data.
7. The May 2026 "Size App (MB)" of 164.6 for tuning, cds and leyden is inflated. The old checkout held 225 library JARs, because `java -Djarmode=tools extract --force` never deletes stale files. A fresh checkout has 93 JARs and 63.8 MB. Startup is not affected.
8. The JDK 27 baseline peak memory is 628 MB median (643 MB max) vs 440 MB on JDK 25, with the same `-Xmx768m`. Watch this in the real benchmark.
9. "Size Extra (MB)" is 0.0 for cds, leyden and crac in the old and the new runs. `compile-and-run.sh` measures sizes before `benchmark.sh` creates the archive, cache or checkpoint. Pre-existing.
10. Found on 2026-11-01: the duplicate indexes (finding 5) slow down every JVM variant too. On the JVM baseline, `data.sql` took 495-559 ms on the `petclinic` database vs 86-109 ms on a clean one, about 0.4 s per startup (about 9% of leyden). Removed on 2026-11-01 on both servers (`tools/drop-duplicate-indexes.sql` in that results folder): 4,152 to 15 indexes on the small server, 533 to 15 on the big server, rows unchanged. The old checkouts in `~/projects/spring-petclinic` still have the old `schema.sql` and would add the copies again.
11. Found on 2026-11-01: `unattended-upgrade` ran on both servers in the morning (small server 06:41-06:52 UTC, big server about 06:24-06:31 UTC). On the small server it upgraded PostgreSQL 16.13 to 16.15 and restarted it twice; a start at 06:48 failed with "Connection to localhost:5432 refused". On the big server PostgreSQL 18.3 was restarted 10 times. Both got glibc 2.39-0ubuntu8.9, a newer OpenSSL and a new kernel, with a reboot pending. The apt timers were disabled on both servers on 2026-11-01 (`systemctl disable --now apt-daily.timer apt-daily-upgrade.timer`), so they stay off after the reboot. Re-enable them after the official run. Record the versions again: the "Tested Versions" table no longer matches the servers.

After the code review, a final check on commit 957a887 passed. On the small server, the median was 0.612 s for graalvm and 0.075 s for crac (1 warm-up + 3 runs). 87 tests pass on JDK 25 and JDK 27. Details are in the [verification README](../docs/benchmark-results/2026-10-31-verification-boot-4.1.2/README.md).

A follow-up on 2026-11-01 explained finding 5, fixed finding 6, upgraded CycloneDX to 3.5.1 and added a test that scans the templates for helpers without a native hint. On `ef9e49d`, 88 tests ran on JDK 25 and on JDK 27: 0 failures, 4 skipped (Docker-based tests, no Docker on the server).

---

## Platform Compatibility

| Variant | Linux | macOS | Windows |
|---------|-------|-------|---------|
| baseline, tuning, cds, leyden | ✅ | ✅ | ❌ |
| crac | ✅ | ❌ | ❌ |
| graalvm | ✅ | ✅ | ❌ |

**CRaC Requirements** (Linux only):
- CRIU installed (`apt install criu`)
- Java 25 or 27 with CRaC support (Azul Zulu CRaC: `25.0.4.1-crac+1-zulu` on track 25, `27.0.0.0-crac+35-zulu` on track 27)
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

Both can be overridden with the environment variables `BENCH_WARMUPS` (integer >= 0) and `BENCH_RUNS` (integer >= 3, because the A row is a trimmed mean that drops min and max). The overrides are intended for smoke tests only; official results use the defaults (3 warm-ups, 7 runs). Example: `BENCH_WARMUPS=1 BENCH_RUNS=3 ./compile-and-run.sh baseline`. A smoke test writes `result_<label>[_jdk27]_smoke.csv` instead of the official file name.

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

# GC logs (per JVM variant)
cat /tmp/gc_baseline.log
cat /tmp/gc_tuning.log
cat /tmp/gc_cds.log
cat /tmp/gc_leyden.log
cat /tmp/gc_crac.log
# GraalVM: the native executable prints GC lines to stdout, so they are in the app log
grep "\[gc" /tmp/app_benchmark.log

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
- Waits up to 120 seconds for checkpoint completion
- Validates that the final `core.img` exists and no `core.img.<random>` temp file remains
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
4. **Fixed timings** - 3-second delays between URLs. 3 warm-ups and 7 runs are the defaults. `BENCH_WARMUPS` and `BENCH_RUNS` override them for smoke tests only (minimum 3 runs), and the CSV name then ends in `_smoke`. Official results use the defaults.
5. **No Windows support** - Linux/macOS only
6. **Swap warnings** - Benchmarks warn if swap usage increases during testing (indicates memory pressure)

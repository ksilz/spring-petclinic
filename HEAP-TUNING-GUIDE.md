# Heap Tuning System - Usage Guide

This guide explains how to use the automated heap tuning system to find optimal JVM heap settings.

## Final Recommended Settings

**TLDR: Use `-Xms1024m -Xmx1024m` for all variants.**

After extensive automated tuning (10 iterations testing heap sizes from 512m to 1088m), the optimal heap size has been determined to be **1024m**. This setting provides a balanced tradeoff between memory usage and GC behavior:
- **Startup GCs:** ~22 (acceptable overhead)
- **Benchmark GCs:** ~2 (sufficient garbage collection during workload)

These settings have been applied to `benchmark.sh` and all benchmark results now include GC metrics in the CSV output.

## Original Goal (Unfeasible)

The initial goal was to find heap settings where:
- ✅ **NO** garbage collection occurs during application startup
- ✅ **SOME** garbage collection occurs during benchmark runs (when pages are accessed)

**Finding:** This goal proved unrealistic for Spring Boot applications. Testing revealed:
1. Heap sizes that prevent all startup GC (>1088m) are so large that even 55 HTTP requests (5x the normal benchmark workload) don't generate enough garbage to trigger GC
2. Heap sizes that allow benchmark GC (<1024m) also experience significant startup GC

The 1024m setting represents the best practical compromise.

## Components

### 1. Modified `benchmark.sh`
- Added GC logging to all JVM-based variants
- Logs to `/tmp/gc_${VARIANT}.log` with unified logging format
- GraalVM Native Image uses `-XX:+PrintGC` flag
- **CSV Output Enhancement:** Now includes two additional columns:
  - `Startup GCs`: Number of garbage collection events during application startup
  - `Benchmark GCs`: Number of garbage collection events during benchmark workload
  - CSV format: `Run,Startup Time (s),Max Memory (KB),Startup GCs,Benchmark GCs`

### 2. `verify-gc-behavior.sh`
Analyzes GC logs to verify behavior meets goals.

**Usage:**
```bash
./verify-gc-behavior.sh <VARIANT> [APP_LOG] [GC_LOG]
```

**Exit codes:**
- `0` = Success (no GC during startup, some during benchmark)
- `1` = GC during startup (heap too small)
- `2` = No GC during benchmark (heap too large)
- `3` = GC during both phases or verification error

**Example:**
```bash
./verify-gc-behavior.sh baseline /tmp/app_benchmark.log /tmp/gc_baseline.log
```

### 3. `tune-heap-settings.sh`
Iteratively finds optimal heap settings using binary search approach.

**Usage:**
```bash
./tune-heap-settings.sh [VARIANT] [JAR_PATH]
```

**Parameters:**
- `VARIANT` (optional): Which variant to tune (default: `baseline`)
  - Supported: `baseline`, `tuning`
  - Others can be added as needed
- `JAR_PATH` (optional): Path to JAR file (default: `build/libs/spring-petclinic-3.5.0-SNAPSHOT.jar`)

**Example:**
```bash
# Tune baseline variant
./tune-heap-settings.sh baseline build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar

# Tune AOT variant
./tune-heap-settings.sh tuning build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar
```

### 4. `TODOS.md`
Live progress tracking - updated automatically during tuning process.

### 5. `heap-tuning-results.log`
Detailed log of all iterations and adjustments.

## How It Works

### Tuning Algorithm

1. **Start** with initial heap: `-Xms512m -Xmx512m`
2. **Run benchmark** with current heap settings (3 iterations for consistency)
3. **Analyze GC logs** using `verify-gc-behavior.sh`
4. **Adjust heap** based on results:
   - If GC during startup → Increase by 64 MB
   - If no GC during benchmark → Decrease by 64 MB
   - If perfect → Done! ✅
5. **Repeat** until optimal settings found or max iterations reached (10)

### Constraints

- **Starting heap:** 512 MB
- **Min heap:** 256 MB
- **Max heap:** 4 GB
- **Adjustment step:** 64 MB
- **Max iterations:** 10

These can be modified in `tune-heap-settings.sh` if needed.

## Running the Tuning Process

### Prerequisites

1. **Build the application:**
   ```bash
   ./gradlew build
   ```

2. **Start PostgreSQL:**
   ```bash
   docker compose up postgres -d
   # OR
   docker run -e POSTGRES_USER=petclinic -e POSTGRES_PASSWORD=petclinic \
     -e POSTGRES_DB=petclinic -p 5432:5432 postgres:17.5 -d
   ```

3. **Ensure benchmark.sh works:**
   ```bash
   ./benchmark.sh build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar baseline
   ```

### Run Tuning

```bash
# Start the tuning process
./tune-heap-settings.sh baseline build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar
```

### Monitor Progress

- **Live updates:** `tail -f TODOS.md`
- **Detailed log:** `tail -f heap-tuning-results.log`
- **GC events:** `tail -f /tmp/gc_baseline.log`

### Example Output

```
[INFO] =========================================
[INFO] Starting heap tuning for variant: baseline
[INFO] JAR path: build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar
[INFO] =========================================
[INFO] =========================================
[INFO] Iteration 1 / 10
[INFO] Testing heap: 512m
[INFO] =========================================
[INFO] Running benchmark with heap: -Xms512m -Xmx512m
...
[INFO] GC occurred during startup. Increasing heap by 64m
[INFO] =========================================
[INFO] Iteration 2 / 10
[INFO] Testing heap: 576m
[INFO] =========================================
...
[INFO] ✅ SUCCESS! Optimal heap found: 640m
[INFO] =========================================
[INFO] Heap Tuning Complete
[INFO] =========================================
[INFO] ✅ Optimal heap settings found:
[INFO]    -Xms640m -Xmx640m
```

## Applying Results

The optimal heap settings (**1024m**) have already been applied to `benchmark.sh`.

All JVM parameter variables (lines ~143-155) have been updated:
```bash
BASE_JVM_PARAMS="-Xms1024m -Xmx1024m ..."
BASE_JVM_PARAMS_WITH_AOT="-Xms1024m -Xmx1024m ..."
CRAC_TRAINING_PARAMS="-Xms1024m -Xmx1024m ..."
CRAC_RESTORE_PARAMS="-Xms1024m -Xmx1024m ..."
GRAALVM_PARAMS="-Xms1024m -Xmx1024m ..."
```

**To verify** with the full benchmark suite:
```bash
./compile-and-run.sh
```

**To apply different settings** (if needed for experimentation):
1. Open `benchmark.sh`
2. Find the parameter variables (lines ~143-155)
3. Replace all instances of `-Xms1024m -Xmx1024m` with your desired settings
4. Re-run benchmarks to verify

## Troubleshooting

### Script fails immediately
- Check that JAR path is correct
- Ensure PostgreSQL is running
- Verify benchmark.sh works standalone

### No GC events found
- Check GC log file exists: `ls -lh /tmp/gc_*.log`
- Verify GC logging flags in benchmark.sh
- For GraalVM, GC might log to stdout - script handles this

### Infinite loop detected
- Script tracks tested heap sizes to avoid loops
- If stuck, manually adjust starting heap or constraints

### Verification fails
- Review `/tmp/app_benchmark.log` for application startup
- Check `/tmp/gc_*.log` for GC events
- Manually run: `./verify-gc-behavior.sh baseline`

## Manual Verification

To manually check GC behavior without tuning:

1. **Run benchmark:**
   ```bash
   ./benchmark.sh build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar baseline
   ```

2. **Check startup time:**
   ```bash
   grep "Started PetClinicApplication" /tmp/app_benchmark.log
   ```

3. **Check GC events:**
   ```bash
   grep "Pause" /tmp/gc_baseline.log
   ```

4. **Verify GC behavior:**
   ```bash
   ./verify-gc-behavior.sh baseline
   ```

## Notes

- **Adjustment step:** Currently 64 MB. Smaller steps = more iterations but finer granularity
- **Variants:** Only `baseline` and `tuning` supported currently. Add more as needed.
- **Training runs:** Tuning uses benchmark runs (not training runs) for speed
- **GraalVM Native:** Different GC system - may need different tuning approach
- **CRaC:** GC config restored from checkpoint - tune during training phase

## Next Steps

After finding optimal heap for one variant:

1. Test other variants (`tuning`, `cds`, `leyden`, `crac`)
2. Compare heap requirements across variants
3. Run full benchmark suite with optimal settings
4. Document results in PRD or benchmark report

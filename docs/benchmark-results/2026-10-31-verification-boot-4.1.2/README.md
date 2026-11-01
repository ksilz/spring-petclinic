# Verification run 2026-10-31 (not the official benchmark)

This is a smoke test after the upgrade to Spring Boot 4.1.2 with JDK 25.0.5 and JDK 27. It is NOT the official benchmark. The user runs the real benchmark later.

Do not quote these numbers as final results. Each variant had only 1 warm-up and 3 measured runs.

## What ran

- Method: `BENCH_WARMUPS=1 BENCH_RUNS=3`. This is a new environment override. The defaults stay at 3 warm-ups and 7 runs.
- The row `A` in each CSV is the trimmed mean (min and max dropped). With 3 runs it equals the median.
- Run host: the small server (AWS t3.small, 2 vCPU Intel Xeon Platinum 8259CL @ 2.50GHz, 1.9 GB RAM, 2 GB swap). This is the same host as the May 2026 run.
- No CPU steal during the run: `vmstat` st averaged 0.45 %, with a maximum of 16 % in one sample over 283 samples.
- Native build host: the big server (AWS t3.2xlarge, 8 vCPU, 31 GB RAM, no swap). The GraalVM executable was copied to the small server.
- OS on both hosts: Ubuntu 24.04.4 LTS, kernel 6.17.0-1013-aws, glibc 2.39.
- Track 25: baseline, tuning, cds, leyden, crac, graalvm. Track 27: baseline, tuning, cds, leyden, crac (no GraalVM release for JDK 27).
- Old comparison run: May 2026, Spring Boot 4.0.3, 3 warm-ups and 7 runs. See `../2026-05-01-boot-4.0.3-jdk25/README.md`.

## Versions

| Item | Track 25 | Track 27 |
|---|---|---|
| Code | branch run-upgrade-benchmarks-jdk25-jdk27 (Spring Boot 4.1.2, Gradle 9.5.1, GraalVM native build tools 1.1.2, CycloneDX Gradle plugin 3.2.4) | same |
| baseline, tuning, cds, leyden JDK | Temurin 25.0.5+8 (`openjdk 25.0.5 2026-10-20 LTS`, build 25.0.5+8-LTS), SDKMAN `25.0.5.0+8-tem` | Temurin 27+35 (`openjdk 27 2026-09-15`, build 27+35), SDKMAN `27.0.0.0+35-tem` |
| crac JDK | Zulu CRaC 25.0.4.1 (`Zulu25.36+205-CRaC-CA`, build 25.0.4.1+1-LTS), SDKMAN `25.0.4.1-crac+1-zulu` | Zulu CRaC 27 (`Zulu27.28+101-CRaC-CA`, build 27+35), SDKMAN `27.0.0.0-crac+35-zulu` |
| graalvm | Oracle GraalVM 25.0.5.0.3+1.1 (build 25.0.5.0.3+1-LTS-jvmci-b01), `native-image 25.0.5.0.3 2026-10-25`, SDKMAN `25.0.5.0+3-graal` | n/a (no GraalVM release for JDK 27) |
| CRIU | 4.1.1 (CRaC engine: warp) | same |
| PostgreSQL | 16.13 on the small server (benchmarks); 18.3 on the big server (GraalVM PGO training run only) | same |

## Commits

- Track 25 baseline, tuning, cds, leyden and track 27 baseline ran on `62e0b4e`.
- Track 25 crac (rerun) and track 27 tuning, cds, leyden, crac ran on `87cf7b6`. It adds only the CRaC checkpoint-wait fix, which only affects crac.
- Track 25 graalvm (valid run): commit `9fe08b8` on the small server. The executable was built from `6b52de8` (adds the reflection-hint fix).
- The guard commits `70ce917` and `9fe08b8` only add the HTTP status guard. It passed: all pages 200, `/oups` 500.

## Results

These are verification numbers (1 warm-up + 3 runs), not the official benchmark. The old column comes from a full run (3 warm-ups + 7 runs).

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

The graalvm "Startup GCs" and "Benchmark GCs" columns in the CSV files are not measured (known script issue, see finding 6). The 0/0 values there are not data.

### GraalVM A/B on the small server

Both executables were run back to back on 2026-10-31, 22:00 to 22:21 UTC, with 1 warm-up and 3 runs each.

| Executable | Median (s) | Runs (s) |
|---|---|---|
| May 2026 executable | 0.283 | 0.279 / 0.303 / 0.283 |
| New executable (attempt 2) | 0.629 | 0.631 / 0.629 / 0.615 |

The new executable also ran on the big server (8 vCPU) at 0.311 s. After the reflection-hint fix (attempt 3) the executable started in 0.611 s on the small server (runs 0.604 / 0.611 / 0.697) and 0.295 s on the big server.

## Native build (big server, track 25)

- Attempt 1 failed in 12 s: CycloneDX 3.2.4 vs `nativeCompile`. Fixed in `62e0b4e`.
- Attempt 2 (`62e0b4e`): instrumented build 13m38s, peak RSS 19.73 GB. PGO training 179 s. Optimized build 8m46s, peak RSS 9.87 GB. Binary 194,382,232 bytes, `default.iprof` 43,107,218 bytes. This executable returned HTTP 500 on 9 of 11 pages, so its timings are not valid.
- Attempt 3 (`6b52de8`): instrumented build 11m53s, peak RSS 17.60 GB. PGO training 179 s with every page 200 (except `/oups` 500). Optimized build 7m27s, peak RSS 10.39 GB. Binary 194,447,768 bytes, `default.iprof` 43,089,137 bytes.

## Artifact sizes observed

- CDS archive `petclinic.jsa`: 110.6 MB (JDK 25), 109.9 MB (JDK 27).
- Leyden AOT cache `petclinic.aot`: 140.2 MB (JDK 25), 149.5 MB (JDK 27).
- CRaC checkpoint `core.img`: 232.6 MB (JDK 25 rerun), 397.4 MB (JDK 27).
- Training run durations (JDK 25 / JDK 27): cds 188 s / 191 s, leyden 202 s / 203 s, crac 188 s (rerun) / 189 s.

## Findings

All were found by this verification run.

1. **GraalVM native build broken by CycloneDX 3.2.4.** Fixed in `62e0b4e` (the `cyclonedxDirectBom` task is realized eagerly in `build.gradle`).
2. **CRaC training race.** `benchmark.sh` treated the checkpoint as finished as soon as any file appeared in `petclinic-crac/`. Zulu CRaC 25.0.4.1 (warp) writes `core.img.<random>`, logs "warp: Checkpoint successful!", keeps writing, then renames to `core.img`. The script sent TERM mid-write, the shutdown got baked into the image, and every restore ran the shutdown hooks and exited. Track 25 crac failed on the first attempt and passed after the fix (`8c005d0`, `87cf7b6`). Track 27 crac passed with the fix.
3. **GraalVM native image missing reflection registrations.** `MissingReflectionRegistrationError` for `org.thymeleaf.expression.Strings.listJoin` (40x), `Numbers.sequence` (30x) and `Temporals.format` (20x) gave HTTP 500 on 9 of 11 pages. The templates used these before the upgrade, but the new stack no longer covers them. The PGO training run hit the same 500s. Fixed in `6b52de8`.
4. **The benchmark accepted HTTP 500 pages as success.** `hit_urls` only aborted on 000. Fixed in `70ce917`: every URL must return 200 except `/oups` (500), otherwise the run fails.
5. **GraalVM startup is slower on the small server. Open.** New executable (attempt 2) 0.629 s vs May executable 0.283 s, back to back. The same new executable needs 0.311 s on the 8-vCPU big server. After the hint fix it is unchanged: 0.611 s small vs 0.295 s big. So the slowdown is real and independent of the reflection bug. The A/B app logs (G1 GC log, before "Started") show GC pauses of about 25 ms in total for both executables. The second young GC comes at 0.488 s (new) vs 0.223 s (May) after allocating about the same memory. That means about 0.3 s more application work between 0.06 s and 0.49 s, and it is slower on 2 vCPU. The new executable also runs 2 concurrent mark cycles during startup (May: 0). Investigate before the real benchmark. The invalid attempt 2 run (HTTP 500 on 9 of 11 pages) had a median of 0.614 s. It is kept for the record only, never as a result.
6. **Known, not fixed (pre-existing).** The GraalVM "Startup GCs" and "Benchmark GCs" columns are always 0/0. `benchmark.sh` puts `2>/tmp/gc_graalvm.log` inside `APP_CMD` and `TRAIN_CMD` and expands them unquoted, so the redirect becomes a program argument. The native GC log lines go to the app log instead. Publish these two columns as "not measured (known script issue)".
7. **May 2026 "Size App (MB)" of 164.6 for tuning, cds and leyden is inflated.** The old checkout's extracted folder holds 225 library JARs (three Spring Boot 4 versions). `java -Djarmode=tools extract --force` never deletes stale files. The fresh checkout has 93 JARs and 63.8 MB. Startup is not affected.
8. **JDK 27 baseline peak memory is higher.** 628 MB median (643 MB max) vs 440 MB on JDK 25, with the same `-Xmx768m`. Other variants are within about 50 MB. Watch this in the real benchmark.
9. **"Size Extra (MB)" is 0.0 for cds, leyden and crac** in both the old and the new runs. `compile-and-run.sh` measures sizes before `benchmark.sh` creates the archive, cache or checkpoint. Pre-existing.

## File index

| Path | Content |
|---|---|
| `jdk25/<label>.csv` | Track 25 results: baseline, tuning, cds, leyden, crac, graalvm |
| `jdk25/invalid/graalvm-attempt2-http500.csv` | Invalid GraalVM run (HTTP 500 on 9 of 11 pages). Record only. |
| `jdk27/<label>.csv` | Track 27 results: baseline, tuning, cds, leyden, crac |
| `logs/jdk25/` | Per-variant run logs and `progress.log` for track 25. `crac-attempt1.log` is the failed CRaC run. `graalvm-attempt2-invalid-http500.log` is the invalid GraalVM run. |
| `logs/jdk27/` | Per-variant run logs and `progress.log` for track 27 |
| `logs/native-build/` | Big-server GraalVM build logs (attempts 1 to 3) and the benchmark CSVs from the big server (`big-server-attempt2-invalid.csv`, `big-server-attempt3.csv`) |
| `logs/graalvm-ab/` | GraalVM A/B logs and CSVs (`may-2026-executable.csv`, `new-executable-attempt2.csv`). The two large app logs (about 610 KB) are not included. |
| `logs/mem.log` | Memory log of the small server during the run |
| `logs/chain.log`, `logs/chain-attempt1.log` | Orchestration logs (attempt 1 exited with exit 1 after 1 s) |
| `tools/` | Throwaway helper scripts used to drive this run: `run-track.sh`, `chain.sh`, `post-chain.sh`, `mem-logger.sh`, `graalvm-build.sh`, `ab.sh`. They are not part of the benchmark. They are stored unchanged. |

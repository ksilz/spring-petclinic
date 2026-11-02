# Verification run 2026-10-31 (not the official benchmark)

This is a smoke test after the upgrade to Spring Boot 4.1.2 with JDK 25.0.5 and JDK 27. It is NOT the official benchmark. The user runs the real benchmark later.

Do not quote these numbers as final results. Each variant had only 1 warm-up and 3 measured runs.

## What ran

- Method: `BENCH_WARMUPS=1 BENCH_RUNS=3`. This is a new environment override. The defaults stay at 3 warm-ups and 7 runs.
- The row `A` in each CSV is the trimmed mean (min and max dropped). With 3 runs it equals the median.
- Run host: the small server (AWS t3.small, 2 vCPU Intel Xeon Platinum 8259CL @ 2.50GHz, 1.9 GB RAM, 2 GB swap). This is the same host as the May 2026 run.
- CPU steal (`vmstat` st, from `logs/mem.log`): 606 samples from 2026-10-31T17:29:40Z to 20:12:30Z, average 0.50 %, maximum 26 % in a single sample at 20:01:01Z. The memory logger did not run during the later GraalVM reruns (23:48 UTC onwards), so there is no steal data for them.
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

The graalvm "Startup GCs" and "Benchmark GCs" columns in the CSV files were not measured in this run (script issue, fixed on 2026-11-01, see finding 6). The 0/0 values there are not data.

### GraalVM A/B on the small server

Both executables were run back to back on 2026-10-31, 22:00 to 22:21 UTC, with 1 warm-up and 3 runs each.

| Executable | Median (s) | Runs (s) |
|---|---|---|
| May 2026 executable | 0.283 | 0.279 / 0.303 / 0.283 |
| New executable (attempt 2) | 0.629 | 0.631 / 0.629 / 0.615 |

The attempt-2 executable (invalid, HTTP 500 on 9 of 11 pages) also ran on the big server (8 vCPU) at 0.311 s. The fixed attempt-3 executable started in 0.611 s on the small server (runs 0.604 / 0.611 / 0.697) and 0.295 s on the big server.

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

1. **GraalVM native build broken by CycloneDX 3.2.4.** Fixed in `62e0b4e` (the `cyclonedxDirectBom` task is realized eagerly in `build.gradle`). Since `53d0ad6` (2026-11-01) the plugin is 3.5.1 and the workaround is gone.
2. **CRaC training race.** `benchmark.sh` treated the checkpoint as finished as soon as any file appeared in `petclinic-crac/`. Zulu CRaC 25.0.4.1 (warp) writes `core.img.<random>`, logs "warp: Checkpoint successful!", keeps writing, then renames to `core.img`. The script sent TERM mid-write, the shutdown got baked into the image, and every restore ran the shutdown hooks and exited. Track 25 crac failed on the first attempt and passed after the fix (`8c005d0`, `87cf7b6`). Track 27 crac passed with the fix.
3. **GraalVM native image missing reflection registrations.** `MissingReflectionRegistrationError` for `org.thymeleaf.expression.Strings.listJoin` (40x), `Numbers.sequence` (30x) and `Temporals.format` (20x) gave HTTP 500 on 9 of 11 pages. The templates used these before the upgrade, but the new stack no longer covers them. The PGO training run hit the same 500s. Fixed in `6b52de8`.
4. **The benchmark accepted HTTP 500 pages as success.** `hit_urls` only aborted on 000. Fixed in `70ce917`: every URL must return 200 except `/oups` (500), otherwise the run fails.
5. **GraalVM startup is slower on the small server. Explained on 2026-11-01**, see [Follow-up 2026-11-01](#follow-up-2026-11-01): the new executable runs `schema.sql` and `data.sql` at startup, and `data.sql` is slow against the duplicate indexes in the small server's database. Original notes: New executable (attempt 2) 0.629 s vs May executable 0.283 s, back to back. The same attempt-2 executable needed 0.311 s on the 8-vCPU big server. The fixed attempt-3 executable behaves the same way: 0.611 s on the small server vs 0.295 s on the big server. So the slowdown is real and independent of the reflection bug. The A/B app logs (G1 GC log, before "Started"; startup excerpts in `logs/graalvm-ab/app-startup-excerpt-may.log` and `app-startup-excerpt-new.log`) show GC pauses of about 25 ms in total for both executables. The second young GC comes at 0.488 s (new) vs 0.223 s (May) after allocating about the same memory. That means about 0.3 s more application work between 0.06 s and 0.49 s, and it is slower on 2 vCPU. The new executable also runs 2 concurrent mark cycles during startup (May: 0). The invalid attempt 2 run (HTTP 500 on 9 of 11 pages) had a median of 0.614 s. It is kept for the record only, never as a result.
6. **Pre-existing, fixed on 2026-11-01 (`de3b237`, `b78735e`).** The GraalVM "Startup GCs" and "Benchmark GCs" columns were always 0/0. `benchmark.sh` puts `2>/tmp/gc_graalvm.log` inside `APP_CMD` and `TRAIN_CMD` and expands them unquoted, so the redirect becomes a program argument. The native GC log lines go to the app log instead (stdout; the executable ignores `-Xlog:gc:file=...`). `benchmark.sh` now reads them from there. The 0/0 values in this run and in May 2026 are not data.
7. **May 2026 "Size App (MB)" of 164.6 for tuning, cds and leyden is inflated.** The old checkout's extracted folder holds 225 library JARs (three Spring Boot 4 versions). `java -Djarmode=tools extract --force` never deletes stale files. The fresh checkout has 93 JARs and 63.8 MB. Startup is not affected.
8. **JDK 27 baseline peak memory is higher.** 628 MB median (643 MB max) vs 440 MB on JDK 25, with the same `-Xmx768m`. Other variants are within about 50 MB. Watch this in the real benchmark.
9. **"Size Extra (MB)" is 0.0 for cds, leyden and crac** in both the old and the new runs. `compile-and-run.sh` measures sizes before `benchmark.sh` creates the archive, cache or checkpoint. Pre-existing.

## Final check on the final commit (957a887, 2026-11-01)

After the main runs, a code review led to small fixes. The review is in `docs/reviews/REVIEW-run-upgrade-benchmarks-jdk25-jdk27.md`. None of the fixes changes the timing or the CSV output of a passing run.

- `f99d6a3` and `9e7695f` register Thymeleaf `#fields` (`org.thymeleaf.spring6.expression.Fields`) for native reflection. This is a safeguard. They also correct the hint comments.
- `7a8ad70` and `91df2ba` make `benchmark.sh` stop the app on every `hit_urls` failure. They also remove an old `petclinic-crac/` before CRaC training.
- `1e9631a` and `91df2ba` correct facts in the PRD.

Native build attempt 4 on the big server. The source includes the `Fields` hint from commit `7a8ad70`.

- Instrumented build: 11m 59s, peak RSS 20.00 GB.
- Optimized build: 7m 28s, peak RSS 10.33 GB.
- PGO training: all pages return 200, except `/oups` (500).
- Big-server check (1 warm-up + 3 runs): median 0.298 s. See `logs/native-build/big-server-attempt4.csv`.

Final end-to-end check on the small server, commit 957a887 (1 warm-up + 3 runs). This is verification only.

| Variant | Runs (s) | Median (s) | Notes |
|---|---|---|---|
| graalvm (attempt-4 executable) | 0.612 / 0.599 / 0.629 | 0.612 | all pages 200, /oups 500 |
| crac (JDK 25) | 0.065 / 0.083 / 0.075 | 0.075 | checkpoint image complete after 1 s (core.img 230,055,936 bytes, size stable) |

The GraalVM startup on the small server is still about 2.2x slower than the May build. Finding 5 was explained on 2026-11-01, see below.

Tests on the final commit 957a887 on the big server: 87 tests, 0 failures, 4 skipped (Docker-based MySQL and Postgres tests). This ran on JDK 25.0.5 and on JDK 27.

Cleanup happened afterwards. On both servers, `~/bench-runs`, the build output, the result CSVs, the CDS, Leyden and CRaC files, and the PGO profile were removed from `~/projects/petclinic-upgrade`. Both checkouts are clean at 957a887. Only the ignored `.gradle/` cache remains on the small server. The old checkouts in `~/projects/spring-petclinic` were not modified.

## Follow-up 2026-11-01

Code on branch `run-upgrade-benchmarks-jdk25-jdk27`, commits `53d0ad6` to `ef9e49d`. Evidence is in `logs/followup-2026-11-01/`. All runs below are diagnostics, not benchmark results.

### Cause of the GraalVM slowdown (finding 5)

- **The new executable runs `schema.sql` and `data.sql` at every startup. The May executable never ran them.** Upstream commit `a2c2ef9` (2026-05-27, "Register native resource hints for nested db/{h2,mysql,postgres}/ scripts") came in with the upgrade. Before it, the native image did not contain `db/postgres/*.sql`, so `spring.sql.init` found no scripts. The JVM variants always ran them (`spring.sql.init.mode=always` in `application-postgres.properties`). Evidence: `may-executable-sql-init-check.txt` (DEBUG log, 0 scripts, index count unchanged) and `startup-sql-init-excerpts.txt`.
- **`data.sql` is slow on the small server because its `petclinic` database carries thousands of duplicate indexes:** 591 copies each on `owners`, `specialties`, `types`, `vets` and `visits`, 1,182 on `pets` (4,137 in total). The old `schema.sql` had `CREATE INDEX ON vets (last_name)` without a name, so every startup that ran the scripts added another copy of each index. Upstream changed these to named `CREATE INDEX IF NOT EXISTS` statements, so no new copies appear, but the old ones stay. The 42 `INSERT ... WHERE NOT EXISTS (SELECT ...)` statements in `data.sql` all touch these tables; most likely Postgres spends the time planning them against all the copies (not profiled). The measurements show the effect: the same `data.sql` takes 14-15 ms on a clean database. The big server has 74 copies per table (518 in total), which is consistent with the same executable being fast there (`data.sql` was not timed there). Evidence: `duplicate-indexes-dry-run.txt`.
- **Not the cause:** CPU count (the May executable is fast on the same 2 vCPU), GC pauses (about the same) and the reflection bug (the fixed executable is just as slow).

Native executable on the small server, 5 interleaved rounds, same flags in every arm (listed in `native-ab-small-server.txt`):

| Arm | Median (s) | Runs (s) | `data.sql` |
|---|---|---|---|
| New executable, `petclinic` database (duplicate indexes) | 0.648 | 0.641 / 0.648 / 0.629 / 0.966 / 0.663 | 281-457 ms |
| New executable, clean scratch database | 0.357 | 0.345 / 0.384 / 0.355 / 0.357 / 0.357 | 14-15 ms |
| New executable, `petclinic` database, `--spring.sql.init.mode=never` | 0.323 | 0.323 / 0.319 / 0.323 / 0.338 / 0.321 | not run |
| May 2026 executable (never runs the scripts) | 0.292 | 0.723 (first start) / 0.285 / 0.292 / 0.332 / 0.287 | not run |

So the slowdown (0.648 s vs 0.292 s in this test) splits into:
- about 0.29 s: `data.sql` against the duplicate indexes (database state, not code);
- about 0.03 s: the two scripts on a clean database (the same work the JVM variants always did);
- about 0.03 s (+10%): the rest of the upgrade (Spring Boot 4.1.2, Hibernate 7.4, GraalVM 25.0.5), in line with the JVM variants.

The May 2026 graalvm result (0.278 s) skipped the SQL scripts that every JVM variant ran, so it is not comparable with the other variants or with a new run.

The JVM variants pay for the duplicate indexes too. With the JVM baseline settings, `data.sql` took 495-559 ms on the `petclinic` database (3,470 ms on the first start) and 86-109 ms on a clean one (`jvm-db-probe-small-server.txt`). That is about 0.4 s per startup: lost in the noise of baseline (about 14.7 s), but about 9% of leyden (4.6 s). Each JVM start in the May 2026 run still added one copy per index, and nobody knows how many copies existed then. So the share of the +5% to +10% in table (a) that comes from this is unknown.

### Before the official run

1. **Remove the duplicate indexes. Done on 2026-11-01** with the user's go-ahead, on both servers (the big server runs the PGO training). `tools/drop-duplicate-indexes.sql` kept the primary and unique keys and the named indexes from today's `schema.sql`: 4,152 to 15 indexes on the small server, 533 to 15 on the big server, row counts unchanged. `data.sql` through `psql` went from 0.32 s to 0.065 s on the small server (`index-drop-and-apt-timers.txt`). The old checkouts in `~/projects/spring-petclinic` still have the old `schema.sql`: running them against the `petclinic` database adds the copies again.
2. **Automatic updates.** On 2026-11-01, `unattended-upgrade` ran on both servers (`small-server-auto-updates.txt`, which covers both):
   - Small server, 06:41-06:52 UTC: it upgraded PostgreSQL 16.13 to 16.15, and systemd restarted PostgreSQL twice (06:48:18-22 and 06:49:37-40). A start at 06:48 failed with "Connection to localhost:5432 refused".
   - Big server, about 06:24-06:31 UTC: PostgreSQL 18.3 stayed, but it was restarted 10 times as libraries changed.
   - Both: glibc 2.39-0ubuntu8.7 to 8.9, OpenSSL 3.0.13-0ubuntu3.9 to 3.16, a new kernel 7.0.0-1014-aws installed. Both report a pending reboot (libc6, linux-image-7.0.0-1014-aws, linux-base).

   **Paused on 2026-11-01** with the user's go-ahead: `apt-daily.timer` and `apt-daily-upgrade.timer` are disabled on both servers, so they stay off after a reboot. Re-enable them after the official run with `sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer`. The "Versions" table above (PostgreSQL 16.13, glibc 8.7, kernel 6.17) no longer matches the servers, so record the versions again for the official run.
3. **Reboot both servers** (the user), so the new kernel and glibc are active, then record the versions.

### Other changes, verified

- **CycloneDX 3.5.1 (`53d0ad6`).** The full PGO native build on the big server passed without the workaround: instrumented build 11m 56s, optimized build 7m 33s (`big-server-native-build.log`). On the Mac, the `nativeCompile` dry run fails with 3.2.4 and passes with 3.5.1, `bootJar` embeds the same SBOM as with 3.2.4 (spec 1.6, 162 components), and two `bootJar` runs in a row reuse the configuration cache (`mac-cyclonedx-checks.txt`).
- **GraalVM GC columns (`de3b237`, `b78735e`).** The big-server check of that executable (1 warm-up + 3 runs, median 0.300 s) recorded 2 startup and 4 benchmark GC lines per run (`big-server-graalvm-smoke.csv`, run with `de3b237`; the current parser from `b78735e` gives the same 2/4 on that app log). The GC lines in `big-server-graalvm-gc-lines.txt` match: one pause before "Started" and two after it, two log lines each.
- **Smoke CSV name (`12d26ec`).** The same check wrote `result_graalvm_smoke.csv`, not `result_graalvm.csv`.
- **Template hint scan (`9c4f779`, `ef9e49d`).** `PetClinicRuntimeHintsTests.everyTemplateHelperUseIsInvocable` fails with the `Temporals` hint removed and with an added `${#execInfo.templateName}`, and ignores CSS such as `#navbar.active`.
- **Failure paths (`bd04d84`, `fc24b83`), the last two review items.** `stop_app_after_failure` now stops the launcher's whole process tree, so a wrong `app_pid` no longer leaves the app running on port 8080 (2 s instead of 37 s in the test). `wait_for_port_free` stops only the process that holds port 8080, and only if its command line is a benchmark app (`-jar ...spring-petclinic`, `nativeCompile/spring-petclinic` or `petclinic-crac`). Tested on the small server with a stand-in app in 7 cases, including an app two levels below `/usr/bin/time` (`failure-path-tests.txt`, `tools/failpath-test.sh`). A passing run never reaches this code.
- **Tests on `ef9e49d`** (big server): 88 tests, 0 failures on JDK 25.0.5 and on JDK 27. The 4 Docker-based MySQL and Postgres tests are skipped (no Docker on the server).

## File index

| Path | Content |
|---|---|
| `jdk25/<label>.csv` | Track 25 results: baseline, tuning, cds, leyden, crac, graalvm |
| `jdk25/invalid/graalvm-attempt2-http500.csv` | Invalid GraalVM run (HTTP 500 on 9 of 11 pages). Record only. |
| `jdk27/<label>.csv` | Track 27 results: baseline, tuning, cds, leyden, crac |
| `logs/jdk25/` | Per-variant run logs and `progress.log` for track 25. `crac-attempt1.log` is the failed CRaC run. `graalvm-attempt2-invalid-http500.log` is the invalid GraalVM run. |
| `logs/jdk27/` | Per-variant run logs and `progress.log` for track 27 |
| `logs/native-build/` | Big-server GraalVM build logs (attempts 1 to 3) and the benchmark CSVs from the big server (`big-server-attempt2-invalid.csv`, `big-server-attempt3.csv`) |
| `logs/graalvm-ab/` | GraalVM A/B logs and CSVs (`may-2026-executable.csv`, `new-executable-attempt2.csv`). The two large app logs (about 610 KB) are not included. `app-startup-excerpt-may.log` (88 lines) and `app-startup-excerpt-new.log` (111 lines) hold the app log of each A/B executable up to and including the "Started PetClinicApplication" line. They back the GC claims in finding 5. |
| `logs/mem.log` | Memory log of the small server during the run |
| `logs/chain.log`, `logs/chain-attempt1.log` | Orchestration logs (attempt 1 exited with exit 1 after 1 s) |
| `tools/` | Throwaway helper scripts used to drive this run: `run-track.sh`, `chain.sh`, `post-chain.sh`, `mem-logger.sh`, `graalvm-build.sh`, `ab.sh`. They are not part of the benchmark. They are stored unchanged. |
| `final/graalvm.csv`, `final/crac.csv` | Final check on commit 957a887 (1 warm-up + 3 runs, track 25). Verification only. |
| `logs/final/` | Logs of the final check: `graalvm.log`, `crac.log`, `progress.log`, `chain.log` |
| `logs/native-build/graalvm-build-attempt4.log` | Big-server GraalVM build log, attempt 4 (the executable used in the final check) |
| `logs/native-build/big-server-attempt4.csv` | Big-server check of the attempt-4 executable (1 warm-up + 3 runs) |
| `tools/final-check.sh` | Throwaway script that ran the final check. Not part of the benchmark. |
| `logs/followup-2026-11-01/` | Evidence for the follow-up of 2026-11-01: native A/B, JVM database probe, SQL-init log excerpts, May-executable check, duplicate-index dry run, automatic updates on both servers, index drop and apt timers, failure-path tests, CycloneDX checks on the Mac, big-server native build log, smoke CSV and GC lines |
| `tools/startup-probe.sh` | Throwaway diagnostic: starts an executable N times and records the startup time and the SQL script times. Not part of the benchmark. |
| `tools/duplicate-indexes.sql` | Read-only query that counts duplicate indexes per table. Not part of the benchmark. |
| `tools/drop-duplicate-indexes.sql` | Drops those duplicates (used once on 2026-11-01, see `index-drop-and-apt-timers.txt`). Not part of the benchmark. |
| `tools/failpath-test.sh` | Throwaway test of the `benchmark.sh` failure-path helpers with a stand-in app on port 8080. Not part of the benchmark. |

# Official run 2026-11-02/03: Spring Boot 4.1.2, JDK 25 and JDK 27

The full benchmark with the default run counts (3 warm-ups + 7 measured runs per variant), for the W-JAX 2026 talk "Wie kann ich Java schneller starten". It replaces the run of 2026-11-01 (`../2026-11-01-boot-4.1.2-jdk25-jdk27/`): same code, JDKs and servers, but measured with the fixed `benchmark.sh` (commit `392548b`). That fix:

- **GC pauses:** it counts one per pause (the old script counted log lines, two per pause), and it splits startup and benchmark pauses at millisecond precision (before: whole seconds).
- **Startup from process start:** it records the startup time counted from process start.
- **Per-run logs:** it keeps every run's logs.

The German single-file report with all results, charts and the numbers for Keynote is [`benchmark-bericht.html`](benchmark-bericht.html).

## Results (row A = trimmed mean: per column, the lowest and the highest value are dropped)

| Variant | JDK 25 startup | JDK 27 startup | JDK 25 from process start | JDK 27 from process start | JDK 25 memory | JDK 27 memory | JDK 25 GC pauses startup / benchmark | JDK 27 GC pauses startup / benchmark |
|---|---|---|---|---|---|---|---|---|
| Baseline | 13.417 s | 13.980 s | 14.621 s | 15.268 s | 443 MB | 503 MB | 18 / 2 | 17.2 / 1 |
| Tuning | 9.115 s | 8.927 s | 9.888 s | 9.522 s | 414 MB | 455 MB | 14 / 1 | 12.4 / 1 |
| Tuning + CDS | 5.301 s | 5.449 s | 5.666 s | 5.871 s | 398 MB | 371 MB | 2 / 1 | 2.4 / 0.8 |
| Tuning + Leyden | 4.199 s | 3.915 s | 4.907 s | 4.421 s | 360 MB | 342 MB | 2 / 0 | 2 / 0 |
| CRaC | 0.084 s | 0.088 s | 0.084 s | 0.088 s | 387 MB | 373 MB | 0 / 0 | 0 / 0 |
| GraalVM | 0.338 s | n/a | 0.343 s | n/a | 200 MB | n/a | 4 / 4 | n/a |

**Columns:**
- **Startup** is Spring's "Started PetClinicApplication in X seconds", counted from `SpringApplication.run()`, as on the May slides. CRaC uses "restored JVM running for X ms".
- **From process start** is "(process running for Y)" on the same line, so it includes JVM boot and everything before `main`, such as loading the CDS archive or the Leyden cache. CRaC already counts from process start, so both columns are the same there.
- **GC pauses** include the Remark and Cleanup pauses of G1's concurrent marking cycles.

**Sizes (JDK 25 / JDK 27):**

| Artifact | JDK 25 | JDK 27 |
|---|---|---|
| Boot JAR | 63.9 MB | 63.9 MB |
| Extracted app JAR | 1.0 MB | 1.0 MB |
| 93 library JARs | 62.8 MB | 62.8 MB |
| CDS archive | 105.5 MB | 105.0 MB |
| Leyden AOT cache | 133.8 MB | 142.5 MB |
| CRaC checkpoint | 230.3 MB | 380.5 MB |
| GraalVM native executable | 185.3 MB | n/a |
| PGO profile | 41.0 MB | n/a |

**Native build on the big server:** the instrumented build took 12:06 min (peak RSS 19.51 GB), the optimized build 7:41 min (10.40 GB).

## Checks

- **CSV vs. logs:** every CSV value of all 77 measured runs matches that run's logs in `jdk25/run-logs/` and `jdk27/run-logs/`. That covers startup time, peak memory from `/usr/bin/time`, GC pauses with the startup/benchmark split recomputed independently, and the time from process start.
- **Exit codes:** all 11 variants exited 0 with valid CSVs (`chain.log`, `jdk25/progress.log`, `jdk27/progress.log`).

## Observations

- **Memory on JDK 27, Baseline:** two levels, 4 runs at 427-431 MB and 3 runs at 612-624 MB.
  - The GC logs show the cause: in the high runs G1 grew the heap from 258 MB to 445-462 MB, in the low runs it did not.
  - Tuning on JDK 27 grew the heap to 462 MB in all 7 runs (451-466 MB RSS).
  - On JDK 25 the heap stayed at 258 MB in every run.
  - Baseline's row A on JDK 27 keeps two high values (503 MB); the median is 431 MB.
- **Slow runs:** 8 of 77 runs are more than 8 % slower than their variant's median.
  - Each is the slowest run of its variant, so none is in row A.
  - The biggest is GraalVM run 4: 0.975 s against a median of 0.339 s. The whole process ran about three times slower, the GC pauses too.
  - `mem.log` (vmstat every 15 s) shows no CPU steal, disk reads or I/O wait near any of these runs, so the cause is unknown.
- **CPU steal:** mean 0.32 %, max 46 % (1,307 samples).
- **Swap:** at most 16 MB used on the JDK 25 track, up to 65 MB on the JDK 27 track.
- **GC split on JDK 27 CDS:** the split now varies between 2 / 1 and 3 / 0 at millisecond precision, so one pause really falls just before or just after the end of startup.
- **Compared with 2026-11-01:** the GC split is now exact. Leyden on JDK 25 is 2 / 0 in every run (2026-11-01: 1.5 / 0.5 after halving), so the old flip-flop was the whole-second rounding.
  - **Startup time:** 10 of 11 variants are 0.1-8 % faster than on 2026-11-01 (largest: JDK 27 CDS 5.935 to 5.449 s, JDK 27 Tuning 9.588 to 8.927 s). JDK 27 CDS has much less spread: 5.16-6.22 s, against 6.6-7.6 s for three runs on 2026-11-01. JDK 25 CRaC is slower: 0.084 s vs 0.077 s (+10 %).

## How it ran

- **Servers:**
  - The small server (AWS t3.small, 2 vCPU, 2 GB RAM, 1.9 GB usable) runs all benchmarks.
  - The big server (t3.2xlarge, 8 vCPU, 32 GB RAM, 31 GB usable) builds the GraalVM native executable with PGO. The executable is copied to the small server, with checksums verified.
- **Code:** branch `run-upgrade-benchmarks-jdk25-jdk27`, commit `7785519`.
- **Exact versions:** in `versions-small-server.txt` and `versions-big-server.txt`. They are the same as on 2026-11-01:
  - Temurin 25.0.5+8 and 27+35;
  - Zulu CRaC 25.0.4.1 and 27;
  - Oracle GraalVM 25.0.5.0.3;
  - PostgreSQL 16.15;
  - kernel 7.0.0-1014-aws, glibc 2.39-0ubuntu8.9.
- **Before the run:**
  - Both servers were stopped and started by the user (new IP addresses).
  - The apt timers were disabled for the run; they were re-enabled afterwards.
  - The `petclinic` database had 15 indexes, so no duplicates.
- **Timeline (UTC):**
  - The GraalVM build ran 22:15-22:50 on 2026-11-02.
  - The chain ran 22:17 on 2026-11-02 to 04:06 on 2026-11-03.
  - JDK 25 JVM variants: 22:17-00:58.
  - GraalVM: 00:58-01:26.
  - JDK 27: 01:26-04:06.

## Files

| Path | Content |
|---|---|
| `benchmark-bericht.html` | German report (single file, works offline). A copy is in the talk's Keynote folder as "Benchmark-Bericht 2026-11-02.html". |
| `jdk25/<label>.csv`, `jdk27/<label>.csv` | Result CSVs, 9 columns (renamed from `result_<label>[_jdk27].csv`, which `.gitignore` ignores) |
| `jdk25/run-logs/<label>/`, `jdk27/run-logs/<label>/` | Every measured run: `run-<n>-app.log`, `run-<n>-gc.log` (not GraalVM: its GC lines are in the app log), `run-<n>-time.log` (`/usr/bin/time -v`) |
| `jdk25/`, `jdk27/` | Per variant: runner log `<label>.log`, training app log, last app and GC log; `sizes.txt`; `progress.log` |
| `graalvm-build.log`, `big-server-graalvm-smoke.csv` | Native build on the big server and its 1 + 3 check run there |
| `chain.log`, `chain-stdout.log`, `mem.log` | Orchestration and memory / CPU steal log |
| `versions-small-server.txt`, `versions-big-server.txt` | Pre-flight: exact versions and host state |
| `tools/` | Throwaway run scripts (`chain.sh`, `run-track.sh`, `mem-logger.sh`, `preflight.sh`, `graalvm-build.sh`, the Mac-side watchers), `test-gc-extraction.sh` (tests `benchmark.sh`'s extraction functions against saved logs), and the report generator |

Regenerate the report from the repository root:

```bash
python3 docs/benchmark-results/2026-11-02-boot-4.1.2-jdk25-jdk27/tools/make_report.py \
  --results docs/benchmark-results/2026-11-02-boot-4.1.2-jdk25-jdk27 --repo . \
  --template docs/benchmark-results/2026-11-02-boot-4.1.2-jdk25-jdk27/tools/report-template.html \
  --out docs/benchmark-results/2026-11-02-boot-4.1.2-jdk25-jdk27/benchmark-bericht.html
```

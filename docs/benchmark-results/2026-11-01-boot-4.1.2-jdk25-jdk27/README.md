# Official run 2026-11-01: Spring Boot 4.1.2, JDK 25 and JDK 27

The full benchmark with the default run counts (3 warm-ups + 7 measured runs per variant), for the W-JAX 2026 talk "Wie kann ich Java schneller starten". The German single-file report with all results, charts and the numbers for Keynote is [`benchmark-bericht.html`](benchmark-bericht.html).

## Results (row A = trimmed mean without the fastest and slowest run)

| Variant | JDK 25 startup | JDK 27 startup | JDK 25 memory | JDK 27 memory | JDK 25 GCs startup / benchmark | JDK 27 GCs startup / benchmark |
|---|---|---|---|---|---|---|
| Baseline | 13.756 s | 13.991 s | 442 MB | 469 MB | 34 / 5 | 34 / 2.4 |
| Tuning | 9.240 s | 9.588 s | 411 MB | 481 MB | 28 / 2 | 26.4 / 1.2 |
| Tuning + CDS | 5.629 s | 5.935 s (rerun) | 399 MB | 371 MB | 4 / 2 | 4.4 / 1.6 |
| Tuning + Leyden | 4.331 s | 4.088 s | 370 MB | 346 MB | 3 / 1 | 2.8 / 1.2 |
| CRaC | 0.077 s | 0.091 s | 387 MB | 375 MB | 0 / 0 | 0 / 0 |
| GraalVM | 0.354 s | n/a | 200 MB | n/a | 8 / 8 | n/a |

Sizes (JDK 25 / JDK 27): boot JAR 63.9 / 63.9 MB; extracted app JAR 1.0 MB plus 93 library JARs 62.8 MB; CDS archive 105.5 / 105.0 MB; Leyden AOT cache 133.7 / 142.6 MB; CRaC checkpoint 222.7 / 379.3 MB; GraalVM native executable 185.4 MB (PGO profile 41.1 MB). Native build on the big server: instrumented 11:52 min (peak RSS 19.45 GB), optimized 7:22 min (9.16 GB).

## How it ran

- Small server (AWS t3.small, 2 vCPU, 1.9 GB RAM) runs all benchmarks; the big server (t3.2xlarge, 8 vCPU, 31 GB RAM) builds the GraalVM native executable with PGO, which is copied over (checksums verified).
- Code: branch `run-upgrade-benchmarks-jdk25-jdk27`, commit `58f09f3`. Exact versions: `versions-small-server.txt`, `versions-big-server.txt` (Temurin 25.0.5+8 and 27+35, Zulu CRaC 25.0.4.1 and 27, Oracle GraalVM 25.0.5.0.3, PostgreSQL 16.15, kernel 7.0.0-1014-aws, glibc 2.39-0ubuntu8.9).
- Before the run: both servers rebooted, apt timers disabled, 4,137 duplicate indexes removed from the small server's `petclinic` database (see the 2026-10-31 verification README, "Follow-up 2026-11-01").
- Chain 08:25-14:15 UTC, all 11 variants exit 0 with valid CSVs (`chain.log`, `jdk25/progress.log`, `jdk27/progress.log`).
- CPU steal (`mem.log`, vmstat every 15 s): mean 0.68 %, short spikes up to 64 %, no trend over the day; average CPU load per variant 0.4-14 %, below the t3.small baseline of 20 %.
- **Rerun:** Tuning + CDS on JDK 27 was measured again at 14:20-14:54 UTC, because runs 5-7 of the first attempt were slow (6.9 / 6.6 / 7.6 s vs about 5.5 s) and row A sat 6.5 % above the median. First attempt: A 6.022 s, median 5.655 s (`jdk27/first-attempt/`). Rerun: A 5.935 s, median 5.995 s. Both attempts scatter more than the other variants; the report uses the rerun.

## Files

| Path | Content |
|---|---|
| `benchmark-bericht.html` | German report (single file, works offline). A copy is in the talk's Keynote folder. |
| `jdk25/<label>.csv`, `jdk27/<label>.csv` | Result CSVs (renamed from `result_<label>[_jdk27].csv`, which `.gitignore` ignores) |
| `jdk25/`, `jdk27/` | Per variant: runner log `<label>.log`, last app log of the measured runs, training app log, last JVM GC log; `sizes.txt` (artifact sizes after each variant); `progress.log` |
| `jdk27/first-attempt/` | First attempt of Tuning + CDS on JDK 27 |
| `graalvm-build.log`, `big-server-graalvm-smoke.csv` | Native build on the big server and its 1 + 3 check run there |
| `chain.log`, `chain-stdout.log`, `rerun.log`, `rerun-stdout.log`, `mem.log` | Orchestration and memory / CPU steal log |
| `versions-small-server.txt`, `versions-big-server.txt` | Pre-flight: exact versions and host state |
| `tools/` | Throwaway run scripts (`chain.sh`, `run-track.sh`, `rerun-cds27.sh`, `mem-logger.sh`, `preflight.sh`, `graalvm-build.sh`, the Mac-side watchers) and the report generator |

Regenerate the report from the repository root:

```bash
python3 docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27/tools/make_report.py \
  --results docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27 --repo . \
  --template docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27/tools/report-template.html \
  --out docs/benchmark-results/2026-11-01-boot-4.1.2-jdk25-jdk27/benchmark-bericht.html --commit 58f09f3
```

# Official run 2026-11-01: Spring Boot 4.1.2, JDK 25 and JDK 27

The full benchmark with the default run counts (3 warm-ups + 7 measured runs per variant), for the W-JAX 2026 talk "Wie kann ich Java schneller starten". The German single-file report with all results, charts and the numbers for Keynote is [`benchmark-bericht.html`](benchmark-bericht.html).

## Results (row A = trimmed mean: per column, the lowest and the highest value are dropped)

GC columns are pauses: the CSV columns count GC log lines that contain "Pause", and G1 writes two per pause, so the values here and in the report are the CSV values divided by 2.

| Variant | JDK 25 startup | JDK 27 startup | JDK 25 memory | JDK 27 memory | JDK 25 GC pauses startup / benchmark | JDK 27 GC pauses startup / benchmark |
|---|---|---|---|---|---|---|
| Baseline | 13.756 s | 13.991 s | 442 MB | 469 MB | 17 / 2.5 | 17 / 1.2 |
| Tuning | 9.240 s | 9.588 s | 411 MB | 481 MB | 14 / 1 | 13.2 / 0.6 |
| Tuning + CDS | 5.629 s | 5.935 s (rerun) | 399 MB | 371 MB | 2 / 1 | 2.2 / 0.8 |
| Tuning + Leyden | 4.331 s | 4.088 s | 370 MB | 346 MB | 1.5 / 0.5 | 1.4 / 0.6 |
| CRaC | 0.077 s | 0.091 s | 387 MB | 375 MB | 0 / 0 | 0 / 0 |
| GraalVM | 0.354 s | n/a | 200 MB | n/a | 4 / 4 | n/a |

Read these numbers with the caveats below (from an audit of the report against the raw data on 2026-11-02):

- **Startup time** is the value the app reports, as in May. JVM variants and GraalVM: Spring's "Started PetClinicApplication in X seconds", which starts counting when Spring Boot starts, so JVM boot is not included (0.4-1.4 s in the last runs, most for Baseline; 6 ms for GraalVM). CRaC: "restored JVM running for X ms", counted from process start.
- **GC split:** for the JVM variants, `benchmark.sh` splits startup and benchmark pauses at whole-second precision. A pause in the same second as startup counts as benchmark, and a pause across a second boundary counts half on each side. The total is right. Example: JDK 27 Baseline run 7 is 17 / 2 pauses in the CSV, 18 / 1 exactly. Only the last run's logs were kept, so runs 1-6 can't be corrected. GraalVM splits at millisecond precision.
- **Pauses** include the Remark and Cleanup pauses of G1's concurrent marking cycles (6 of 19 pauses for Baseline, 4 of 8 for GraalVM in the last runs; none for CDS and Leyden).
- **Memory on JDK 27** has two levels for Baseline (5 runs 427-434 MB, 2 runs 619/620 MB) and Tuning (4 runs 447-458 MB, 3 runs 525-536 MB). Row A keeps one high value for Baseline and two for Tuning; the medians are 433 and 458 MB. JDK 25 shows no such split.
- **GraalVM** runs with a 128 MB max heap (set at build time, on purpose) plus about 83 MB of build-time objects; the JVM variants run with `-Xms256m -Xmx768m`.
- **Swap:** at most 3 MB used on the JDK 25 track, up to 84 MB on the JDK 27 track.
- **CPU steal** explains only some slow runs: 3 of them show a steal spike in `mem.log` (sampled every 15 s), the others don't.

Sizes (JDK 25 / JDK 27): boot JAR 63.9 / 63.9 MB; extracted app JAR 1.0 MB plus 93 library JARs 62.8 MB; CDS archive 105.5 / 105.0 MB; Leyden AOT cache 133.7 / 142.6 MB; CRaC checkpoint 222.7 / 379.3 MB; GraalVM native executable 185.4 MB (PGO profile 41.1 MB). Native build on the big server: instrumented 11:52 min (peak RSS 19.45 GB), optimized 7:22 min (9.16 GB).

## How it ran

- Small server (AWS t3.small, 2 vCPU, 2 GB RAM, 1.9 GB usable) runs all benchmarks; the big server (t3.2xlarge, 8 vCPU, 32 GB RAM, 31 GB usable) builds the GraalVM native executable with PGO, which is copied over (checksums verified).
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

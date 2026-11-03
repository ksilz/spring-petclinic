# Benchmark Results

This folder holds archived benchmark result files (CSV files, logs, helper scripts) with a README per run.

Each run has its own folder named `<date>-<description>`. Inside, every variant has one CSV file named after its label (`baseline.csv`, `tuning.csv`, `cds.csv`, `leyden.csv`, `crac.csv`, `graalvm.csv`).

Since 2026-11-02 the CSVs have 9 columns (GC pauses, startup from process start) and each run folder has `run-logs/` with every measured run's logs. The benchmark scripts write `result_<label>.csv` (track 27: `result_<label>_jdk27.csv`; smoke tests add `_smoke`). These files are not stored under that name here because the repository `.gitignore` ignores `result_*.csv`. They were renamed to `<label>.csv` when copied.

Runs:

- `2026-05-01-boot-4.0.3-jdk25/` - full run (3 warm-ups + 7 runs) on Spring Boot 4.0.3 and JDK 25.0.3.
- `2026-10-31-verification-boot-4.1.2/` - verification run (1 warm-up + 3 runs) on Spring Boot 4.1.2, JDK 25.0.5 and JDK 27. Not the official benchmark.
- `2026-11-01-boot-4.1.2-jdk25-jdk27/` - full run (3 warm-ups + 7 runs) on Spring Boot 4.1.2, JDK 25.0.5 and JDK 27. Superseded: its GC columns count log lines (two per pause) split at whole-second precision.
- `2026-11-02-boot-4.1.2-jdk25-jdk27/` - **official run** (3 warm-ups + 7 runs) on the same setup with the fixed `benchmark.sh`: GC pauses split at millisecond precision, startup time from process start, logs of every run. German report `benchmark-bericht.html`.

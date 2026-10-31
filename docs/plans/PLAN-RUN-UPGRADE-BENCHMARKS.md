# Implementation Plan: RUN-UPGRADE-BENCHMARKS

## Business Summary
The PetClinic fork moved to newer Spring Boot, Gradle and Java versions. We now re-measure startup time for all six speed-up techniques on Java 25 and compare to the May 2026 results. We also measure the new Java 27 on five of them. The outcome is a published, reproducible comparison that shows what the upgrade changed.

## Technical Summary
Run `compile-and-run.sh` per variant on the small server (t3.small) via a throwaway runner script outside the repo. Build the GraalVM executable once on the big server (t3.2xlarge), copy it over, and benchmark it on the small server. Track 25 takes about 3.5 h, track 27 about 3 h. Collect the CSVs, compute medians and deltas against the old run (read from the small server's old checkout), and record results plus tested versions under `docs/benchmark-results/`, `specs/Startup-Benchmark-PRD.md` and `docs/specs/SPECS-overview.md`. No code changes.

## Decisions for the user
1. **GraalVM on the small server** runs via a direct `benchmark.sh` call, not `compile-and-run.sh`. Its graalvm branch runs `./gradlew clean nativeCompile` (needs ~24 GB, deletes the copied binary). Same measurement, no methodology change. Deviates from "run compile-and-run.sh for all six". Needs approval.
2. **Old results source** is the small server's old checkout `~/projects/spring-petclinic/result_*.csv` (at f8b1e65 = tag `pre-upgrade-boot-4.0.3`). The tag itself holds no CSVs (`result_*.csv` is git-ignored).
3. **Continue-on-failure** per variant: record the failure, move on, do not retry, do not patch. A variant is OK only with exit 0, a fresh CSV, 7 numeric startup times and an A row. Environment errors (wrong JDK, busy port 8080, missing or mismatched native files) abort the whole track instead.
4. **Results stored renamed** as `<label>.csv` under `docs/benchmark-results/<dated-folder>/`. Avoids the `result_*.csv` ignore rule and `git add -f`.
5. **No test-suite re-run.** Only docs/CSV/log files change. The 81 tests already passed on both JDKs on the big server.
6. **GraalVM GC columns cannot be measured.** A pre-existing script bug (benchmark.sh 164-165 put `2>/tmp/gc_graalvm.log` inside `APP_CMD`/`TRAIN_CMD`; ~line 1295 expands `$APP_CMD` unquoted, so the redirect becomes a program argument) means the GC log is never written. `extract_gc_counts_graalvm` (~420-426) returns 0,0. The May 2026 CSV shows 0/0 too. We publish these two columns as "not measured (known script issue)". We fix the script only if the user asks, as a separate change.

Start gates (each needs an explicit user OK): big-server GraalVM build, track 25, track 27, any reboot, any script change, push.

## Test Command
`./gradlew test -x checkstyleNohttp`

Not re-run in this task. See Verification.

## Tasks

### 1. Pre-flight
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

- [ ] Mac: confirm branch is `run-upgrade-benchmarks-jdk25-jdk27`, HEAD `ae973f9` (a state-file commit) on top of `af0f48f`. Expected untracked: `claude.bpf.json`, `docs/profiles/`, and this plan file until it is committed.
- [ ] Never run `compile-and-run.sh` on the Mac (it `kill -9`s all Java processes).
- [ ] Every ssh/scp command spells out literally `-i ~/.ssh/AWS-Better-Projects-Faster-GmbH.pem -o IdentitiesOnly=yes -o BatchMode=yes`. No ssh options in shell variables (zsh does not word-split).
- [ ] Both servers: `ps -eo args | grep "[j]ava"` and `jps` show no Java process. Do not use `pgrep -f` with the pattern on the command line.
- [ ] Both servers: `free -m`, `df -h /home`. Small: at least 5 GB free, swap 2 GB. Big: ~31 GB free, no swap.
- [ ] Both servers: Postgres up, db `petclinic` reachable (`pg_isready`, `psql -l`). Big runs 18, small runs 16.
- [ ] Both servers: `~/projects/petclinic-upgrade` is at `af0f48f` (`ae973f9` adds only state files), `git status --short` clean at the start. After crac runs it legitimately shows ` D petclinic-crac/test.txt` plus untracked `petclinic-crac/`, `petclinic.aotconf` etc. Expected and harmless.
- [ ] Both servers: snapshot the OLD checkout `~/projects/spring-petclinic` read-only (`git status --short`, `ls -la`) to a Mac scratchpad file. It already has uncommitted/untracked state. The end-of-run check compares against this snapshot. Never touch that checkout.
- [ ] Both servers: tool check. `/usr/bin/time`, `ss`, `curl`, `stdbuf`, `pgrep`, `python3` exist. `jcmd` appears only after `sdk use` activates a JDK; check it then.
- [ ] Both servers: record `/etc/os-release`, `ldd --version | head -1` (glibc) and `lscpu | grep 'Model name'`. The native binary is built on the big server and run on the small one. Both hosts go into the docs.
- [ ] Both servers: `source ~/.sdkman/bin/sdkman-init.sh && sdk list java | grep` confirms each pin is installed: `25.0.5.0+8-tem`, `25.0.4.1-crac+1-zulu`, `25.0.5.0+3-graal`, `27.0.0.0+35-tem`, `27.0.0.0-crac+35-zulu`. Report missing ones. Do not install without asking.
- [ ] Small: confirm CRIU 4.1.1 (`criu --version`) and the CRaC prerequisites the PRD names.
- [x] Old results copied to the Mac scratchpad folder `old-2026-05/` (six files, read-only copy).
- [ ] Sanity-check old averages (column A): baseline 13.317, tuning 8.903, cds 5.552, leyden 4.215, crac 0.089, graalvm 0.287 s.
- [ ] Present the time estimate: per variant 33-40 min (10 runs x ~3 min + build 2-3 min + training 3-6 min). Track 25 ≈ 3.5 h (graalvm benchmark-only ≈ 30 min). Track 27 ≈ 3 h. Big-server build ≈ 40-50 min, can overlap the first small-server variants.

### 2. Runner script and memory logger on the small server
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

Throwaway ops script. NOT a repo file. Lives at `~/bench-runs/run-track.sh` on the small server, outside both checkouts.

- [ ] Args: track (25|27) plus a variant list. Reject anything else.
- [ ] Header: `source ~/.sdkman/bin/sdkman-init.sh` first, then `set -uo pipefail` (sdkman trips on unset variables). No `set -e` around the variant command. Capture its exit code.
- [ ] Environment errors ABORT the whole track. Write `TRACK <t> ABORTED <reason> <iso>` and stop. Causes: `sdk use` fails; `java --version` major differs from the track (skip for graalvm); port 8080 busy before a variant (`ss -tln | grep -q ':8080 '`); graalvm binary or `default.iprof` missing; sha256 mismatch against `~/bench-runs/native/SHA256SUMS`.
- [ ] Variant errors (non-zero exit or bad CSV) are recorded and the runner CONTINUES with the next variant. No retry, no patching.
- [ ] Per variant: `sdk use java <pin>`, print `java --version`, `cd ~/projects/petclinic-upgrade`, `rm -f /tmp/gc_<label>.log`. Before leyden also `rm -f petclinic.aotconf` (compile-and-run.sh 423-428 deletes only `petclinic.aot`; a stale config from a failed record step could leak into the next track).
- [ ] Run `JDK_TRACK=<t> ./compile-and-run.sh <label>`. stdout+stderr go to `~/bench-runs/jdk<t>/<label>.log`.
- [ ] graalvm (track 25 only): `mkdir -p build/native/nativeCompile src/pgo-profiles/main`. Copy the binary and `default.iprof` from `~/bench-runs/native/` to `build/native/nativeCompile/spring-petclinic` and `src/pgo-profiles/main/`. `chmod +x` the binary. Verify sha256. Compute sizes like `get_variant_sizes` (`du -sk`, /1024, 1 decimal). Then, from the repo root (benchmark.sh hardcodes `./build/...`) with `JDK_TRACK` exported, call exactly: `./benchmark.sh build/native/nativeCompile/spring-petclinic graalvm "-Dspring.aot.enabled=true" "" <appMB> <extraMB>`. `default.iprof` is git-ignored. Every other variant's `clean` wipes `build/`, so graalvm always runs in its own invocation after staging.
- [ ] Progress lines in `~/bench-runs/jdk<t>/progress.log`: `VARIANT <label> START <iso>`, `VARIANT <label> EXIT <code> CSV <ok|missing|bad:<reason>> <iso>`, and `TRACK <t> DONE <iso>` or `TRACK <t> ABORTED <reason> <iso>`.
- [ ] CSV check. Exit 0 without a CSV comes from compile-and-run.sh `continue` paths (≈ lines 313, 347, 365, 384, 396, 444, 473, 485). The "CRaC training failed" paths in benchmark.sh exit 1. Variant is OK only if: exit 0; CSV (`result_<label>.csv` or `result_<label>_jdk27.csv`) mtime after START; rows 1..7 present in order plus an A row; startup time (col 2) and max memory (col 3) numeric on rows 1-7; each row's "Ran at" (col 6) after START; for graalvm the A-row Size App > 0. Otherwise `CSV bad:<reason>`, or `missing` if no file.
- [ ] Do not set `WARMUPS` or `RUNS`. They are hardcoded (benchmark.sh 200-201), so changing them is a script change. Ask the user first. `SKIP_LEYDEN_AOT` is not implemented (only echoed in a warning, benchmark.sh 213-215). Do not use it.
- [ ] Launch: `nohup setsid bash ~/bench-runs/run-track.sh <t> <variants> >~/bench-runs/jdk<t>/runner.out 2>&1 &`. An SSH drop must not kill it.
- [ ] Memory logger, same detached launch: `free -m` plus `vmstat` every 15 s to `~/bench-runs/mem.log`. Runs for the track's lifetime. Main purpose: diagnose the Leyden hang risk.
- [ ] Dry check before the real launch: `bash -n` on the script, and run it with an invalid track to confirm rejection.

### 3. Track 25 GraalVM build on the big server
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

- [ ] ASK USER before starting. The build is memory-heavy (~24 GB).
- [ ] `source ~/.sdkman/bin/sdkman-init.sh && sdk use java 25.0.5.0+3-graal`, `cd ~/projects/petclinic-upgrade`.
- [ ] Check `java --version` contains "Oracle GraalVM". Otherwise compile-and-run.sh 335-347 silently skips the build with exit 0. Then `mkdir -p ~/bench-runs/jdk25`.
- [ ] Run `JDK_TRACK=25 ./compile-and-run.sh graalvm` detached (`nohup setsid`), log to `~/bench-runs/jdk25/graalvm-build.log` on the big server.
- [ ] The script does an instrumented native compile, a PGO training run against the big server's own `petclinic` Postgres (all benchmark URLs are GETs, no write or duplicate-key risk), moves `default.iprof` to `src/pgo-profiles/main/`, then an optimized rebuild.
- [ ] It then also benchmarks on the big server. That result is not used. It is harmless. Do not copy it into the comparison.
- [ ] Monitor with a background until-loop or Monitor tool on the log. No manual polling.
- [ ] Verify `build/native/nativeCompile/spring-petclinic` and `src/pgo-profiles/main/default.iprof` exist. Record sizes and `native-image --version`.
- [ ] After the build, write `sha256sum` of the binary and `default.iprof` to `SHA256SUMS` on the big server.
- [ ] Copy all three files (binary, `default.iprof`, `SHA256SUMS`) to the small server `~/bench-runs/native/` with `scp -3` through the Mac (the servers may lack each other's key). Run `sha256sum -c SHA256SUMS` on the small server.
- [ ] Keep the Mac scratch copy of `native-image --version` for the docs.

### 4. Track 25 on the small server
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

- [ ] ASK USER before starting (≈3.5 h).
- [ ] Start the memory logger. Then run `run-track.sh 25 baseline tuning cds leyden crac`. It may start while the big-server build still runs.
- [ ] Only after the binary, `default.iprof` and `SHA256SUMS` are staged and verified, and the first invocation has finished (one benchmark at a time), run `run-track.sh 25 graalvm` as a second invocation.
- [ ] Monitor from the Mac with a background until-loop or Monitor on `progress.log`. No manual polling.
- [ ] Record the exact `java --version` output per variant (the runner writes it to each log's head).
- [ ] Record kernel and OS (`uname -a`, `/etc/os-release`), `criu --version`, and `psql --version` once.
- [ ] Report each variant's result and any failure to the user as it lands.

### 5. Track 27 on the small server
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

- [ ] ASK USER before starting (≈3 h). Start only after track 25 is done, so the small server never runs two benchmarks at once.
- [ ] `run-track.sh 27 baseline tuning cds leyden crac` (the script sets `JDK_TRACK=27`; graalvm is skipped; CSVs end `_jdk27`).
- [ ] Any JDK 27 breakage is a finding, not a bug to patch silently. Examples: Leyden `AOTMode`/`AOTCache` flag changes, CRaC flags or warp engine, class-file/ASM errors, training-run behaviour.
- [ ] On breakage: capture the exact error text and the log path, propose a fix, ASK before touching any script.

### 6. Recovery plan
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

- [ ] Small server stops answering SSH for more than 10 min (Leyden hang risk): stop, report, ask the user before any reboot. The user reboots via AWS.
- [ ] After a reboot: re-check Postgres, free disk, leftover Java processes. Do not delete `build/` in the old checkout. Ask whether to resume the interrupted variant from scratch or skip it.
- [ ] `WARMUPS`/`RUNS` are hardcoded in benchmark.sh. Changing them is a script change. Ask the user first. `SKIP_LEYDEN_AOT` is not implemented, so it is no mitigation.
- [ ] Disk below ~1 GB free: stop and report. Do not delete anything outside `~/bench-runs/` and `~/projects/petclinic-upgrade/build/` without asking.
- [ ] If a server address changes (relaunch): ask the user, then update the memory files `project_ec2_small_server.md` and `project_ec2_big_server.md`.

### 7. Collect and compare
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

- [ ] Copy back from the small server to the Mac scratchpad: all `result_*.csv` from `~/projects/petclinic-upgrade`, `~/bench-runs/jdk25/`, `~/bench-runs/jdk27/` (runner logs, `progress.log`, `runner.out`), and `~/bench-runs/mem.log`.
- [ ] Write one deterministic Python script in the scratchpad (run with `python3 -I`). It reads the 7 run rows per CSV (ignores the A row). The A row is a trimmed mean (drops min and max, averages 5 runs; benchmark.sh ~1458-1485). Per variant it reports: median startup, min-max spread, trimmed mean (must equal the A row; flag mismatches), median max memory, and delta of the median vs old in %.
- [ ] Table (a): old (May 2026, Boot 4.0.3 / JDK 25.0.3) vs new track 25, six variants.
- [ ] Table (b): track 25 vs track 27, five variants.
- [ ] Cross-check the script's trimmed mean against the A row in each CSV, not a plain mean. Flag any mismatch.
- [ ] Call out regressions and surprises. Expected small shifts come from: Boot 4.0.3 to 4.1.2, JDK 25.0.3 to 25.0.5 (CRaC 25.0.2 to 25.0.4.1, GraalVM 25.0.3 to 25.0.5), two new message bundles (Hindi, Japanese), and the new unique pet-name index.
- [ ] Treat a delta within the spread of the 7 runs as noise. Say so in the write-up.
- [ ] Hand the table data, `java --version` outputs and version facts to the docs agent as files in the scratchpad.

### 8. Record in docs
**Agent:** shell-coder
**Model:** sonnet — documentation slice from data already collected

- [ ] Create `docs/benchmark-results/` with three dated folders, one per run set: old May 2026 run, new track 25, new track 27 (names like `2026-05-old-boot-4.0.3-jdk25`, `2026-10-boot-4.1.2-jdk25`, `2026-10-boot-4.1.2-jdk27`; use real run dates).
- [ ] Inside each folder rename to `<label>.csv` (drop `result_` and `_jdk27`). Add a `logs/` subfolder with runner logs, `progress.log`, `mem.log` (new runs only). Skip large app logs unless a variant failed.
- [ ] Add to `specs/Startup-Benchmark-PRD.md` a "Tested Versions" section. Per track: exact JDK builds as `java --version` reports, GraalVM and `native-image` version, CRaC build, CRIU 4.1.1, Spring Boot 4.1.2, Gradle 9.5.1, native build tools 1.1.2, Postgres 16 on the small server, instance types (t3.small, t3.2xlarge), OS and kernel.
- [ ] In Tested Versions record build host vs run host for the native binary: `/etc/os-release`, glibc and CPU model of the big server (build) and the small server (run).
- [ ] Add to the same PRD a results section: the two comparison tables, with links to the CSV folders.
- [ ] Mark the graalvm "Startup GCs" and "Benchmark GCs" columns "not measured (known script issue)" in tables and CSV notes. Do not publish the 0/0 as real values.
- [ ] Add to `docs/specs/SPECS-overview.md` a short tested-versions table and a one-paragraph results pointer. Bump its `Updated:` line to the real date/time (Europe/Berlin).
- [ ] Use only numbers from the scratchpad data. Do not recompute or round differently. Mark failed or skipped variants explicitly (graalvm on track 27: n/a).
- [ ] State the graalvm-on-small-server method (binary built on the big server, benchmarked via direct `benchmark.sh` call) in the PRD, if the user approved it.
- [ ] Stage exact paths only (`git add [exact paths]`). Never `git add -A`, `git add .` or `git commit -a`.
- [ ] Commit with `git commit -s`. Message starts with `docs:` and ends with ` RUN-UPGRADE-BENCHMARKS`. One commit per run-set folder plus one for the spec updates is fine.
- [ ] Do not push.

### 9. Review
**Agent:** shell-reviewer
**Model:** haiku — reviews a sonnet docs slice against known data

- [ ] Check every number in the docs tables against the committed CSVs.
- [ ] Check all relative links and paths resolve (`docs/benchmark-results/...`).
- [ ] Check the versions in "Tested Versions" match the recorded `java --version` outputs and the pins in `compile-and-run.sh`.
- [ ] Check commit messages: `-s` sign-off present, `docs:` prefix, ` RUN-UPGRADE-BENCHMARKS` suffix, attribution lines present.
- [ ] Report findings only. Do not edit.

### 10. Verification and wrap-up
**Agent:** orchestrator
**Model:** n/a — live server operations need user gates and hours-long monitoring

- [ ] Do NOT re-run the test suite. Only docs/CSV/log files change. The Mac's port 5432 is held by another Docker container, and the Postgres integration test needs Docker Compose.
- [ ] `git diff --name-only merge-upstream-2026-10...HEAD` must list only `docs/` and `specs/` files.
- [ ] Mac `git status` shows only the pre-existing untracked `claude.bpf.json`, `docs/profiles/`, and this plan file if still uncommitted.
- [ ] Both servers: `~/projects/petclinic-upgrade` shows only the expected state: ` D petclinic-crac/test.txt` (tracked file deleted by `rm -rf petclinic-crac`) plus untracked `petclinic-crac/`, `petclinic.aotconf` etc. Do not require a clean status.
- [ ] Both servers: no stray Java processes. The old checkout `~/projects/spring-petclinic` is unmodified: repeat the `git status --short` + `ls -la` snapshot and compare it with the pre-flight snapshot.
- [ ] Final summary lists the graalvm GC-log bug as a finding for the user (benchmark.sh 164-165 and ~1295, `extract_gc_counts_graalvm` ~420-426; graalvm GC columns always 0/0).
- [ ] ASK the user before pushing the branch to origin. No PR unless asked. Never push to main.

## Tests

### Benchmark run checks
- [ ] Each log head shows the pinned JDK via `java --version` (verifies `sdk use` took effect in the non-interactive shell).
- [ ] Port 8080 is free before every variant (the runner checks with `ss -tln | grep -q ':8080 '` and aborts the track otherwise).
- [ ] Per variant: exit 0, fresh CSV (mtime after START), rows 1..7 plus A row, numeric startup and max memory, "Ran at" after START.
- [ ] CSV `Size App` and `Size Extra` columns are filled and plausible (graalvm: binary size and `default.iprof` size; A-row Size App > 0).
- [ ] Track 27 CSVs carry the `_jdk27` suffix. Track 25 CSVs do not. No graalvm file on track 27.
- [ ] CRaC and graalvm medians are well below 1 s (old: 0.089 s and 0.287 s). Anything near seconds means a silent fallback to a normal start. Investigate.
- [ ] GC columns numeric for JVM variants. graalvm 0/0 is expected (known script issue), not a failure.
- [ ] `mem.log` shows no sustained swap thrash outside the Leyden training window.
- [ ] The runner verifies the sha256 of the staged native binary and `default.iprof` against `~/bench-runs/native/SHA256SUMS` (written on the big server). A mismatch aborts the invocation.

### Doc checks
- [ ] Every table cell equals the script output from the scratchpad. Spot-check each variant against its CSV.
- [ ] Old-run figures match the A rows listed in Pre-flight (13.317 / 8.903 / 5.552 / 4.215 / 0.089 / 0.287 s).
- [ ] graalvm GC columns read "not measured (known script issue)". Build host vs run host is recorded.
- [ ] Folder names, CSV names and links resolve.
- [ ] `.gitignore` does not hide any committed CSV (`git ls-files docs/benchmark-results` lists them all).
- [ ] `Updated:` line in `docs/specs/SPECS-overview.md` is changed. The PRD has a Tested Versions section.
- [ ] No emojis in the docs.

### Edge Cases
- [ ] A variant fails (for example Leyden or CRaC on JDK 27). The runner continues. The docs mark it failed with the exact error. No numbers invented.
- [ ] The big-server build is not ready when the first invocation ends. Do not launch graalvm. Wait until the files are staged and verified. Do not substitute another binary.
- [ ] graalvm is launched but `~/bench-runs/native/` files are missing or the sha256 mismatches. That is an environment error: the invocation aborts with `TRACK 25 ABORTED <reason>` and writes no variant result.
- [ ] The small-server SSH session drops. The runner survives (`setsid`). Re-attach by tailing `progress.log`.
- [ ] compile-and-run.sh exits 0 without a CSV (its `continue` paths). The runner records `CSV missing`, not success.
- [ ] A result CSV from a prior run sits in the checkout. The mtime-after-START check rejects it. Move stale `result_*.csv` into `~/bench-runs/` before track 25 starts, only inside `petclinic-upgrade`.
- [ ] Mac-side `pgrep -f` self-match. Use `ps -eo args | grep "[p]attern"` or `jps` instead.
- [ ] Server IP changed after relaunch. Ask the user, then update the memory files.

# Code Review - run-upgrade-benchmarks-jdk25-jdk27

**Date**: 2026-11-01
**Branch**: run-upgrade-benchmarks-jdk25-jdk27
**Base**: merge-upstream-2026-10
**Files Reviewed**: 65 (code: `benchmark.sh`, `build.gradle`, `PetClinicRuntimeHints.java`, `PetClinicRuntimeHintsTests.java`; rest: docs, result CSVs, logs)
**Review Rounds**: 3

## Summary

The branch fixes four defects the verification run found (GraalVM build broken by CycloneDX 3.2.4, CRaC checkpoint race, missing native reflection hints for Thymeleaf helpers, benchmark accepting HTTP 500 pages) and records the verification-run results. Round 1 found 4 warnings and 8 suggestions. Round 2 checked those fixes and found 2 warnings and 4 suggestions. Round 3 was clean. No critical issue in any round. Nothing changes timing, CSV output or process handling for a passing benchmark run.

## Review Rounds

### Round 1

**Issues found**: 12 | **Fixes applied**: 8

| # | Severity | File | Issue | Found by | Fix | Fixed by |
|---|----------|------|-------|----------|-----|----------|
| 1 | WARNING | `src/main/java/org/springframework/samples/petclinic/PetClinicRuntimeHints.java:39` | `#fields` helper (`org.thymeleaf.spring6.expression.Fields`) not registered for native reflection | be-reviewer (sonnet) | Registered `Fields` with `INVOKE_PUBLIC_METHODS` and added two tests (f99d6a3) | be-coder (sonnet) |
| 2 | SUGGESTION | `src/main/java/org/springframework/samples/petclinic/PetClinicRuntimeHints.java:39` | Comment claims GraalVM 25.0.5 / Boot 4.1.2 "no longer" register the helpers | be-reviewer (sonnet) | Comment states the verified OGNL-only metadata condition (f99d6a3) | be-coder (sonnet) |
| 3 | SUGGESTION | `build.gradle:73` | Workaround comment misstates the CycloneDX mechanism | be-reviewer (sonnet) | Comment describes the decompiled `afterEvaluate` hook (f99d6a3) | be-coder (sonnet) |
| 4 | SUGGESTION | `build.gradle:78` | Try CycloneDX plugin 3.5.1 to drop the workaround | be-reviewer (sonnet) | — | — |
| 5 | SUGGESTION | `src/test/java/org/springframework/samples/petclinic/PetClinicRuntimeHintsTests.java:44` | Tests narrow; no template scan | be-reviewer (sonnet) | — | — |
| 6 | WARNING | `benchmark.sh:317` | `000` abort and readiness-timeout exit leave the app running | shell-reviewer (sonnet) | New `stop_app_after_failure` called from all three `hit_urls` failure paths (7a8ad70) | shell-coder (sonnet) |
| 7 | WARNING | `benchmark.sh:1010` | Stale `core.img.*` temp file blocks every direct CRaC rerun | shell-reviewer (sonnet) | CRaC training removes an old `petclinic-crac/` first (7a8ad70) | shell-coder (sonnet) |
| 8 | SUGGESTION | `benchmark.sh:200` | Smoke-test CSV indistinguishable from an official CSV | shell-reviewer (sonnet) | — | — |
| 9 | SUGGESTION | `benchmark.sh:379` | Guard cache-cleanup message wrong outside training | shell-reviewer (sonnet) | Neutral, conditional messages (7a8ad70) | shell-coder (sonnet) |
| 10 | SUGGESTION | `benchmark.sh:337` | Skipped non-descendant `app_pid` orphans the app until `wait_for_port_free` | shell-reviewer (sonnet) | — | — |
| 11 | WARNING | `specs/Startup-Benchmark-PRD.md:721` | PRD says 1-second pauses / ~55 s; code sleeps 3 s (~165 s) | shell-reviewer (sonnet) | Corrected lines 278, 280, 721 and the 120 s checkpoint wait (1e9631a) | shell-coder (haiku) |
| 12 | SUGGESTION | `specs/Startup-Benchmark-PRD.md:204` | CRaC and guard sentences incomplete; checkpoint size stale | shell-reviewer (sonnet) | Full completion rule, guard scope, 230-400 MB (1e9631a) | shell-coder (haiku) |

### Round 2

**Issues found**: 6 | **Fixes applied**: 5

| # | Severity | File | Issue | Found by | Fix | Fixed by |
|---|----------|------|-------|----------|-----|----------|
| 1 | WARNING | `src/main/java/org/springframework/samples/petclinic/PetClinicRuntimeHints.java:39` | New comment overstates the gap for `#fields` (metadata does register `Fields` for SpEL, tested on 3.1.0.M2 only) | be-reviewer (sonnet) | Comment split: core helpers OGNL-only; `Fields` registered as a safeguard (9e7695f) | be-coder (sonnet) |
| 2 | SUGGESTION | `src/test/java/org/springframework/samples/petclinic/PetClinicRuntimeHintsTests.java:64` | No test for `#fields.hasAnyErrors()` | be-reviewer (sonnet) | Added `thymeleafFieldsHasAnyErrorsIsInvocable` (9e7695f) | be-coder (sonnet) |
| 3 | WARNING | `benchmark.sh:304` | `petclinic.jsa` also removed after warm-up/measured-run failures; docs describe only training | shell-reviewer (sonnet) | Behaviour kept (retrain is cheap; compile-and-run.sh deletes it anyway); comment and PRD now say so (91df2ba) | shell-coder (sonnet) |
| 4 | SUGGESTION | `specs/Startup-Benchmark-PRD.md:705` | "non-log files" check outdated; early process exit missing | shell-reviewer (sonnet) | PRD describes the `core.img` check and early exit (91df2ba) | shell-coder (sonnet) |
| 5 | SUGGESTION | `benchmark.sh:892` | `rm -rf petclinic-crac` result unchecked | shell-reviewer (sonnet) | Fails fast with an error (91df2ba) | shell-coder (sonnet) |
| 6 | SUGGESTION | `benchmark.sh:261` | `wait_for_port_free` fallback can TERM/KILL a PID outside the descendant check after 30 s | shell-reviewer (sonnet) | — | — |

Round 2 fix plan was written by the orchestrator (fully spelled-out edits) instead of by the fixers; the Step 5.3 plan review was folded into round 3.

### Round 3

Clean pass. No issues found.

## Remaining Issues

- `build.gradle:78` (SUGGESTION, round 1) — try CycloneDX Gradle plugin 3.3.0-3.5.1; if one fixes the "Cannot mutate the artifacts" error on `nativeCompile`, drop the `tasks.named("cyclonedxDirectBom").get()` workaround. Needs a native build to verify. Not attempted (out of scope).
- `src/test/java/org/springframework/samples/petclinic/PetClinicRuntimeHintsTests.java:44` (SUGGESTION, round 1) — a test that scans `templates/**` for `#xxx.` helpers and asserts each is registered would catch the next missing hint. Not attempted (new test idea, not a fix).
- `benchmark.sh:200` (SUGGESTION, round 1) — a smoke-test CSV (`BENCH_RUNS` other than 7) carries no marker and overwrites the official `result_<label>.csv`. Not attempted (CSV format change).
- `benchmark.sh:337` (SUGGESTION, round 1) — when `app_pid` is skipped as a non-descendant, killing the `/usr/bin/time` launcher orphans the app until `wait_for_port_free` clears it. Rare path, already fail-safe. Not attempted.
- `benchmark.sh:261` (SUGGESTION, round 2) — pre-existing: `wait_for_port_free`'s `jcmd`/`pgrep`/`ss` fallback can stop a process it picks itself after 30 s. Now reachable from more failure paths. Not attempted.
- Found during fix planning, pre-existing, not changed: `benchmark.sh:133, 237, 866` — `[[ ! -f petclinic-crac/*.img ]]` never globs, so the CRaC branch always retrains and never reuses a checkpoint. Harmless under `compile-and-run.sh`, which deletes the directory anyway.
- Found during plan review, pre-existing, not changed: the readiness fast-fail in `hit_urls` checks `${app_pid:-${pid:-}}`; in the measured-run loop `pid` can be a stale warm-up PID if `app_pid` were ever empty.

## Project Context Validation

- No PRD file matches `PRD*.md`; project context came from `CLAUDE.md` and `specs/Startup-Benchmark-PRD.md`.
- Spring Java Format: `checkFormat` passes for the changed Java files.
- Commits: every commit on the branch carries `Signed-off-by`.
- Gradle is the maintained build; changes target Gradle only.
- Benchmark methodology: default warm-ups/runs (3/7), URL list, pacing (`sleep 3`), timing and CSV output are unchanged for passing runs. The new behaviour only affects failure paths and the opt-in `BENCH_WARMUPS`/`BENCH_RUNS` override.
- Tests: 84 tests passed on JDK 25.0.5 and JDK 27 on the big server at 9fe08b8 (before the round 1-2 fixes). The changed test class (`PetClinicRuntimeHintsTests`, 6 tests) passes at 9e7695f.

## Next Steps

- Review remaining issues (if any)
- Ensure all tests pass
- Update documentation if needed
- Create PR when ready

---
Generated with Claude Code - bpf-review v1.10.0

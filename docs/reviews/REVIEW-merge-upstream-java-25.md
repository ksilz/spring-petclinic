# Code Review - merge-upstream-java-25

**Date**: 2026-05-01
**Branch**: merge-upstream-java-25
**Base**: main
**Files Reviewed**: 52
**Review Rounds**: 1

## Summary

Merged 28 upstream commits into the benchmark fork. Key changes: Spring Boot 4.0.0-RC1 → 4.0.3, Gradle 9.1.0 → 9.2.1, GraalVM buildtools 0.11.2 → 0.11.5. Removed errorprone/nullaway. Updated all starter names to Spring Boot 4.x conventions. Java 25 toolchain preserved. SDK version strings updated to `25.0.3-tem` and `25.0.3-graal`.

## Review Rounds

### Round 1

**Issues found**: 2 | **Fixes applied**: 1

| # | Severity | File | Issue | Found by | Fix | Fixed by |
|---|----------|------|-------|----------|-----|----------|
| 1 | WARNING | `build.gradle:100` | File missing trailing newline (merge artifact) | built-in review | Added trailing newline | direct fix |
| 2 | SUGGESTION | `PetClinicRuntimeHints.java:29` | Jackson 3 `try/catch` block kept from fork; upstream removed it. Likely safe in Spring Boot 4.x where Jackson 3 hints are auto-registered | built-in review | — | — |

## Remaining Issues

- `PetClinicRuntimeHints.java:29` — Jackson 3 reflection hints try/catch block. Harmless but may be redundant in Spring Boot 4.x. Low priority.

## Project Context Validation

- **Java 25 toolchain**: Preserved in `build.gradle` ✓
- **`.sdkmanrc`**: Updated from `25-librca` → `25.0.3-tem` ✓
- **`compile-and-run.sh`**: Updated from `25.0.1-tem` → `25.0.3-tem` and `25.0.1-graal` → `25.0.3-graal` ✓
- **Benchmark scripts**: `benchmark.sh` and `compile-and-run.sh` unchanged ✓
- **CRaC support**: `org.crac:crac:1.5.0` dependency preserved ✓
- **Security fix**: `OwnerController.setDisallowedFields` updated to also disallow `"*.id"` ✓
- **GitHub Actions**: CI workflows kept at Java 25 (not upstream's Java 17) ✓
- **Tests**: 59/59 pass ✓

## Next Steps

- Consider removing Jackson 3 try/catch from `PetClinicRuntimeHints.java` (low priority)
- Run benchmarks on EC2 servers to verify performance after upgrade
- Merge to main when ready

---
Generated with Claude Code - bpf-review v1.4.0

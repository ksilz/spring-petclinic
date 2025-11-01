# Heap Tuning Progress

## Goal
Find optimal JVM heap settings where:
- ✅ NO garbage collection during startup
- ✅ SOME garbage collection during benchmark runs

## Current Status
**Iteration:** 10 / 10
**Current Heap:** -Xms1152m -Xmx1152m
**Status:** ❌ Failed

Could not find optimal heap settings within constraints.\n\nReview heap-tuning-results.log for details.\n\n**Tested heap sizes:** 512 576 640 704 768 832 896 960 1024 1088

## Configuration
- **Variant:** baseline
- **Adjustment increment:** 64 MB
- **Starting heap:** 512 MB
- **Min heap:** 256 MB
- **Max heap:** 4096 MB
- **Max iterations:** 10

## Iteration Log

### Recent Iterations
```
[2025-11-01 11:13:51] GC occurred during startup. Increasing heap by 64m
[2025-11-01 11:13:51] =========================================
[2025-11-01 11:13:51] Iteration 9 / 10
[2025-11-01 11:13:51] Testing heap: 1024m
[2025-11-01 11:13:51] =========================================
[2025-11-01 11:13:51] Running benchmark with heap: -Xms1024m -Xmx1024m
[2025-11-01 11:18:06] GC occurred during startup. Increasing heap by 64m
[2025-11-01 11:18:06] =========================================
[2025-11-01 11:18:06] Iteration 10 / 10
[2025-11-01 11:18:06] Testing heap: 1088m
[2025-11-01 11:18:06] =========================================
[2025-11-01 11:18:06] Running benchmark with heap: -Xms1088m -Xmx1088m
[2025-11-01 11:22:20] ERROR: GC during both phases or verification error
[2025-11-01 11:22:20] Trying larger heap: 1152m
[2025-11-01 11:22:20] =========================================
[2025-11-01 11:22:20] Heap Tuning Complete
[2025-11-01 11:22:20] =========================================
[2025-11-01 11:22:20] ERROR: ❌ Failed to find optimal heap settings
[2025-11-01 11:22:20] ERROR: Iterations exhausted or limits reached
[2025-11-01 11:22:20] ERROR: Review heap-tuning-results.log for details
```

---
*Last updated: 2025-11-01 11:22:20*

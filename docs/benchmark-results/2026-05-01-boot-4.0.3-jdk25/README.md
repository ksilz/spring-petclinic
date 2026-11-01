# May 2026 benchmark results (Spring Boot 4.0.3, JDK 25.0.3)

This is a full benchmark run: 3 warm-ups and 7 measured runs per variant. The row `A` in each CSV is the trimmed mean (min and max dropped).

## Source

- Host: the small server (AWS t3.small, 2 vCPU, 1.9 GB RAM, 2 GB swap).
- Checkout: the old checkout `~/projects/spring-petclinic` at commit `f8b1e65`. This is the tag `pre-upgrade-boot-4.0.3`.
- Dates: baseline, tuning, cds and leyden ran on 2026-05-01. crac and graalvm ran on 2026-05-02.
- The files were never committed before. The original `result_<label>.csv` files are git-ignored and the tag holds none. They are copied here as `<label>.csv`.

## Versions

Spring Boot 4.0.3, Gradle 9.2.1, GraalVM native build tools 0.11.5, CycloneDX Gradle plugin 3.2.0, JDK 25.0.3-tem, CRaC 25.0.2.crac-zulu, GraalVM 25.0.3-graal.

## Caveat: Size App (MB)

The `Size App (MB)` value of 164.6 for tuning, cds and leyden is inflated. The old checkout's extracted folder holds 225 library JARs (three Spring Boot 4 versions), because `java -Djarmode=tools extract --force` never deletes stale files. A fresh checkout has 93 JARs and 63.8 MB. Startup times are not affected: the app JAR's manifest lists exactly the libraries it loads.

## Files

`baseline.csv`, `tuning.csv`, `cds.csv`, `leyden.csv`, `crac.csv`, `graalvm.csv`.

For a comparison with the 2026-10-31 verification run, see `../2026-10-31-verification-boot-4.1.2/README.md`.

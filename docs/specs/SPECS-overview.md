# Overview Specification

Updated: 2026-11-01 08:59 Europe/Berlin

Spring PetClinic benchmark fork — measures startup speed of five Spring Boot optimization techniques for a Java conference talk.

## Tech Stack

| Technology | Version | Purpose |
|---|---|---|
| Spring Boot | 4.1.2 | Application framework |
| Java | 25 LTS (Temurin 25.0.5) and 27 (Temurin 27) | Runtime (regular variants), selected with `JDK_TRACK=25\|27` |
| GraalVM | 25.0.5.0+3-graal | Runtime (native image variant, JDK track 25 only) |
| Gradle | 9.5.1 | Build system (primary) |
| Maven | 3.9.x | Build system (secondary) |
| Spring Data JPA | via Boot 4 | Data persistence |
| Hibernate | via Boot 4 | ORM with snake_case naming |
| Thymeleaf | via Boot 4 | Server-side templates |
| PostgreSQL | 18.4 (Docker image in `docker-compose.yml`) | Production database (Docker or native) |
| H2 | via Boot 4 | Default in-memory database for tests |
| CRaC | Zulu CRaC 25.0.4.1 / 27 | Checkpoint/Restore variant |

## Benchmark Variants

| Label | Description | Java (track 25) | Java (track 27) |
|---|---|---|---|
| baseline | Standard Spring Boot, AOT disabled | 25.0.5.0+8-tem | 27.0.0.0+35-tem |
| tuning | Spring Boot with AOT enabled | 25.0.5.0+8-tem | 27.0.0.0+35-tem |
| cds | Class Data Sharing + AOT | 25.0.5.0+8-tem | 27.0.0.0+35-tem |
| leyden | OpenJDK Project Leyden AOT cache | 25.0.5.0+8-tem | 27.0.0.0+35-tem |
| crac | OpenJDK Project CRaC checkpoint/restore | 25.0.4.1-crac+1-zulu | 27.0.0.0-crac+35-zulu |
| graalvm | GraalVM Native Image with PGO | 25.0.5.0+3-graal | n/a (no GraalVM release for JDK 27) |

`JDK_TRACK=25` (default) or `JDK_TRACK=27 ./compile-and-run.sh` selects the track. Track 27 result CSVs get a `_jdk27` suffix
(`result_baseline_jdk27.csv`); track 25 keeps the historic names. SDKMAN identifiers with `+` need SDKMAN 5.24 or newer
(`sdk selfupdate`).

## Tested Versions

| Item | Track 25 | Track 27 |
|---|---|---|
| baseline, tuning, cds, leyden JDK | Temurin 25.0.5+8 (`25.0.5.0+8-tem`) | Temurin 27+35 (`27.0.0.0+35-tem`) |
| crac JDK | Zulu CRaC 25.0.4.1 (`25.0.4.1-crac+1-zulu`) | Zulu CRaC 27 (`27.0.0.0-crac+35-zulu`) |
| graalvm | Oracle GraalVM 25.0.5.0.3+1.1 (`25.0.5.0+3-graal`) | n/a (no GraalVM release for JDK 27) |
| Spring Boot | 4.1.2 | 4.1.2 |
| Gradle | 9.5.1 | 9.5.1 |
| GraalVM native build tools | 1.1.2 | 1.1.2 |
| CycloneDX Gradle plugin | 3.5.1 | 3.5.1 |

Hosts and OS details are in `specs/Startup-Benchmark-PRD.md` (section "Tested Versions").

## Architecture

MVC web application (vet clinic management). Standard Spring Boot layering: controllers → services (implicit) → repositories → JPA entities.

## Important Files

| Path | Purpose |
|---|---|
| `compile-and-run.sh` | Main benchmark orchestrator |
| `benchmark.sh` | Per-variant measurement script |
| `build.gradle` | Build config with CRaC conditional |
| `.sdkmanrc` | Default SDK: `java=25.0.5.0+8-tem` |
| `specs/Startup-Benchmark-PRD.md` | Detailed benchmark methodology |
| `CLAUDE.md` | Full project guidance |

## Quick Reference

| Action | Command |
|---|---|
| Build | `./gradlew build -x checkstyleNohttp` (`checkstyleNohttp` fails with the configuration cache) |
| Test | `./gradlew test -x checkstyleNohttp` |
| Run (H2) | `./gradlew bootRun` |
| Run (postgres) | `SPRING_PROFILES_ACTIVE=postgres ./gradlew bootRun` |
| Run benchmarks | `./compile-and-run.sh` (track 25) or `JDK_TRACK=27 ./compile-and-run.sh` (track 27). Defaults: 3 warm-ups, 7 runs. Smoke test: `BENCH_WARMUPS=1 BENCH_RUNS=3 ./compile-and-run.sh`, writes `result_<label>[_jdk27]_smoke.csv`. Official results use the defaults. |
| Format code | `./gradlew formatMain formatTest` |

## Benchmark Results

Archived results are in `docs/benchmark-results/`. The verification run of 2026-10-31 (1 warm-up + 3 runs, Spring Boot 4.1.2, JDK 25 and 27) is described in `docs/benchmark-results/2026-10-31-verification-boot-4.1.2/README.md`. It is not the official benchmark.
Duplicate indexes in the `petclinic` database added about 0.3 s to the native and about 0.4 s to the JVM startup on the small server. They were removed on 2026-11-01 (PRD findings 5 and 10). Check for them again before an official run.
The full May 2026 run (3 warm-ups + 7 runs, Spring Boot 4.0.3, JDK 25.0.3) is in `docs/benchmark-results/2026-05-01-boot-4.0.3-jdk25/`.

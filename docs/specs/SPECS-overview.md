# Overview Specification

Updated: 2026-05-01 15:29 Europe/Berlin

Spring PetClinic benchmark fork — measures startup speed of five Spring Boot optimization techniques for a Java conference talk.

## Tech Stack

| Technology | Version | Purpose |
|---|---|---|
| Spring Boot | 4.0.3 | Application framework |
| Java | 25 (Temurin) | Runtime (regular variants) |
| GraalVM | 25.0.3-graal | Runtime (native image variant) |
| Gradle | 9.2.1 | Build system (primary) |
| Maven | 3.9.x | Build system (secondary) |
| Spring Data JPA | via Boot 4 | Data persistence |
| Hibernate | via Boot 4 | ORM with snake_case naming |
| Thymeleaf | via Boot 4 | Server-side templates |
| PostgreSQL | 18.3 | Production database (Docker or native) |
| H2 | via Boot 4 | Default in-memory database for tests |
| CRaC | Zulu 25.crac | Checkpoint/Restore variant |

## Benchmark Variants

| Label | Description | Java |
|---|---|---|
| baseline | Standard Spring Boot, AOT disabled | 25.0.3-tem |
| tuning | Spring Boot with AOT enabled | 25.0.3-tem |
| cds | Class Data Sharing + AOT | 25.0.3-tem |
| leyden | OpenJDK Project Leyden AOT cache | 25.0.3-tem |
| crac | OpenJDK Project CRaC checkpoint/restore | 25.crac-zulu |
| graalvm | GraalVM Native Image with PGO | 25.0.3-graal |

## Architecture

MVC web application (vet clinic management). Standard Spring Boot layering: controllers → services (implicit) → repositories → JPA entities.

## Important Files

| Path | Purpose |
|---|---|
| `compile-and-run.sh` | Main benchmark orchestrator |
| `benchmark.sh` | Per-variant measurement script |
| `build.gradle` | Build config with CRaC conditional |
| `.sdkmanrc` | Default SDK: `java=25.0.3-tem` |
| `specs/Startup-Benchmark-PRD.md` | Detailed benchmark methodology |
| `CLAUDE.md` | Full project guidance |

## Quick Reference

| Action | Command |
|---|---|
| Build | `./gradlew build` |
| Test | `./gradlew test` |
| Run (H2) | `./gradlew bootRun` |
| Run (postgres) | `SPRING_PROFILES_ACTIVE=postgres ./gradlew bootRun` |
| Run benchmarks | `./compile-and-run.sh` |
| Format code | `./gradlew spring-javaformat:apply` |

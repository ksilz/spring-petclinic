# PRD: Merge Upstream Spring PetClinic + Java 25 Upgrade

## Source

Fork: ksilz/spring-petclinic (benchmark-focused fork)
Upstream: spring-projects/spring-petclinic

## Problem Statement

This fork (used for a Java startup speed talk) is behind the upstream by ~28 commits. The upstream has upgraded to Spring Boot 4.0.3, Gradle 9.2.1, and various dependency updates. Meanwhile, the fork still runs Spring Boot 4.0.0-RC1. We also need to update the Java 25 SDK versions from `25.0.1` to `25.0.3` across all scripts and config.

## Requirements

### Upstream Changes to Adopt

| Change | Details |
|--------|---------|
| Spring Boot | 4.0.0-RC1 → 4.0.3 |
| Gradle wrapper | 9.1.0 → 9.2.1 |
| GraalVM buildtools plugin | 0.11.2 → 0.11.5 |
| CycloneDX plugin | 3.0.0 → 3.2.0 |
| Checkstyle version | 11.1.0 → 12.3.1 |
| webjarsLocatorLite | existing → 1.1.3 |
| Starter `spring-boot-starter-web` | renamed to `spring-boot-starter-webmvc` |
| New test starters | `spring-boot-starter-data-jpa-test`, `spring-boot-starter-restclient-test`, `spring-boot-starter-webmvc-test` |
| `runtimeOnly 'spring-boot-starter-actuator'` | added |
| Snake case naming strategy | `spring.jpa.hibernate.naming.physical-strategy` added |
| Hibernate fetch size | `spring.jpa.properties.hibernate.default_batch_fetch_size=16` added |
| Source code changes | Entity simplifications, package-info updates, OwnerController, PetController, etc. |
| HSQLDB removal | Remove `src/main/resources/db/hsqldb/` |
| MySQL user.sql fix | MySQL 8.0+ compatibility |
| Docker images | Updated MySQL 9.2→9.6, PostgreSQL 18.0→18.3 |
| `errorprone` / `nullaway` | Remove from build.gradle (upstream dropped them) |
| `.mvn/jvm.config` | Remove (contained `--add-exports` for errorprone, no longer needed) |
| Binder allowed fields | OwnerController/PetController security fix (`setDisallowedFields`) |
| Maven wrapper | Update |
| `.gitignore` | Upstream cleaned up; merge carefully (keep fork-specific entries) |

### Changes to Override (Keep Fork Versions)

| Item | Reason | Update Needed? |
|------|--------|---------------|
| Java toolchain in `build.gradle` | Keep Java 25 (upstream reverted to 17) | No |
| `.sdkmanrc` | Update version string | Yes: `java=25-librca` → `java=25.0.3-tem` |
| `.github/workflows/gradle-build.yml` | Our fork uses Java 25; upstream uses 17 | No (keep Java 25 matrix) |
| `.github/workflows/maven-build.yml` | Our fork uses Java 25; upstream uses 17 | No (keep Java 25 matrix) |
| `benchmark.sh` | Fork-specific; no SDK version refs needing updates | No |
| `compile-and-run.sh` | Fork-specific; update Java version strings | Yes: `25.0.1-tem`→`25.0.3-tem`, `25.0.1-graal`→`25.0.3-graal` |
| `gradle.properties` | Keep our config/build cache/parallel flags; upstream has no gradle.properties | No |
| `CLAUDE.md` | Fork-specific docs | No |
| `specs/Startup-Benchmark-PRD.md` | Fork-specific | No |
| `HEAP-TUNING-GUIDE.md`, `TODOS.md` | Fork-specific | No |
| Native image reachability metadata | Fork-specific; upstream has none | No |
| `petclinic-crac/` | Fork-specific | No |
| CRaC dependency in `build.gradle` | Fork-specific (`org.crac:crac:1.5.0`) | No |

### Java 25 Version Updates

Update SDK version from `25.0.1` → `25.0.3` everywhere:

| File | Change |
|------|--------|
| `.sdkmanrc` | `java=25-librca` → `java=25.0.3-tem` |
| `compile-and-run.sh` | `JAVA[baseline/tuning/cds/leyden]='25.0.1-tem'` → `25.0.3-tem` |
| `compile-and-run.sh` | `JAVA[graalvm]='25.0.1-graal'` → `25.0.3-graal` |

Note: `JAVA[crac]='25.crac-zulu'` stays unchanged (Zulu CRaC doesn't follow same versioning).

## Special Instructions

- Do NOT change `build.gradle` Java toolchain from `JavaLanguageVersion.of(25)` even though upstream uses 17.
- Preserve all fork-specific scripts and documentation.
- After the merge, run `./gradlew test` to verify everything compiles and tests pass.
- The merge strategy: use `git merge upstream/main` and resolve conflicts manually, preferring upstream for shared source files and preferring fork for fork-specific files.

## Implementation Approach

1. Fetch upstream changes (`git fetch upstream` — already done).
2. Run `git merge upstream/main` — expect conflicts.
3. Resolve conflicts file by file:
   - Source code files: take upstream changes unless they conflict with CRaC additions.
   - `build.gradle`: merge carefully — take upstream dependency updates, keep Java 25 toolchain and CRaC support, remove errorprone/nullaway.
   - `application.properties`: take upstream (snake case naming, fetch size).
   - `.gitignore`: take upstream additions AND keep our fork-specific additions.
   - `.github/workflows/`: keep our versions (Java 25 matrix, not upstream's Java 17).
   - `docker-compose.yml`: take upstream (updated image versions).
   - `pom.xml`: take upstream.
   - Fork-specific files (`benchmark.sh`, `compile-and-run.sh`, `gradle.properties`, docs, specs): keep ours.
   - `.mvn/jvm.config`: delete (no longer needed without errorprone).
4. Update `.sdkmanrc` to `java=25.0.3-tem`.
5. Update `compile-and-run.sh` version strings.
6. Run `./gradlew test` to verify.

## Test Strategy

- Run `./gradlew test` after merge.
- Verify the application compiles with Java 25.
- Verify no import errors from renamed starters.

## Non-Functional Requirements

- All benchmark scripts must still function after the merge.
- GraalVM configuration must reference `25.0.3-graal`.
- Regular Java must reference `25.0.3-tem`.

## Success Criteria

- `git merge upstream/main` completes with all conflicts resolved.
- `./gradlew test` passes.
- `.sdkmanrc` contains `java=25.0.3-tem`.
- `compile-and-run.sh` references `25.0.3-tem` and `25.0.3-graal`.
- Application starts with Spring Boot 4.0.3 and Java 25.

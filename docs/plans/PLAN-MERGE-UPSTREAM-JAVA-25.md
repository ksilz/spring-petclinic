# Implementation Plan: MERGE-UPSTREAM-JAVA-25

## Test Command
`./gradlew test`

## Tasks

### 1. Initiate Upstream Merge

- [ ] Run `git merge upstream/main --no-commit --no-ff` to stage changes without auto-committing
- [ ] List all conflicts with `git status`

### 2. Resolve Build File Conflicts

- [ ] **`build.gradle`**: Manually merge
  - Take from upstream: Spring Boot `4.0.3`, GraalVM buildtools `0.11.5`, CycloneDX `3.2.0`, checkstyle `12.3.1`, webjarsLocatorLite `1.1.3`
  - Take from upstream: rename `spring-boot-starter-web` → `spring-boot-starter-webmvc`
  - Take from upstream: add `runtimeOnly 'spring-boot-starter-actuator'`
  - Take from upstream: new test starters (`spring-boot-starter-data-jpa-test`, `spring-boot-starter-restclient-test`, `spring-boot-starter-webmvc-test`)
  - Take from upstream: remove `net.ltgt.errorprone` plugin, remove `nullaway` and `errorprone` dependencies
  - Keep ours: Java toolchain `languageVersion = JavaLanguageVersion.of(25)`
  - Keep ours: CRaC dependency block (`if (cracEnabled)`)
  - Keep ours: `gradle.startParameter.excludedTaskNames` line
- [ ] **`gradle/wrapper/gradle-wrapper.properties`**: Take upstream (Gradle `9.2.1`)
- [ ] **`pom.xml`**: Take upstream version

### 3. Resolve Config File Conflicts

- [ ] **`application.properties`**: Take upstream (adds snake_case naming strategy, Hibernate fetch size)
- [ ] **`.gitignore`**: Merge — take upstream changes AND keep our fork-specific entries (`spring-petclinic*`, `petclinic.aot`, `petclinic.jsa`, `result_*.csv`, `default.iprof`, `/.claude/settings.local.json`, `/CLAUDE.local.md`, `/*.log`)
- [ ] **`docker-compose.yml`**: Take upstream (MySQL `9.6`, PostgreSQL `18.3`)
- [ ] **`k8s/db.yml`**: Take upstream changes
- [ ] **`.mvn/wrapper/maven-wrapper.properties`**: Take upstream
- [ ] **`.mvn/jvm.config`**: Delete this file (was only needed for errorprone)
- [ ] **`.github/workflows/gradle-build.yml`**: Keep our version (Java 25 matrix)
- [ ] **`.github/workflows/maven-build.yml`**: Keep our version (Java 25 matrix)

### 4. Resolve Source Code Conflicts

All source file changes come from upstream (removing `@Nullable`/`@NullMarked`/jspecify, `@Column(name=...)` → `@Column`):

- [ ] `PetClinicRuntimeHints.java`: Take upstream (remove Jackson 3 reflection hints, remove `@Nullable` on classLoader)
- [ ] `model/BaseEntity.java`: Take upstream (remove `@Nullable`, remove jspecify import)
- [ ] `model/NamedEntity.java`: Take upstream (remove `@Nullable`, `@Column(name=...)` → `@Column`)
- [ ] `model/Person.java`: Take upstream (remove `@Nullable`, `@Column(name=...)` → `@Column`)
- [ ] `model/package-info.java`: Take upstream (remove `@NullMarked`)
- [ ] `owner/Owner.java`: Take upstream (remove `@Nullable`, `@Column(name=...)` → `@Column`)
- [ ] `owner/OwnerController.java`: Take upstream (binder security fix: `setDisallowedFields("id", "*.id")`, remove jspecify)
- [ ] `owner/OwnerRepository.java`: Take upstream
- [ ] `owner/Pet.java`: Take upstream (remove `@Nullable`, etc.)
- [ ] `owner/PetController.java`: Take upstream
- [ ] `owner/PetTypeFormatter.java`: Take upstream
- [ ] `owner/Visit.java`: Take upstream
- [ ] `owner/VisitController.java`: Take upstream
- [ ] `owner/package-info.java`: Take upstream
- [ ] `package-info.java`: Take upstream
- [ ] `system/package-info.java`: Take upstream
- [ ] `vet/Vet.java`: Take upstream
- [ ] `vet/Vets.java`: Take upstream
- [ ] `vet/package-info.java`: Take upstream

### 5. Resolve Test Code Conflicts

- [ ] `MySqlIntegrationTests.java`: Take upstream
- [ ] `MysqlTestApplication.java`: Take upstream (if changed)
- [ ] `PetClinicIntegrationTests.java`: Take upstream
- [ ] `PostgresIntegrationTests.java`: Take upstream
- [ ] `owner/OwnerControllerTests.java`: Take upstream (improved test naming conventions)
- [ ] `owner/PetControllerTests.java`: Take upstream
- [ ] `owner/PetValidatorTests.java`: Take upstream
- [ ] `owner/VisitControllerTests.java`: Take upstream
- [ ] `service/ClinicServiceTests.java`: Take upstream
- [ ] `system/CrashControllerIntegrationTests.java`: Take upstream
- [ ] `system/CrashControllerTests.java`: Take upstream
- [ ] `system/I18nPropertiesSyncTest.java`: Take upstream
- [ ] `vet/VetControllerTests.java`: Take upstream
- [ ] `vet/VetTests.java`: Take upstream

### 6. Handle Deleted/Added Files

- [ ] **Delete** `src/main/resources/db/hsqldb/data.sql` (accept upstream deletion)
- [ ] **Delete** `src/main/resources/db/hsqldb/schema.sql` (accept upstream deletion)
- [ ] Update `src/main/resources/db/mysql/user.sql` (take upstream MySQL 8.0+ fix)
- [ ] Verify `src/main/resources/application-mysql.properties` and `application-postgres.properties` are intact

### 7. Fork-Specific Files (Keep Ours — No Merge Needed)

- [ ] Verify `benchmark.sh` is unmodified
- [ ] Verify `compile-and-run.sh` is unmodified (will update version strings in task 9)
- [ ] Verify `gradle.properties` is unmodified (our config cache/parallel flags)
- [ ] Verify `CLAUDE.md` is unmodified
- [ ] Verify `specs/Startup-Benchmark-PRD.md` is unmodified
- [ ] Verify `petclinic-crac/` is unmodified
- [ ] Verify native image reachability metadata is unmodified (if present)

### 8. Commit the Merge

- [ ] Stage all resolved files: `git add -A`
- [ ] Commit: `git commit -m "feat: Merge upstream Spring Boot 4.0.3 + Gradle 9.2.1 changes. MERGE-UPSTREAM-JAVA-25"`

### 9. Update Java 25 Version Strings

- [ ] Update `.sdkmanrc`: `java=25-librca` → `java=25.0.3-tem`
- [ ] Update `compile-and-run.sh`: all `25.0.1-tem` → `25.0.3-tem` (4 occurrences: baseline, tuning, cds, leyden)
- [ ] Update `compile-and-run.sh`: `25.0.1-graal` → `25.0.3-graal` (1 occurrence: graalvm)
- [ ] Commit: `feat: Update Java 25 SDK versions to 25.0.3. MERGE-UPSTREAM-JAVA-25`

### 10. Verification

- [ ] Run `./gradlew test` — all tests must pass
- [ ] Verify `./gradlew build` compiles successfully with Java 25
- [ ] Check that `spring-boot-starter-webmvc` resolves correctly
- [ ] Check that HSQLDB references are fully removed

## Tests

### Verification Checks
- [ ] `./gradlew test` passes with zero failures
- [ ] `./gradlew build` succeeds (compiles + tests)
- [ ] `.sdkmanrc` contains `java=25.0.3-tem`
- [ ] `compile-and-run.sh` contains `25.0.3-tem` and `25.0.3-graal`
- [ ] `build.gradle` contains Spring Boot `4.0.3` and Java 25 toolchain
- [ ] No jspecify imports remain in source files
- [ ] No `hsqldb` directory in `src/main/resources/db/`

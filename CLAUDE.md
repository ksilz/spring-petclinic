# CLAUDE.md

Updated: 2026-11-01 16:48 Europe/Berlin

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spring PetClinic is a sample Spring Boot application demonstrating best practices for building web applications with Spring. It's a veterinary clinic management system that tracks owners, their pets, visits, and veterinarians.

**Technology Stack:**
- Spring Boot 4.1.2
- Spring Data JPA with support for H2 (default), MySQL, and PostgreSQL
- Thymeleaf templating engine
- JCache/Caffeine for caching
- Bootstrap 5.3.8 for frontend styling
- Gradle 9.5.1 for build management (primary); Maven also available
- Java 25 LTS (Temurin `25.0.5.0+8-tem`) and Java 27 (Temurin `27.0.0.0+35-tem`); pick with `JDK_TRACK=25|27` (GraalVM variant only on 25)

## Build and Run Commands

### Building the Application

Gradle is the maintained build. The Gradle configuration cache is on (`gradle.properties`), and every task supports it, including `checkstyleNohttp` (defined in `build.gradle`, not by the old nohttp plugin).

```bash
# Gradle: build the jar (JDK 25 by default, add -PjavaVersion=27 for JDK 27)
./gradlew bootJar

# Gradle: run the application
./gradlew bootRun
```

Maven commands:

```bash
# Build and package the application
./mvnw package

# Run the application
java -jar target/*.jar

# Or run directly with Spring Boot Maven plugin (picks up changes immediately)
./mvnw spring-boot:run

# Build container image (requires Docker daemon)
./mvnw spring-boot:build-image

# Compile CSS from SCSS (required after changing scss files or upgrading Bootstrap)
./mvnw package -P css
```

### Running Tests

```bash
# Gradle: run all tests
./gradlew test

# Gradle: full build with all checks (tests, Checkstyle, nohttp, format check)
./gradlew build
```

Maven commands:

```bash
# Run all tests
./mvnw test

# Run a specific test class
./mvnw test -Dtest=OwnerControllerTests

# Run a specific test method
./mvnw test -Dtest=OwnerControllerTests#testProcessCreationFormHasErrors

# Run tests with coverage (JaCoCo)
./mvnw verify

# Run integration tests (includes tests that use Testcontainers/Docker)
./mvnw verify
```

### Code Quality

```bash
# Gradle: format code (Spring Java Format)
./gradlew formatMain formatTest

# Gradle: check code formatting
./gradlew checkFormat
```

Maven commands:

```bash
# Validate code formatting (Spring Java Format)
./mvnw validate

# Format code automatically
./mvnw spring-javaformat:apply

# Run checkstyle validation
./mvnw checkstyle:check
```

## Application Architecture

### Package Structure

The codebase follows a feature-based package organization:

```
org.springframework.samples.petclinic/
├── model/              # Base entity classes (BaseEntity, NamedEntity, Person)
├── owner/              # Owner domain: entities, controllers, repositories, validators
├── vet/                # Veterinarian domain: entities, controllers, repositories
├── system/             # System-wide configuration and utilities
├── PetClinicApplication.java      # Main Spring Boot application class
└── PetClinicRuntimeHints.java     # GraalVM native image hints (resources, reflection, Thymeleaf helpers)
```

### Domain Model

The application has three main domains organized as separate packages:

1. **Owner Domain** (`owner/`):
   - `Owner` - Pet owners with contact information
   - `Pet` - Pets belonging to owners
   - `Visit` - Vet visits for pets
   - `PetType` - Types of pets (cat, dog, etc.)
   - Controllers: `OwnerController`, `PetController`, `VisitController`
   - Repository: `OwnerRepository`, `PetTypeRepository`

2. **Vet Domain** (`vet/`):
   - `Vet` - Veterinarians
   - `Specialty` - Vet specialties (radiology, surgery, dentistry)
   - Controller: `VetController`
   - Repository: `VetRepository`

3. **System** (`system/`):
   - `CacheConfiguration` - JCache configuration for the "vets" cache
   - `WebConfiguration` - Session-based language setting and language switch by `?lang=` URL parameter
   - `WelcomeController` - Home page controller
   - `CrashController` - Demonstrates exception handling

### Base Model Classes

All entities inherit from base classes in the `model/` package:
- `BaseEntity` - Provides ID field with auto-generation
- `NamedEntity` - Extends BaseEntity with a name field
- `Person` - Extends NamedEntity with firstName and lastName

### Data Persistence

- Uses Spring Data JPA with repository interfaces extending `Repository` or `JpaRepository`
- Database schema initialized via SQL scripts in `src/main/resources/db/{h2,mysql,postgres}/`
- By default uses H2 in-memory database
- Caching enabled via `@EnableCaching` for vet list queries

### Web Layer

- Controllers use Spring MVC with Thymeleaf templates
- Templates located in `src/main/resources/templates/`
- Static resources (CSS, images) in `src/main/resources/static/resources/`
- Bootstrap CSS compiled from SCSS in `src/main/scss/`

## Database Configuration

### Default (H2 In-Memory)

Application runs with H2 by default. Console available at `http://localhost:8080/h2-console` with JDBC URL displayed at startup (`jdbc:h2:mem:<uuid>`).

### MySQL

```bash
# Start MySQL with Docker
docker run -e MYSQL_USER=petclinic -e MYSQL_PASSWORD=petclinic \
  -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=petclinic \
  -p 3306:3306 mysql:9.7

# Or use docker-compose
docker compose up mysql

# Run application with MySQL profile
./mvnw spring-boot:run -Dspring-boot.run.profiles=mysql
```

### PostgreSQL

```bash
# Start PostgreSQL with Docker
docker run -e POSTGRES_USER=petclinic -e POSTGRES_PASSWORD=petclinic \
  -e POSTGRES_DB=petclinic -p 5432:5432 postgres:18.4

# Or use docker-compose
docker compose up postgres

# Run application with PostgreSQL profile
./mvnw spring-boot:run -Dspring-boot.run.profiles=postgres
```

## Test Infrastructure

### Fast Development Workflow

For rapid development, use the test application classes with embedded Spring Boot Devtools:

- `PetClinicIntegrationTests.main()` - Runs with H2 and DevTools
- `MysqlTestApplication.main()` - Runs with MySQL via Testcontainers
- `PostgresIntegrationTests` class - Runs with PostgreSQL via Docker Compose

These can be run directly from your IDE as Java applications for quick feedback.

### Test Types

1. **Unit Tests** - Test individual components (controllers, validators, formatters)
2. **Integration Tests** - Full Spring context tests:
   - `PetClinicIntegrationTests` - Default H2 database
   - `MySqlIntegrationTests` - Uses Testcontainers to spin up MySQL in Docker
   - `PostgresIntegrationTests` - Uses Docker Compose to spin up PostgreSQL

Note: Tests using Testcontainers are disabled when Docker is not available and in native image/AOT mode.

## Code Style and Formatting

**Important:** This project uses Spring Java Format conventions enforced by the `spring-javaformat-maven-plugin`.

- **Indentation:** Tabs (width 4) for Java and XML files
- **Line endings:** LF (Unix-style)
- **Encoding:** UTF-8
- The build will fail if code doesn't conform to Spring Java Format
- Run `./gradlew formatMain formatTest` to auto-format code before committing (or `./mvnw spring-javaformat:apply` for Maven)
- Run `./gradlew checkFormat` to check the format

## Contributing Requirements

All commits must include a `Signed-off-by` trailer to indicate agreement with the Developer Certificate of Origin (DCO). This is required for all contributions to Spring projects.

Example commit message:
```
Add new feature for tracking pet vaccinations

Signed-off-by: Your Name <your.email@example.com>
```

## Customization
### General

This is a fork of the official Spring Petclininc application at https://github.com/spring-projects/spring-petclinic.
The fork exists to benchmark five different approaches for speeding up Spring Boot application startup:

- **Baseline** - Standard Spring Boot with AOT disabled
- **Spring Boot Tuning** - Spring Boot with AOT enabled
- **(Application) Class Data Sharing (CDS)** - Java CDS with AOT
- **OpenJDK Project Leyden** - Leyden AOT cache
- **OpenJDK Project CRaC** - Coordinated Restore at Checkpoint
- **GraalVM Native Image** - Native compilation with Profile-Guided Optimization

### Benchmark System

The benchmarks are orchestrated by two bash scripts:
- `./compile-and-run.sh` - Main orchestrator that builds variants and coordinates measurement
- `benchmark.sh` - Performance measurement script that executes training, warm-ups, and benchmarks

**Comprehensive documentation**: See [`specs/Startup-Benchmark-PRD.md`](specs/Startup-Benchmark-PRD.md) for detailed information about:
- How each optimization technique works
- Build commands and runtime parameters for each variant
- Java version requirements and platform compatibility
- Training run workflows (CDS, Leyden, CRaC, GraalVM PGO)
- Performance measurement methodology
- Troubleshooting and best practices

Short facts:
- `JDK_TRACK=25|27 ./compile-and-run.sh` picks the JDK track. Track 25 is the default and runs all six variants. Track 27 skips GraalVM and writes CSV files with a `_jdk27` suffix.
- `BENCH_WARMUPS` and `BENCH_RUNS` override the warm-up and run counts (defaults 3 and 7). Use them for smoke tests only: the CSV name then ends in `_smoke` (`result_<label>[_jdk27]_smoke.csv`). Official results use the defaults.
- `benchmark.sh` fails the run on any unexpected HTTP status. Only `/oups` returns 500. It stops the app before it exits.
- The `postgres` profile runs `schema.sql` and `data.sql` at every startup, in all variants (the native image too, since upstream `a2c2ef9`). The old `schema.sql` added a copy of every index at each startup; duplicates slow this down. Check for them before an official run with `docs/benchmark-results/2026-10-31-verification-boot-4.1.2/tools/duplicate-indexes.sql` (PRD findings 5 and 10).
- Results live in `docs/benchmark-results/`: the May 2026 full run, a 2026-10-31 verification run (not official) and the official run of 2026-11-01 with the German report `benchmark-bericht.html`. Its generator is `tools/make_report.py` in that folder.

### Build System

Although both Maven and Gradle builds exist, **Gradle is the actively used and maintained build system**. When making changes, prioritize Gradle compatibility.

## Agents

| Agent | When to Use | File Types |
|---|---|---|
| be-coder | Implement Java/Spring Boot features — entities, controllers, repositories, tests | `*.java` |
| be-reviewer | Review Java/Spring Boot code changes for correctness and Spring conventions | `*.java` |
| shell-coder | Implement changes to benchmark scripts — compile-and-run.sh, benchmark.sh | `*.sh` |
| shell-reviewer | Review benchmark script changes for correctness and safety | `*.sh` |

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spring PetClinic is a sample Spring Boot application demonstrating best practices for building web applications with Spring. It's a veterinary clinic management system that tracks owners, their pets, visits, and veterinarians.

**Technology Stack:**
- Spring Boot 3.5.0
- Spring Data JPA with support for H2 (default), MySQL, and PostgreSQL
- Thymeleaf templating engine
- JCache/Caffeine for caching
- Bootstrap 5.3.6 for frontend styling
- Maven for build management
- Java 17+

## Build and Run Commands

### Building the Application

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
└── PetClinicRuntimeHints.java     # GraalVM native image configuration
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
  -p 3306:3306 mysql:9.2

# Or use docker-compose
docker compose up mysql

# Run application with MySQL profile
./mvnw spring-boot:run -Dspring-boot.run.profiles=mysql
```

### PostgreSQL

```bash
# Start PostgreSQL with Docker
docker run -e POSTGRES_USER=petclinic -e POSTGRES_PASSWORD=petclinic \
  -e POSTGRES_DB=petclinic -p 5432:5432 postgres:17.5

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
- Run `./mvnw spring-javaformat:apply` to auto-format code before committing

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

### Build System

Although both Maven and Gradle builds exist, **Gradle is the actively used and maintained build system**. When making changes, prioritize Gradle compatibility.

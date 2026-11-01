# Back-End Specification

Updated: 2026-11-01 16:48 Europe/Berlin

Spring MVC application with JPA persistence. Veterinary clinic domain: owners, pets, visits, vets.

## Tech Stack

| Technology | Version | Purpose |
|---|---|---|
| Spring Boot | 4.1.2 | Auto-configuration, embedded Tomcat |
| Spring MVC | via Boot 4 | Web layer (`spring-boot-starter-webmvc`) |
| Spring Data JPA | via Boot 4 | Repository pattern |
| Hibernate | via Boot 4 | JPA provider, snake_case naming |
| JCache/Caffeine | via Boot 4 | Vet list caching |
| Jakarta Validation | via Boot 4 | Bean validation (`@NotBlank`, `@Pattern`) |
| H2 / MySQL / PostgreSQL | runtime | Databases (profile-selected) |
| Java | 25 (default), 27 | Gradle toolchain; use `-PjavaVersion=27` for JDK 27 |
| Gradle | 9.5.1 | Primary build (Maven wrapper 3.9.16 is secondary) |

## Package Structure

```
org.springframework.samples.petclinic/
├── model/          # BaseEntity, NamedEntity, Person (base classes)
├── owner/          # Owner, Pet, Visit, PetType + controllers + repository
├── vet/            # Vet, Specialty + controller + repository
├── system/         # CacheConfiguration, WebConfiguration, WelcomeController, CrashController
├── PetClinicApplication.java
└── PetClinicRuntimeHints.java   # GraalVM native image hints
```

## Key Patterns

- **Naming**: `@Column` without `name=` — Hibernate snake_case strategy maps `firstName` → `first_name`
- **Binder security**: `setDisallowedFields("id", "*.id")` in `OwnerController`, `PetController`, `VisitController`
- **Caching**: `@EnableCaching` on `CacheConfiguration`; vet list cached with JCache/Caffeine
- **No `@Nullable`**: jspecify annotations removed in Spring Boot 4 migration
- **CRaC**: conditional `org.crac:crac:1.5.0` dependency via `-Pcrac=true` Gradle flag
- **Column names**: `Visit.date` uses `@Column(name = "visit_date")` because the field name differs from the column

## Database Profiles

| Profile | Database | Config |
|---|---|---|
| (default) | H2 in-memory | `application.properties` |
| mysql | MySQL 9.7 | `application-mysql.properties` |
| postgres | PostgreSQL 18.4 | `application-postgres.properties` |

Schemas live in `src/main/resources/db/{h2,mysql,postgres}/schema.sql`.

## Data Model and Validation

- Entities: `Owner`, `Pet`, `PetType`, `Visit`, `Vet`, `Specialty`. Base classes: `BaseEntity`, `NamedEntity`, `Person`.
- Tables: `owners`, `pets`, `types`, `visits`, `vets`, `specialties`, `vet_specialties`.
- **Unique pet name per owner**: `UNIQUE (owner_id, name)` on `pets` (H2 and MySQL constraint; PostgreSQL unique index on `(owner_id, LOWER(name))`). H2 and PostgreSQL compare names case-insensitively.
- `Person.firstName` and `lastName`: `@NotBlank`, `@Size(max = 30)`.
- `Owner`: `address` `@Size(max = 255)`, `city` `@Size(max = 80)`, `telephone` `@Pattern(regexp = "\\d{10}")`.
- `Visit.description`: `@NotBlank`, `@Size(max = 255)`. The visit date must be in the future (`VisitController`).
- `PetValidator`: name required and at most 30 characters; type required for new pets; birth date required.
- `PetController`: rejects a duplicate pet name per owner (case-insensitive, `duplicate` error) and a birth date in the future.

## Endpoints

| Method | Path | Controller |
|---|---|---|
| GET | `/` | `WelcomeController` |
| GET | `/oups` | `CrashController` |
| GET | `/vets.html`, `/vets` | `VetController` |
| GET | `/owners/find`, `/owners`, `/owners/{ownerId}` | `OwnerController` |
| GET, POST | `/owners/new`, `/owners/{ownerId}/edit` | `OwnerController` |
| GET, POST | `/owners/{ownerId}/pets/new`, `/owners/{ownerId}/pets/{petId}/edit` | `PetController` |
| GET, POST | `/owners/{ownerId}/pets/{petId}/visits/new` | `VisitController` |

## Internationalization

- Bundles in `src/main/resources/messages/`: `messages.properties` plus `_de`, `_en`, `_es`, `_fa`, `_hi`, `_ja`, `_ko`, `_pt`, `_ru`, `_tr` (11 files).
- `spring.messages.basename=messages/messages`.
- `I18nPropertiesSyncTest` checks that every key exists in every bundle.

## Native Image

- `PetClinicRuntimeHints` registers: `db/*` and `messages/*` resources, `mysql-default-conf`, Java serialization for `BaseEntity`, `Person`, `Vet`.
- It also registers public methods of the Thymeleaf helpers `org.thymeleaf.expression.Strings`, `Numbers`, `Temporals` and `org.thymeleaf.spring6.expression.Fields` (`#fields.*`). Native image would miss them otherwise.
- `PetClinicRuntimeHintsTests` covers the hints.

## Testing

| Type | Example |
|---|---|
| MVC slice | `@WebMvcTest` with `OwnerControllerTests` |
| Integration | `PetClinicIntegrationTests` (H2) |
| MySQL integration | `MySqlIntegrationTests` (Testcontainers) |
| Postgres integration | `PostgresIntegrationTests` (Docker Compose — needs port 5432 free) |

## Do's and Don'ts

- DO run `./gradlew formatMain formatTest` before committing (`./gradlew checkFormat` verifies; `./mvnw spring-javaformat:apply` is the Maven goal)
- DO keep `checkstyleNohttp` in `build.gradle` compatible with the configuration cache (it replaces the io.spring.nohttp plugin, whose task was not); the build runs it via `check`
- DO use `@Column` without `name=` for standard fields
- DON'T use jspecify imports (`@Nullable`, `@NullMarked`)
- DON'T reference HSQLDB (removed)
- DON'T use `spring-boot-starter-web` (renamed to `spring-boot-starter-webmvc`)

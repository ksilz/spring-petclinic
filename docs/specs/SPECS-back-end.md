# Back-End Specification

Updated: 2026-05-01 15:29 Europe/Berlin

Spring MVC application with JPA persistence. Veterinary clinic domain: owners, pets, visits, vets.

## Tech Stack

| Technology | Version | Purpose |
|---|---|---|
| Spring Boot | 4.0.3 | Auto-configuration, embedded Tomcat |
| Spring MVC | via Boot 4 | Web layer (`spring-boot-starter-webmvc`) |
| Spring Data JPA | via Boot 4 | Repository pattern |
| Hibernate | via Boot 4 | JPA provider, snake_case naming |
| JCache/Caffeine | via Boot 4 | Vet list caching |
| Jakarta Validation | via Boot 4 | Bean validation (`@NotBlank`, `@Pattern`) |
| H2 / MySQL / PostgreSQL | runtime | Databases (profile-selected) |

## Package Structure

```
org.springframework.samples.petclinic/
├── model/          # BaseEntity, NamedEntity, Person (base classes)
├── owner/          # Owner, Pet, Visit, PetType + controllers + repository
├── vet/            # Vet, Specialty + controller + repository
├── system/         # CacheConfiguration, WelcomeController, CrashController
└── PetClinicApplication.java
```

## Key Patterns

- **Naming**: `@Column` without `name=` — Hibernate snake_case strategy maps `firstName` → `first_name`
- **Binder security**: `setDisallowedFields("id", "*.id")` in all controllers
- **Caching**: `@EnableCaching` on `CacheConfiguration`; vet list cached with JCache/Caffeine
- **No `@Nullable`**: jspecify annotations removed in Spring Boot 4 migration
- **CRaC**: conditional `org.crac:crac:1.5.0` dependency via `-Pcrac` Gradle flag

## Database Profiles

| Profile | Database | Config |
|---|---|---|
| (default) | H2 in-memory | `application.properties` |
| mysql | MySQL 9.6 | `application-mysql.properties` |
| postgres | PostgreSQL 18.3 | `application-postgres.properties` |

## Testing

| Type | Example |
|---|---|
| MVC slice | `@WebMvcTest` with `OwnerControllerTests` |
| Integration | `PetClinicIntegrationTests` (H2) |
| MySQL integration | `MySqlIntegrationTests` (Testcontainers) |
| Postgres integration | `PostgresIntegrationTests` (Docker Compose — needs port 5432 free) |

## Do's and Don'ts

- DO run `./gradlew spring-javaformat:apply` before committing
- DO use `@Column` without `name=` for standard fields
- DON'T use jspecify imports (`@Nullable`, `@NullMarked`)
- DON'T reference HSQLDB (removed)
- DON'T use `spring-boot-starter-web` (renamed to `spring-boot-starter-webmvc`)

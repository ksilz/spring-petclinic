# Documentation Update Result

Updated: 2026-11-01 02:26 Europe/Berlin

## Agents
- Created: none
- Updated:
  - `.claude/agents/be-coder.md` — Spring Boot 4.0.3 → 4.1.2; JDK 25 default, `-PjavaVersion=27`; format `spring-javaformat:apply` → `formatMain formatTest` + `checkFormat`; tests with `-x checkstyleNohttp`; `system/` lists WebConfiguration; added PetClinicRuntimeHints(+Tests) location and the Thymeleaf native-hint rule
  - `.claude/agents/be-reviewer.md` — added native-image reflection-hint check (missing hint → HTTP 500), new key locations (PetClinicRuntimeHints, WebConfiguration, hint tests), verification commands; `@Column` exception note (`Visit.date`)
  - `.claude/agents/shell-coder.md` — SDK pins 25.0.3-tem / 25.0.3-graal / 25.crac-zulu → per-track table (25.0.5.0+8-tem, 25.0.4.1-crac+1-zulu, 25.0.5.0+3-graal; 27.0.0.0+35-tem, 27.0.0.0-crac+35-zulu); labels per track; new "Benchmark Behavior" (BENCH_WARMUPS/RUNS, URL load, status guard, CRaC completion rule, CSV, known GraalVM GC issue); safety rules
  - `.claude/agents/shell-reviewer.md` — same pin corrections; CSV naming and columns; new "Benchmark Change Checks" and "Safety Rules" sections
- Verified current: none
- Skipped: none

## Specs
- Created: none
- Updated:
  - `docs/specs/SPECS-back-end.md` — Spring Boot 4.0.3 → 4.1.2; JDK tracks, Gradle 9.5.1; WebConfiguration and PetClinicRuntimeHints in package structure; MySQL 9.6 → 9.7, PostgreSQL 18.3 → 18.4; `-Pcrac` → `-Pcrac=true`; new sections Data Model and Validation (unique pet name per owner), Endpoints, Internationalization (11 bundles incl. hi, ja), Native Image; format and test commands corrected
  - `docs/specs/SPECS-overview.md` — PostgreSQL 18.3 → 18.4; build/test commands with `-x checkstyleNohttp`; format `spring-javaformat:apply` → `formatMain formatTest`; benchmark commands with `JDK_TRACK=27` and the smoke-test override
- Verified current: none
- Renamed: none
- Skipped: none

## Needs Attention
none

## CLAUDE.md
- Sections updated: Building the Application, Running Tests, Code Quality, Package Structure / System domain list, Database Configuration (MySQL, PostgreSQL), Code Style and Formatting, Benchmark System (short facts list)
- Sections added: none

## CLAUDE.md Size
- Line count: 287 (trigger: over 300, target: 200 or fewer)
- Candidates: not run

## CLAUDE.md Ticket References
- Flags: none

## Files Modified
- /Users/karsten/workspaces/me/open-source/spring-boot/spring-petclinic/.claude/agents/be-coder.md
- /Users/karsten/workspaces/me/open-source/spring-boot/spring-petclinic/.claude/agents/be-reviewer.md
- /Users/karsten/workspaces/me/open-source/spring-boot/spring-petclinic/.claude/agents/shell-coder.md
- /Users/karsten/workspaces/me/open-source/spring-boot/spring-petclinic/.claude/agents/shell-reviewer.md
- /Users/karsten/workspaces/me/open-source/spring-boot/spring-petclinic/docs/specs/SPECS-back-end.md
- /Users/karsten/workspaces/me/open-source/spring-boot/spring-petclinic/docs/specs/SPECS-overview.md
- /Users/karsten/workspaces/me/open-source/spring-boot/spring-petclinic/CLAUDE.md

## Profile Record
docs/profiles/update-claude-files/PROFILE-run-upgrade-benchmarks-jdk25-jdk27-20261101T012045Z.json
{"reference_lines_loaded": 404, "unique_reference_lines": 404, "repeat_ratio": 0.0, "target_project_lines_loaded": 287, "total_lines_loaded": 691, "dispatches": 9, "subagent_tokens": 501936, "orchestrator_reads": 5, "checkpoints": 0, "wall_clock_s": 339, "blocked": false}

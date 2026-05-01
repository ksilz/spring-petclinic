# Implementation Plan: UPDATE-EC2-JAVA25-GRAALVM25

## Test Command
Build test on each server — see Task 4 and Task 5.

## Context

Two EC2 servers (Frankfurt, `eu-central-1`):
- **Small** (`t3.small`): `ubuntu@ec2-18-192-45-97.eu-central-1.compute.amazonaws.com` — runs all benchmarks except GraalVM native compile
- **Big** (`t3.2xlarge`): `ubuntu@ec2-18-195-174-209.eu-central-1.compute.amazonaws.com` — compiles GraalVM native image

SSH key: `~/.ssh/AWS-Better-Projects-Faster-GmbH.pem -o IdentitiesOnly=yes`

Project path on servers: `/home/ubuntu/projects/spring-petclinic`

Required SDKman Java versions (from `compile-and-run.sh`):
- `25.0.3-tem` — Temurin 25.0.3 (baseline, tuning, CDS, Leyden)
- `25.crac-zulu` — Zulu CRaC JDK 25 (CRaC benchmark)
- `25.0.3-graal` — Oracle GraalVM 25.0.3 (native image)

## Tasks

### 1. Prepare — Check Current State on Both Servers

Run on **small** server:
- [ ] Check which Java versions are installed: `sdk list java | grep installed`
- [ ] Check current default Java: `java -version`
- [ ] Check PostgreSQL version: `sudo -iu postgres psql -c "SELECT version();"`
- [ ] Confirm project is checked out: `ls /home/ubuntu/projects/spring-petclinic`
- [ ] Pull latest code: `cd /home/ubuntu/projects/spring-petclinic && git pull`

Run on **big** server:
- [ ] Check which Java versions are installed: `sdk list java | grep installed`
- [ ] Check current default Java: `java -version`
- [ ] Check PostgreSQL version: `sudo -iu postgres psql -c "SELECT version();"`
- [ ] Pull latest code: `cd /home/ubuntu/projects/spring-petclinic && git pull`

### 2. Install/Update Java on Small Server

Via SDKman on the small server:
- [ ] Install Temurin 25.0.3: `sdk install java 25.0.3-tem`
- [ ] Install Zulu CRaC 25: `sdk install java 25.crac-zulu`
- [ ] Install Oracle GraalVM 25.0.3: `sdk install java 25.0.3-graal`
- [ ] Set Temurin as default: `sdk default java 25.0.3-tem`
- [ ] Verify: `java -version`

### 3. Install/Update Java on Big Server

Via SDKman on the big server:
- [ ] Install Oracle GraalVM 25.0.3: `sdk install java 25.0.3-graal`
- [ ] Set as default: `sdk default java 25.0.3-graal`
- [ ] Verify: `java -version`
- [ ] Also install Temurin 25.0.3 (may be needed for non-GraalVM tasks): `sdk install java 25.0.3-tem`

### 4. Check PostgreSQL 16 on Both Servers

**Stay on PG 16 — do NOT upgrade to 17+.**
- [ ] Small server: `sudo -iu postgres psql -c "SELECT version();"` — verify it's 16.x
- [ ] Small server: `sudo apt list --installed 2>/dev/null | grep postgresql` — check installed package version
- [ ] Small server: If on 16.x but a 16.y (y is newer minor) is available, update with: `sudo apt update && sudo apt install -y postgresql-16`
- [ ] Big server: same checks and update if needed

### 5. Test Build on Small Server

```bash
cd /home/ubuntu/projects/spring-petclinic
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk use java 25.0.3-tem

# Test 1: Baseline JAR build
./gradlew clean bootJar -x processAot -x processTestAot

# Test 2: AOT JAR build (tuning/CDS/Leyden)
./gradlew clean bootJar

# Test 3: CRaC build
sdk use java 25.crac-zulu
./gradlew clean bootJar -x processAot -x processTestAot
```

- [ ] Baseline JAR builds successfully
- [ ] AOT JAR builds successfully
- [ ] CRaC JAR builds successfully

### 6. Test GraalVM Native Build on Big Server

```bash
cd /home/ubuntu/projects/spring-petclinic
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk use java 25.0.3-graal

# Test: GraalVM native compile (PGO-instrumented first)
SPRING_PROFILES_ACTIVE=postgres ./gradlew clean nativeCompile --pgo-instrument
```

- [ ] GraalVM native compile starts without errors (full compile takes 15-30 min — check first 5 min for errors)
- [ ] Binary produces at `build/native/nativeCompile/spring-petclinic-instrumented`

### 7. Update Memory/Config

- [ ] Update `CLAUDE.local.md` with new server IP addresses
- [ ] Update memory file for EC2 small server address
- [ ] Commit configuration updates

## Verification

- Both servers have all required Java versions installed
- PostgreSQL stays at 16.x (not upgraded to 17+)
- All three JDK builds succeed on small server
- GraalVM native compile starts on big server
- Local documentation updated with new server addresses

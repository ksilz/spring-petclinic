#!/usr/bin/env bash
# Throwaway: records the exact versions and the host state before the official run.
source ~/.sdkman/bin/sdkman-init.sh
J=~/.sdkman/candidates/java
echo "== host $(hostname) $(date -u +%FT%TZ)"
grep -m1 "model name" /proc/cpuinfo; echo "vCPUs: $(nproc)"; free -m | sed -n 1,3p
echo "kernel: $(uname -r)"; ldd --version | head -1; grep PRETTY_NAME /etc/os-release
for j in 25.0.5.0+8-tem 25.0.4.1-crac+1-zulu 25.0.5.0+3-graal 27.0.0.0+35-tem 27.0.0.0-crac+35-zulu; do
  [[ -x "$J/$j/bin/java" ]] || continue
  echo "-- $j"; "$J/$j/bin/java" -version 2>&1
  [[ -x "$J/$j/bin/native-image" ]] && "$J/$j/bin/native-image" --version 2>&1
done
command -v criu >/dev/null && echo "criu: $(criu --version 2>&1 | head -1)"
echo "postgres: $(PGPASSWORD=petclinic psql -h localhost -U petclinic -d petclinic -At -c 'select version()' 2>&1)"
echo "indexes in petclinic: $(PGPASSWORD=petclinic psql -h localhost -U petclinic -d petclinic -At -c "select count(*) from pg_indexes where schemaname = 'public'" 2>&1)"
echo "apt timers: $(systemctl is-enabled apt-daily.timer apt-daily-upgrade.timer | tr '\n' ' ')"
cd ~/projects/petclinic-upgrade && echo "commit: $(git log --oneline -1)" && echo "status: [$(git status --short | tr '\n' ' ')]"
set +u; sdk use java 25.0.5.0+8-tem >/dev/null; ./gradlew --version 2>/dev/null | grep -E "^Gradle|^Kotlin|^Launcher"
grep -E "org.springframework.boot'|graalvm.buildtools|cyclonedx" build.gradle
echo "disk: $(df -h / | tail -1)"; echo "port 8080: $(ss -tln | grep -c ':8080 ')"; echo "java procs: $(ps -eo comm | grep -cx java)"

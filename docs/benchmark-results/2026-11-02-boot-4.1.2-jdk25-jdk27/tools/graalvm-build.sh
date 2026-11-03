#!/usr/bin/env bash
# Throwaway launcher (RUN-UPGRADE-BENCHMARKS): GraalVM native build + PGO on the big server.
source ~/.sdkman/bin/sdkman-init.sh
sdk use java 25.0.5.0+3-graal || { echo "GRAALVM_BUILD_EXIT sdk-use-failed $(date -u +%FT%TZ)"; exit 1; }
java --version
java --version 2>&1 | grep -q "Oracle GraalVM" || { echo "GRAALVM_BUILD_EXIT not-oracle-graalvm $(date -u +%FT%TZ)"; exit 1; }
cd ~/projects/petclinic-upgrade || exit 1
echo "GRAALVM_BUILD_START $(date -u +%FT%TZ)"
BENCH_WARMUPS=1 BENCH_RUNS=3 JDK_TRACK=25 ./compile-and-run.sh graalvm
rc=$?
echo "GRAALVM_BUILD_EXIT $rc $(date -u +%FT%TZ)"

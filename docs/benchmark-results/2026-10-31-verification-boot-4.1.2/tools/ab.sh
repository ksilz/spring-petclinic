#!/usr/bin/env bash
# Throwaway A/B diagnostic (RUN-UPGRADE-BENCHMARKS): May 2026 GraalVM executable vs new one,
# back to back on the small server, same benchmark.sh call, 1 warm-up + 3 runs each.
AB="$HOME/bench-runs/ab"
R="$HOME/projects/petclinic-upgrade"
cd "$R" || exit 1
export JDK_TRACK=25 BENCH_WARMUPS=1 BENCH_RUNS=3
cp -p result_graalvm.csv "$AB/result_graalvm_track25-original.csv" 2>/dev/null
for arm in may new; do
  if ss -tln | grep -q ":8080 "; then echo "AB ABORTED port-8080-busy $(date -u +%FT%TZ)" >>"$AB/ab.log"; exit 1; fi
  rm -f /tmp/gc_graalvm.log result_graalvm.csv
  if [[ $arm == may ]]; then src="$AB/native-may/spring-petclinic"; else src="$HOME/bench-runs/native/spring-petclinic"; fi
  mkdir -p build/native/nativeCompile
  cp "$src" build/native/nativeCompile/spring-petclinic && chmod +x build/native/nativeCompile/spring-petclinic
  app_mb=$(awk "BEGIN {printf \"%.1f\", $(du -sk build/native/nativeCompile/spring-petclinic | cut -f1)/1024}")
  echo "AB $arm START sha=$(sha256sum build/native/nativeCompile/spring-petclinic | cut -c1-12) $(date -u +%FT%TZ)" >>"$AB/ab.log"
  ./benchmark.sh build/native/nativeCompile/spring-petclinic graalvm "-Dspring.aot.enabled=true" "" "$app_mb" "" >"$AB/$arm.log" 2>&1
  rc=$?
  cp -p result_graalvm.csv "$AB/result_graalvm_$arm.csv" 2>/dev/null
  cp -p /tmp/app_benchmark.log "$AB/app_benchmark_$arm.log" 2>/dev/null
  echo "AB $arm EXIT $rc $(date -u +%FT%TZ)" >>"$AB/ab.log"
done
# Put the new executable and the original track-25 CSV back, so the checkout matches the track 25 state.
cp "$HOME/bench-runs/native/spring-petclinic" build/native/nativeCompile/spring-petclinic
cp -p "$AB/result_graalvm_track25-original.csv" result_graalvm.csv
echo "AB DONE $(date -u +%FT%TZ)" >>"$AB/ab.log"

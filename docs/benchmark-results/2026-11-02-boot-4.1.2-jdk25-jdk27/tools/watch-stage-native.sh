#!/usr/bin/env bash
# Mac side: wait for the big-server native build, then stage executable + PGO profile on the small server.
KEY=~/.ssh/AWS-Better-Projects-Faster-GmbH.pem
O=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15)
BIG=ubuntu@3.69.234.143 SMALL=ubuntu@3.122.54.30
R=/home/ubuntu/projects/petclinic-upgrade
until ssh "${O[@]}" "$BIG" 'grep -q GRAALVM_BUILD_EXIT ~/bench-runs/graalvm-build.log' 2>/dev/null; do sleep 60; done
ssh "${O[@]}" "$BIG" 'grep -E "GRAALVM_BUILD|Finished generating|BUILD (SUCC|FAIL)|Peak RSS" ~/bench-runs/graalvm-build.log; cat ~/projects/petclinic-upgrade/result_graalvm_smoke.csv 2>/dev/null'
if ! ssh "${O[@]}" "$BIG" 'grep -q "GRAALVM_BUILD_EXIT 0 " ~/bench-runs/graalvm-build.log'; then echo "STAGE SKIPPED: build failed"; exit 1; fi
ssh "${O[@]}" "$BIG" "cd $R && { sha256sum build/native/nativeCompile/spring-petclinic | sed 's#build/native/nativeCompile/##'; sha256sum src/pgo-profiles/main/default.iprof | sed 's#src/pgo-profiles/main/##'; } > ~/bench-runs/SHA256SUMS && cat ~/bench-runs/SHA256SUMS" || { echo "STAGE FAILED: checksums on big"; exit 1; }
scp -3 -q "${O[@]}" "$BIG:$R/build/native/nativeCompile/spring-petclinic" "$SMALL:/home/ubuntu/bench-runs/native/spring-petclinic" &&
scp -3 -q "${O[@]}" "$BIG:$R/src/pgo-profiles/main/default.iprof" "$SMALL:/home/ubuntu/bench-runs/native/default.iprof" &&
scp -3 -q "${O[@]}" "$BIG:/home/ubuntu/bench-runs/SHA256SUMS" "$SMALL:/home/ubuntu/bench-runs/native/SHA256SUMS.tmp" || { echo "STAGE FAILED: copy"; exit 1; }
ssh "${O[@]}" "$SMALL" 'cd ~/bench-runs/native && sha256sum -c SHA256SUMS.tmp && mv SHA256SUMS.tmp SHA256SUMS && ls -la' && echo "STAGED $(date -u +%FT%TZ)"

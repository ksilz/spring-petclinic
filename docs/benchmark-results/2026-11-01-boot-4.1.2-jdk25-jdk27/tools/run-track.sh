#!/usr/bin/env bash
# Throwaway benchmark runner for the official run 2026-11-01 (3 warm-ups + 7 runs). Not part of the repo.
# Lives in ~/bench-runs on the small server, outside both checkouts.
# Usage: run-track.sh <25|27> <variant>...
# Env passed through to benchmark.sh: BENCH_WARMUPS, BENCH_RUNS (defaults 3 / 7).
# Environment errors abort the whole invocation. Variant errors are recorded, then the next variant runs.

# sdkman trips over unset variables, so source it before strict mode.
# shellcheck disable=SC1090
source ~/.sdkman/bin/sdkman-init.sh
set -uo pipefail

TRACK="${1:-}"
shift || true
case "$TRACK" in
25 | 27) ;;
*)
  echo "usage: run-track.sh <25|27> <variant>..." >&2
  exit 2
  ;;
esac
[[ $# -ge 1 ]] || {
  echo "usage: run-track.sh <25|27> <variant>..." >&2
  exit 2
}

REPO="$HOME/projects/petclinic-upgrade"
OUT="$HOME/bench-runs/jdk$TRACK"
NATIVE="$HOME/bench-runs/native"
mkdir -p "$OUT"
PROG="$OUT/progress.log"

export JDK_TRACK="$TRACK"
export BENCH_WARMUPS="${BENCH_WARMUPS:-3}"
export BENCH_RUNS="${BENCH_RUNS:-7}"

if [[ "$TRACK" == "27" ]]; then
  JDK_TEM='27.0.0.0+35-tem'
  JDK_CRAC='27.0.0.0-crac+35-zulu'
else
  JDK_TEM='25.0.5.0+8-tem'
  JDK_CRAC='25.0.4.1-crac+1-zulu'
fi

now() { date -u +%FT%TZ; }
log() { echo "$*" | tee -a "$PROG"; }
abort() {
  log "TRACK $TRACK ABORTED $1 $(now)"
  exit 1
}

for v in "$@"; do
  case "$v" in
  baseline | tuning | cds | leyden | crac) ;;
  graalvm) [[ "$TRACK" == "25" ]] || abort "graalvm-not-on-track-$TRACK" ;;
  *) abort "unknown-variant-$v" ;;
  esac
done

# Prints ok | missing | bad:<reason>
check_csv() {
  local csv=$1 start=$2 label=$3
  [[ -f "$csv" ]] || {
    echo missing
    return
  }
  local mt
  mt=$(stat -c %Y "$csv")
  ((mt >= start)) || {
    echo "bad:stale-file"
    return
  }
  python3 -I - "$csv" "$start" "$BENCH_RUNS" "$label" <<'PY'
import csv, sys, datetime
path, start, runs, label = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
rows = list(csv.reader(open(path)))
body = rows[1:]
ids = [r[0] for r in body]
want = [str(i) for i in range(1, runs + 1)] + ["A"]
def num(x):
    try:
        float(x)
        return True
    except ValueError:
        return False
def bad(msg):
    print("bad:" + msg)
    sys.exit(0)
if ids != want:
    bad("rows=" + "|".join(ids))
for r in body[:-1]:
    if len(r) < 6 or not (num(r[1]) and num(r[2])):
        bad("non-numeric-run-" + r[0])
    try:
        ts = datetime.datetime.strptime(r[5], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
    except ValueError:
        bad("timestamp-run-" + r[0])
    if ts < start:
        bad("old-timestamp-run-" + r[0])
a = body[-1]
if not num(a[1]):
    bad("A-row-not-numeric")
if label == "graalvm" and not (len(a) > 6 and num(a[6]) and float(a[6]) > 0):
    bad("graalvm-size-app")
print("ok")
PY
}

cd "$REPO" || abort "no-repo"

for label in "$@"; do
  case "$label" in
  crac) pin="$JDK_CRAC" ;;
  graalvm) pin="" ;;
  *) pin="$JDK_TEM" ;;
  esac

  if [[ -n "$pin" ]]; then
    # sdkman's sdk function references unset variables (help_flag), so relax -u around it.
    set +u
    sdk use java "$pin" >/dev/null 2>&1
    sdk_rc=$?
    set -u
    ((sdk_rc == 0)) || abort "sdk-use-failed-$pin"
    major=$(java --version 2>&1 | head -n1 | grep -oE '[0-9]+' | head -n1)
    [[ "$major" == "$TRACK" ]] || abort "java-major-$major-not-$TRACK"
  fi
  if ss -tln | grep -q ':8080 '; then
    abort "port-8080-busy-before-$label"
  fi
  rm -f "/tmp/gc_${label}.log"
  if [[ "$label" == "leyden" ]]; then
    rm -f petclinic.aotconf
  fi

  logf="$OUT/$label.log"
  start=$(date +%s)
  log "VARIANT $label START $(now)"
  {
    echo "=== runner: track $TRACK, variant $label, pin ${pin:-native-binary}, BENCH_WARMUPS=$BENCH_WARMUPS, BENCH_RUNS=$BENCH_RUNS, commit $(git rev-parse --short HEAD)"
    java --version 2>&1 || true
  } >"$logf" 2>&1

  if [[ "$label" == "graalvm" ]]; then
    for f in spring-petclinic default.iprof SHA256SUMS; do
      [[ -f "$NATIVE/$f" ]] || abort "native-file-missing-$f"
    done
    (cd "$NATIVE" && sha256sum -c SHA256SUMS) >>"$logf" 2>&1 || abort "native-sha256-mismatch"
    mkdir -p build/native/nativeCompile src/pgo-profiles/main
    cp "$NATIVE/spring-petclinic" build/native/nativeCompile/spring-petclinic
    cp "$NATIVE/default.iprof" src/pgo-profiles/main/default.iprof
    chmod +x build/native/nativeCompile/spring-petclinic
    # Same size calculation as compile-and-run.sh get_variant_sizes
    app_kb=$(du -sk build/native/nativeCompile/spring-petclinic | cut -f1)
    extra_kb=$(du -sk src/pgo-profiles/main/default.iprof | cut -f1)
    app_mb=$(awk "BEGIN {printf \"%.1f\", $app_kb/1024}")
    extra_mb=$(awk "BEGIN {printf \"%.1f\", $extra_kb/1024}")
    echo "=== runner: sizes app=${app_mb} MB extra=${extra_mb} MB" >>"$logf"
    # Exactly the benchmark call compile-and-run.sh makes after its native build.
    ./benchmark.sh build/native/nativeCompile/spring-petclinic graalvm "-Dspring.aot.enabled=true" "" "$app_mb" "$extra_mb" >>"$logf" 2>&1
    rc=$?
  else
    ./compile-and-run.sh "$label" >>"$logf" 2>&1
    rc=$?
  fi

  suffix=""
  [[ "$TRACK" != "25" ]] && suffix="_jdk$TRACK"
  res=$(check_csv "result_${label}${suffix}.csv" "$start" "$label")
  log "VARIANT $label EXIT $rc CSV $res $(now)"

  # Keep the CSV, the last app/GC logs and all artifact sizes of this variant.
  cp -p "result_${label}${suffix}.csv" "$OUT/" 2>/dev/null
  # Only logs written during this variant (older ones belong to an earlier variant).
  for pair in "/tmp/app_benchmark.log:$label-app-benchmark-last.log" "/tmp/app_training.log:$label-app-training.log" \
    "/tmp/gc_${label}.log:$label-gc-last.log"; do
    src="${pair%%:*}" dst="${pair#*:}"
    [[ -f "$src" ]] && (($(stat -c %Y "$src") >= start)) && cp -p "$src" "$OUT/$dst"
  done
  {
    echo "== $label $(now)"
    X="spring-petclinic-4.0.0-SNAPSHOT"
    for p in "build/libs/$X.jar" "$X" "$X/$X.jar" "$X/lib" petclinic.jsa petclinic.aot petclinic-crac petclinic-crac/core.img \
      build/native/nativeCompile/spring-petclinic src/pgo-profiles/main/default.iprof; do
      [[ -e "$p" ]] && printf '%s KB disk, %s KB apparent, %s\n' "$(du -sk "$p" | cut -f1)" "$(du -sk --apparent-size "$p" | cut -f1)" "$p"
    done
    [[ -d "$X/lib" ]] && echo "lib jars: $(ls "$X/lib" | wc -l)"
  } >>"$OUT/sizes.txt" 2>&1
done

log "TRACK $TRACK DONE $(now)"

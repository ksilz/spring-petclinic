#!/usr/bin/env bash
# Throwaway test of the benchmark.sh failure-path helpers (descendant_pids, stop_app_after_failure,
# wait_for_port_free), extracted into a file. Usage: failpath-test.sh <functions-file> <label>
# A python http.server on port 8080 stands in for the app. Linux only (ss, GNU time, stdbuf).
# Never touches real benchmark files. Run only when nothing else uses port 8080.
source "$1"
label="$2"
LABEL=test
port_busy() { ss -tln | grep -q ':8080 '; }
wait_listen() { for _ in $(seq 1 50); do port_busy && return 0; sleep 0.1; done; return 1; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo gone; }
# Counts real python stand-ins (pgrep -f would also match this script's own command line).
apps_left() { ps -eo comm,args | awk '$1 == "python3" && /http.server 8080/' | wc -l | tr -d ' '; }
cleanup() {
  ps -eo pid,comm,args | awk '$2 == "python3" && /http.server 8080/ {print $1}' | xargs -r kill 2>/dev/null
  kill "$bystander" 2>/dev/null
  sleep 1
}

echo "=== $label T1: app_pid is a stale non-descendant; launcher is /usr/bin/time -> stdbuf -> app"
sleep 600 & bystander=$!
/usr/bin/time -v -o /tmp/failpath-time.log stdbuf -oL python3 -m http.server 8080 >/dev/null 2>&1 &
tpid=$!
wait_listen || echo "app did not listen"
app_pid=$bystander pid=""
t0=$(date +%s)
stop_app_after_failure "T1"
echo "T1 result: stop took $(($(date +%s) - t0))s, port busy after: $(port_busy && echo yes || echo no), bystander: $(alive $bystander), apps left: $(apps_left)"
cleanup

echo "=== $label T4: app_pid is the real app (child of /usr/bin/time)"
/usr/bin/time -v -o /tmp/failpath-time.log stdbuf -oL python3 -m http.server 8080 >/dev/null 2>&1 &
tpid=$!
wait_listen
app_pid=$(pgrep -P "$tpid" python3) pid=""
echo "app_pid=$app_pid descendants=[$(descendant_pids "$tpid")]"
t0=$(date +%s)
stop_app_after_failure "T4"
echo "T4 result: stop took $(($(date +%s) - t0))s, port busy after: $(port_busy && echo yes || echo no), apps left: $(apps_left)"
cleanup

echo "=== $label T5: app_pid is a grandchild (time -> bash -> app)"
/usr/bin/time -v -o /tmp/failpath-time.log bash -c 'python3 -m http.server 8080; true' >/dev/null 2>&1 &
tpid=$!
wait_listen
mid=$(pgrep -P "$tpid" bash)
app_pid=$(pgrep -P "$mid" python3) pid=""
echo "app_pid=$app_pid descendants=[$(descendant_pids "$tpid")]"
t0=$(date +%s)
stop_app_after_failure "T5"
echo "T5 result: stop took $(($(date +%s) - t0))s, port busy after: $(port_busy && echo yes || echo no), apps left: $(apps_left)"
cleanup

echo "=== $label T2: a foreign process (not a benchmark app) holds 8080"
python3 -m http.server 8080 >/dev/null 2>&1 &
foreign=$!
wait_listen
wait_for_port_free 3
echo "T2 result: foreign process: $(alive $foreign)"
kill "$foreign" 2>/dev/null; sleep 1

echo "=== $label T2b: a non-app process with spring-petclinic in a directory argument holds 8080"
mkdir -p /tmp/spring-petclinic-dir
python3 -m http.server 8080 --directory /tmp/spring-petclinic-dir >/dev/null 2>&1 &
foreign=$!
wait_listen
wait_for_port_free 3
echo "T2b result: process: $(alive $foreign)"
kill "$foreign" 2>/dev/null; sleep 1; rmdir /tmp/spring-petclinic-dir

echo "=== $label T3: the native executable holds 8080"
bash -c 'exec -a ./build/native/nativeCompile/spring-petclinic python3 -m http.server 8080' >/dev/null 2>&1 &
named=$!
wait_listen
wait_for_port_free 3
sleep 1
echo "T3 result: process: $(alive $named), port busy after: $(port_busy && echo yes || echo no)"
kill "$named" 2>/dev/null; sleep 1

echo "=== $label T3b: a 'java -jar ...spring-petclinic...jar' process holds 8080"
bash -c 'exec -a "java -Xmx768m -jar build/libs/spring-petclinic-4.0.0-SNAPSHOT.jar" python3 -m http.server 8080' >/dev/null 2>&1 &
named=$!
wait_listen
wait_for_port_free 3
sleep 1
echo "T3b result: process: $(alive $named), port busy after: $(port_busy && echo yes || echo no)"
kill "$named" 2>/dev/null
cleanup
rm -f /tmp/failpath-time.log

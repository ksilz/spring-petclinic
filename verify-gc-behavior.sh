#!/bin/bash
# verify-gc-behavior.sh - Verify GC behavior during startup vs benchmark phases
# Returns:
#   0 = Success (no GC during startup, some GC during benchmark)
#   1 = GC during startup (heap too small)
#   2 = No GC during benchmark (heap too large)
#   3 = GC during both phases or other issues

set -euo pipefail

# ---------------- Parameters ----------------
VARIANT="${1:-}"
APP_LOG="${2:-/tmp/app_benchmark.log}"
GC_LOG="${3:-/tmp/gc_${VARIANT}.log}"

if [[ -z "$VARIANT" ]]; then
	echo "ERROR: VARIANT parameter required"
	echo "Usage: $0 <VARIANT> [APP_LOG] [GC_LOG]"
	exit 3
fi

# ---------------- Helper Functions ----------------
log_info() {
	echo "[INFO] $*"
}

log_error() {
	echo "[ERROR] $*" >&2
}

# ---------------- Validation ----------------
if [[ ! -f "$APP_LOG" ]]; then
	log_error "Application log not found: $APP_LOG"
	exit 3
fi

if [[ ! -f "$GC_LOG" ]]; then
	log_error "GC log not found: $GC_LOG"
	# For GraalVM native image, GC log might not exist if PrintGC writes to stdout
	# Check if this is GraalVM and look for GC info in app log
	if [[ "$VARIANT" == "graalvm" ]]; then
		log_info "GraalVM variant - checking app log for GC output"
		GC_LOG="$APP_LOG"
	else
		exit 3
	fi
fi

# ---------------- Extract Startup Time ----------------
# Find the line with "Started PetClinicApplication" and extract the startup time
# Example line: "2025-11-01T10:30:45.123Z  INFO 12345 --- [main] o.s.s.p.PetClinicApplication : Started PetClinicApplication in 2.345 seconds"

STARTUP_LINE=$(grep "Started PetClinicApplication" "$APP_LOG" | head -1 || true)

if [[ -z "$STARTUP_LINE" ]]; then
	log_error "Could not find 'Started PetClinicApplication' in $APP_LOG"
	exit 3
fi

# Extract timestamp from the log line
# Format: YYYY-MM-DDTHH:MM:SS.sssZ
STARTUP_TIMESTAMP=$(echo "$STARTUP_LINE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' | head -1 || true)

if [[ -z "$STARTUP_TIMESTAMP" ]]; then
	log_error "Could not extract timestamp from startup line: $STARTUP_LINE"
	exit 3
fi

log_info "Application startup completed at: $STARTUP_TIMESTAMP"

# Convert timestamp to epoch seconds for comparison
STARTUP_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${STARTUP_TIMESTAMP%.*}" +%s 2>/dev/null || date -d "$STARTUP_TIMESTAMP" +%s 2>/dev/null || echo "0")

if [[ "$STARTUP_EPOCH" == "0" ]]; then
	log_error "Could not convert timestamp to epoch: $STARTUP_TIMESTAMP"
	exit 3
fi

log_info "Startup epoch: $STARTUP_EPOCH"

# ---------------- Parse GC Log ----------------
# GC log format (unified logging): [uptime]s [timestamp] gc...
# Example: [0.123s][2025-11-01T10:30:45.123+0000][info][gc] GC(0) Pause Young (Normal)
# We'll use the uptime field to determine if GC occurred before or after startup

# Extract all GC pause events and their uptimes
# Look for lines containing "Pause" which indicate stop-the-world GC events
# Use simple pattern to match Pause events in GC logs
GC_EVENTS=$(grep "Pause" "$GC_LOG" | grep -E "\[gc" 2>/dev/null || true)

if [[ -z "$GC_EVENTS" ]]; then
	log_info "No GC pause events found in $GC_LOG"
	GC_DURING_STARTUP=0
	GC_DURING_BENCHMARK=0
else
	log_info "Found GC pause events:"
	echo "$GC_EVENTS"

	# Count GC events by phase
	GC_DURING_STARTUP=0
	GC_DURING_BENCHMARK=0

	# Parse each GC event
	while IFS= read -r line; do
		# Extract uptime in seconds (format: [X.XXXs])
		UPTIME=$(echo "$line" | grep -oE '\[[0-9]+\.[0-9]+s\]' | tr -d '[]s' || true)

		if [[ -z "$UPTIME" ]]; then
			continue
		fi

		# Extract timestamp from GC log line
		GC_TIMESTAMP=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' | head -1 || true)

		if [[ -z "$GC_TIMESTAMP" ]]; then
			# Fallback: use uptime relative to startup
			# This is approximate but better than nothing
			log_info "GC event at uptime ${UPTIME}s (no timestamp)"
			continue
		fi

		# Convert GC timestamp to epoch
		GC_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${GC_TIMESTAMP%.*}" +%s 2>/dev/null || date -d "$GC_TIMESTAMP" +%s 2>/dev/null || echo "0")

		if [[ "$GC_EPOCH" == "0" ]]; then
			log_info "Could not parse GC timestamp: $GC_TIMESTAMP"
			continue
		fi

		# Compare timestamps to determine phase
		if [[ $GC_EPOCH -lt $STARTUP_EPOCH ]]; then
			log_info "GC event DURING STARTUP at ${GC_TIMESTAMP} (uptime: ${UPTIME}s)"
			((GC_DURING_STARTUP++))
		else
			log_info "GC event DURING BENCHMARK at ${GC_TIMESTAMP} (uptime: ${UPTIME}s)"
			((GC_DURING_BENCHMARK++))
		fi
	done <<< "$GC_EVENTS"
fi

# ---------------- Results ----------------
log_info "========================"
log_info "GC Events Summary:"
log_info "  During startup:   $GC_DURING_STARTUP"
log_info "  During benchmark: $GC_DURING_BENCHMARK"
log_info "========================"

# Determine exit code based on results
if [[ $GC_DURING_STARTUP -eq 0 ]] && [[ $GC_DURING_BENCHMARK -gt 0 ]]; then
	log_info "✅ SUCCESS: No GC during startup, GC occurred during benchmark"
	exit 0
elif [[ $GC_DURING_STARTUP -gt 0 ]] && [[ $GC_DURING_BENCHMARK -eq 0 ]]; then
	log_info "❌ FAIL: GC during startup, no GC during benchmark (heap needs adjustment)"
	exit 3
elif [[ $GC_DURING_STARTUP -gt 0 ]]; then
	log_info "❌ FAIL: GC during startup (heap too small - need to increase)"
	exit 1
elif [[ $GC_DURING_BENCHMARK -eq 0 ]]; then
	log_info "⚠️  WARN: No GC during benchmark (heap too large - can decrease)"
	exit 2
else
	log_info "⚠️  WARN: No GC events found at all"
	exit 2
fi

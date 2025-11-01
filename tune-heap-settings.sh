#!/bin/bash
# tune-heap-settings.sh - Iteratively tune heap settings for optimal GC behavior
# Goal: Find heap size where NO GC during startup but SOME GC during benchmark

set -euo pipefail

# ---------------- Configuration ----------------
STARTING_HEAP_MB=512
MIN_HEAP_MB=256
MAX_HEAP_MB=4096
ADJUSTMENT_MB=64
MAX_ITERATIONS=10

# Which variant to tune (default: baseline, fastest to test)
VARIANT="${1:-baseline}"
JAR_PATH="${2:-build/libs/spring-petclinic-3.5.0-SNAPSHOT.jar}"

# Results log
RESULTS_LOG="heap-tuning-results.log"
TODOS_FILE="TODOS.md"

# ---------------- Helper Functions ----------------
log_info() {
	echo "[INFO] $*"
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$RESULTS_LOG"
}

log_error() {
	echo "[ERROR] $*" >&2
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$RESULTS_LOG"
}

# Convert MB to JVM format (e.g., 512 -> 512m)
mb_to_jvm() {
	echo "${1}m"
}

# Update TODOS.md with current progress
update_todos() {
	local iteration=$1
	local heap_mb=$2
	local status=$3
	local details=$4

	cat > "$TODOS_FILE" <<EOF
# Heap Tuning Progress

## Goal
Find optimal JVM heap settings where:
- ✅ NO garbage collection during startup
- ✅ SOME garbage collection during benchmark runs

## Current Status
**Iteration:** $iteration / $MAX_ITERATIONS
**Current Heap:** -Xms${heap_mb}m -Xmx${heap_mb}m
**Status:** $status

$details

## Configuration
- **Variant:** $VARIANT
- **Adjustment increment:** ${ADJUSTMENT_MB} MB
- **Starting heap:** ${STARTING_HEAP_MB} MB
- **Min heap:** ${MIN_HEAP_MB} MB
- **Max heap:** ${MAX_HEAP_MB} MB
- **Max iterations:** $MAX_ITERATIONS

## Iteration Log

EOF

	# Append history from results log
	if [[ -f "$RESULTS_LOG" ]]; then
		echo "### Recent Iterations" >> "$TODOS_FILE"
		echo '```' >> "$TODOS_FILE"
		tail -20 "$RESULTS_LOG" >> "$TODOS_FILE"
		echo '```' >> "$TODOS_FILE"
	fi

	echo "" >> "$TODOS_FILE"
	echo "---" >> "$TODOS_FILE"
	echo "*Last updated: $(date +'%Y-%m-%d %H:%M:%S')*" >> "$TODOS_FILE"
}

# Run benchmark with specific heap settings
run_benchmark_with_heap() {
	local heap_mb=$1
	local heap_setting=$(mb_to_jvm $heap_mb)

	log_info "Running benchmark with heap: -Xms${heap_setting} -Xmx${heap_setting}"

	# Temporarily modify benchmark.sh parameter variables
	# We'll use environment variables to override the heap settings
	export HEAP_XMS="$heap_setting"
	export HEAP_XMX="$heap_setting"

	# Create a temporary benchmark script that uses our heap settings
	local temp_benchmark="./benchmark_temp.sh"

	# Copy benchmark.sh and modify heap parameters
	sed -e "s/-Xms[0-9]*[kmg]/-Xms${heap_setting}/g" \
		-e "s/-Xmx[0-9]*[kmg]/-Xmx${heap_setting}/g" \
		benchmark.sh > "$temp_benchmark"

	chmod +x "$temp_benchmark"

	# Run 3 benchmark iterations for consistency
	local benchmark_cmd="$temp_benchmark"

	# For baseline variant
	if [[ "$VARIANT" == "baseline" ]]; then
		$benchmark_cmd "$JAR_PATH" baseline
	elif [[ "$VARIANT" == "tuning" ]]; then
		$benchmark_cmd "$JAR_PATH" tuning "-Dspring.aot.enabled=true"
	else
		log_error "Variant $VARIANT not yet supported in tuning script"
		return 1
	fi

	# Clean up temp script
	rm -f "$temp_benchmark"

	return $?
}

# ---------------- Main Loop ----------------
log_info "========================================="
log_info "Starting heap tuning for variant: $VARIANT"
log_info "JAR path: $JAR_PATH"
log_info "========================================="

# Initialize
CURRENT_HEAP_MB=$STARTING_HEAP_MB
ITERATION=0
OPTIMAL_HEAP_MB=0
TESTED_HEAPS=()

# Track if we've seen both types of failures (helps avoid infinite loops)
SEEN_GC_DURING_STARTUP=false
SEEN_NO_GC_DURING_BENCHMARK=false

update_todos 0 $CURRENT_HEAP_MB "Initializing" "Starting heap tuning process..."

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
	((ITERATION++))

	log_info "========================================="
	log_info "Iteration $ITERATION / $MAX_ITERATIONS"
	log_info "Testing heap: ${CURRENT_HEAP_MB}m"
	log_info "========================================="

	# Check if we've already tested this heap size (avoid loops)
	if [[ ${#TESTED_HEAPS[@]} -gt 0 ]] && [[ " ${TESTED_HEAPS[@]} " =~ " ${CURRENT_HEAP_MB} " ]]; then
		log_error "Already tested heap size ${CURRENT_HEAP_MB}m - stopping to avoid loop"
		update_todos $ITERATION $CURRENT_HEAP_MB "Failed - Loop Detected" \
			"Already tested this heap size. Stopping.\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"
		break
	fi

	TESTED_HEAPS+=($CURRENT_HEAP_MB)

	# Update TODOS.md
	update_todos $ITERATION $CURRENT_HEAP_MB "Running benchmark" \
		"Executing benchmark with -Xms${CURRENT_HEAP_MB}m -Xmx${CURRENT_HEAP_MB}m...\n\n**Tested heap sizes so far:** ${TESTED_HEAPS[*]}"

	# Run benchmark
	if ! run_benchmark_with_heap $CURRENT_HEAP_MB; then
		log_error "Benchmark failed for heap size ${CURRENT_HEAP_MB}m"
		update_todos $ITERATION $CURRENT_HEAP_MB "Benchmark Failed" \
			"Benchmark execution failed. Check logs."
		continue
	fi

	# Verify GC behavior
	update_todos $ITERATION $CURRENT_HEAP_MB "Verifying GC behavior" \
		"Benchmark completed. Analyzing GC logs...\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"

	# Capture exit code without triggering set -e
	./verify-gc-behavior.sh "$VARIANT" || VERIFY_RESULT=$?
	VERIFY_RESULT=${VERIFY_RESULT:-0}

	case $VERIFY_RESULT in
		0)
			# Success!
			log_info "✅ SUCCESS! Optimal heap found: ${CURRENT_HEAP_MB}m"
			OPTIMAL_HEAP_MB=$CURRENT_HEAP_MB
			update_todos $ITERATION $CURRENT_HEAP_MB "✅ SUCCESS - Optimal Heap Found!" \
				"No GC during startup, GC occurred during benchmark.\n\n**Optimal heap settings:** -Xms${OPTIMAL_HEAP_MB}m -Xmx${OPTIMAL_HEAP_MB}m\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"
			break
			;;
		1)
			# GC during startup - heap too small
			log_info "GC occurred during startup. Increasing heap by ${ADJUSTMENT_MB}m"
			SEEN_GC_DURING_STARTUP=true

			NEXT_HEAP_MB=$((CURRENT_HEAP_MB + ADJUSTMENT_MB))

			if [[ $NEXT_HEAP_MB -gt $MAX_HEAP_MB ]]; then
				log_error "Reached maximum heap size (${MAX_HEAP_MB}m) - stopping"
				update_todos $ITERATION $CURRENT_HEAP_MB "Failed - Max Heap Reached" \
					"GC still occurring during startup even at ${CURRENT_HEAP_MB}m.\nReached max heap limit.\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"
				break
			fi

			update_todos $ITERATION $CURRENT_HEAP_MB "GC during startup - increasing heap" \
				"GC detected during startup. Increasing from ${CURRENT_HEAP_MB}m to ${NEXT_HEAP_MB}m\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"

			CURRENT_HEAP_MB=$NEXT_HEAP_MB
			;;
		2)
			# No GC during benchmark - heap too large
			log_info "No GC during benchmark. Decreasing heap by ${ADJUSTMENT_MB}m"
			SEEN_NO_GC_DURING_BENCHMARK=true

			NEXT_HEAP_MB=$((CURRENT_HEAP_MB - ADJUSTMENT_MB))

			if [[ $NEXT_HEAP_MB -lt $MIN_HEAP_MB ]]; then
				log_error "Reached minimum heap size (${MIN_HEAP_MB}m) - stopping"
				update_todos $ITERATION $CURRENT_HEAP_MB "Failed - Min Heap Reached" \
					"No GC during benchmark even at ${CURRENT_HEAP_MB}m.\nReached min heap limit.\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"
				break
			fi

			update_todos $ITERATION $CURRENT_HEAP_MB "No GC during benchmark - decreasing heap" \
				"No GC detected during benchmark. Decreasing from ${CURRENT_HEAP_MB}m to ${NEXT_HEAP_MB}m\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"

			CURRENT_HEAP_MB=$NEXT_HEAP_MB
			;;
		3)
			# GC during both phases or other issues
			log_error "GC during both phases or verification error"

			# If we've seen both types of failures, we might be in a narrow window
			if [[ "$SEEN_GC_DURING_STARTUP" == "true" ]] && [[ "$SEEN_NO_GC_DURING_BENCHMARK" == "true" ]]; then
				log_info "We've oscillated between too small and too large."
				log_info "The optimal heap size is likely between tested values."
				log_info "Using last tested value as best approximation: ${CURRENT_HEAP_MB}m"
				OPTIMAL_HEAP_MB=$CURRENT_HEAP_MB
				update_todos $ITERATION $CURRENT_HEAP_MB "⚠️ Approximate Solution" \
					"Could not find exact optimal heap.\nBest approximation: -Xms${OPTIMAL_HEAP_MB}m -Xmx${OPTIMAL_HEAP_MB}m\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"
				break
			fi

			# Otherwise, try increasing (conservative approach)
			NEXT_HEAP_MB=$((CURRENT_HEAP_MB + ADJUSTMENT_MB))
			log_info "Trying larger heap: ${NEXT_HEAP_MB}m"
			update_todos $ITERATION $CURRENT_HEAP_MB "Unclear result - trying larger heap" \
				"GC behavior unclear. Increasing from ${CURRENT_HEAP_MB}m to ${NEXT_HEAP_MB}m\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"

			CURRENT_HEAP_MB=$NEXT_HEAP_MB
			;;
	esac
done

# ---------------- Final Results ----------------
log_info "========================================="
log_info "Heap Tuning Complete"
log_info "========================================="

if [[ $OPTIMAL_HEAP_MB -gt 0 ]]; then
	log_info "✅ Optimal heap settings found:"
	log_info "   -Xms${OPTIMAL_HEAP_MB}m -Xmx${OPTIMAL_HEAP_MB}m"
	log_info ""
	log_info "Update benchmark.sh with these settings for variant: $VARIANT"

	# Show which lines to update
	log_info ""
	log_info "Suggested changes for benchmark.sh:"
	log_info "  Replace: -Xms512m -Xmx1g"
	log_info "  With:    -Xms${OPTIMAL_HEAP_MB}m -Xmx${OPTIMAL_HEAP_MB}m"

	# Update final TODOS.md
	cat >> "$TODOS_FILE" <<EOF

## ✅ Final Results

**Optimal heap settings:** \`-Xms${OPTIMAL_HEAP_MB}m -Xmx${OPTIMAL_HEAP_MB}m\`

### Next Steps
1. Update \`benchmark.sh\` with optimal heap settings
2. Re-run full benchmark suite to verify
3. Consider testing other variants (tuning, CDS, Leyden, CRaC)

---
EOF

	exit 0
else
	log_error "❌ Failed to find optimal heap settings"
	log_error "Iterations exhausted or limits reached"
	log_error "Review $RESULTS_LOG for details"

	update_todos $ITERATION $CURRENT_HEAP_MB "❌ Failed" \
		"Could not find optimal heap settings within constraints.\n\nReview $RESULTS_LOG for details.\n\n**Tested heap sizes:** ${TESTED_HEAPS[*]}"

	exit 1
fi

#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

C3C=$(get_c3c_path)
ensure_executable "$C3C"

FUZZ_DIR="fuzz_results"
mkdir -p "$FUZZ_DIR"

gen_random_c3() {
    local f=$1
    echo "module fuzz;" > "$f"
    echo "import std::io;" >> "$f"
    
    # Random types
    for i in {1..5}; do
        case $((RANDOM % 3)) in
            0) echo "struct S$i { int a; double b; }" >> "$f" ;;
            1) echo "enum E$i : int { A, B, C }" >> "$f" ;;
            2) echo "type T$i = int;" >> "$f" ;;
        esac
    done
    
    # Random functions
    for i in {1..10}; do
        echo "fn void func$i() {" >> "$f"
        for j in {1..5}; do
            case $((RANDOM % 3)) in
                0) echo "  int x = $((RANDOM % 100));" >> "$f" ;;
                1) echo "  if (x > 50) { std::io::printn(\"high\"); }" >> "$f" ;;
                2) echo "  for (int k = 0; k < 10; k++) { x += k; }" >> "$f" ;;
            esac
        done
        echo "}" >> "$f"
    done
    
    echo "fn void main() { func1(); }" >> "$f"
}

log_info "Starting fuzzer (Limit: ${FUZZ_LIMIT:-infinite})..."
count=0; crashes=0
while [[ -z "${FUZZ_LIMIT:-}" ]] || [[ $count -lt $FUZZ_LIMIT ]]; do
    ((count++))
    target="$FUZZ_DIR/fuzz_$count.c3"
    gen_random_c3 "$target"
    
    # Run compiler
    local bin="${target%.*}"
    [[ "$PLATFORM" == "Windows" ]] && bin="${bin}.exe"
    out=$("$C3C" compile "$target" -o "$bin" 2>&1)
    status=$?
    
    if [[ $status -ge 128 ]]; then
        log_error "CRASH DETECTED (Signal $((status-128)))! Saved to $target"
        echo "$out" > "$target.log"
        ((crashes++))
    else
        rm -f "$target"
    fi
    
    [[ $((count % 100)) -eq 0 ]] && log_info "Fuzzed $count files..."
done

log_info "Fuzzing complete. Total: $count, Crashes: $crashes"
[[ $crashes -gt 0 ]] && exit 1 || exit 0

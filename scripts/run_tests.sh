#!/usr/bin/env bash
# run_tests.sh -- compiles and runs every self-checking testbench in this
# repository with Icarus Verilog, and fails (exit 1) if any of them prints
# FAIL or produces no PASS output at all. Used by CI (.github/workflows/ci.yml)
# and safe to run locally the same way -- see README.md's "Building and
# running the tests" section, which this mirrors exactly.
#
# Usage: ./scripts/run_tests.sh   (run from the repository root)
set -uo pipefail

cd "$(dirname "$0")/.."

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

overall_status=0

run() {
    local label="$1" outname="$2"
    shift 2
    echo "=== $label ==="

    if ! iverilog -o "$tmpdir/$outname.vvp" "$@" 2>&1; then
        echo "COMPILE FAILED: $label"
        overall_status=1
        return
    fi

    local out
    out=$(vvp "$tmpdir/$outname.vvp")
    echo "$out"

    if echo "$out" | grep -q "FAIL"; then
        echo ">>> TEST FAILED: $label"
        overall_status=1
    elif ! echo "$out" | grep -q "PASS"; then
        echo ">>> NO PASS OUTPUT -- treating as failed: $label"
        overall_status=1
    fi
    echo
}

run "tb_top (flagship QDOT4 smoke test)" tb_top \
    tb_top.v rtl/top.v rtl/cpu_core.v rtl/alu.v rtl/regfile.v rtl/qdot4.v

for t in hazard_branch hazard_loaduse hazard_qdot4 hazard_qdot8 hazard_qdot8_hi qdot8_basic; do
    run "tests/tb_$t" "$t" \
        tests/tb_$t.v rtl/top.v rtl/cpu_core.v rtl/alu.v rtl/regfile.v rtl/qdot4.v
done

run "sw/tb_kernel" tb_kernel \
    sw/tb_kernel.v rtl/top.v rtl/cpu_core.v rtl/alu.v rtl/regfile.v rtl/qdot4.v

run "sw/tb_benchmark" tb_benchmark \
    sw/tb_benchmark.v rtl/top.v rtl/cpu_core.v rtl/alu.v rtl/regfile.v rtl/qdot4.v

run "fpga/tb_uart" tb_uart \
    fpga/tb_uart.v fpga/uart_tx.v fpga/uart_rx.v

run "fpga/tb_fpga_top" tb_fpga_top \
    fpga/tb_fpga_top.v fpga/fpga_top.v fpga/uart_tx.v fpga/uart_rx.v rtl/cpu_core.v rtl/alu.v rtl/regfile.v rtl/qdot4.v

echo "===================================="
if [ "$overall_status" -ne 0 ]; then
    echo "RESULT: one or more tests FAILED"
else
    echo "RESULT: all tests PASSED"
fi

exit "$overall_status"

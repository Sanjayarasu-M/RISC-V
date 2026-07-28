# synth.tcl -- Vivado non-project batch-mode synthesis + implementation for
# fpga_top (Phase 4: synthesis/timing-closure checkpoint, no real board).
#
# Run from the RISC-V project root:
#   vivado -mode batch -source fpga/synth.tcl
set script_dir [file dirname [info script]]
set root_dir   [file normalize "$script_dir/.."]
set build_dir  "$script_dir/build"
file mkdir $build_dir

set part xczu7ev-ffvf1517-1LV-i

read_verilog [list \
    "$root_dir/rtl/cpu_core.v" \
    "$root_dir/rtl/alu.v" \
    "$root_dir/rtl/regfile.v" \
    "$root_dir/rtl/qdot4.v" \
    "$script_dir/fpga_top.v" \
    "$script_dir/uart_tx.v" \
    "$script_dir/uart_rx.v" \
]

read_xdc "$script_dir/constraints.xdc"

synth_design -top fpga_top -part $part \
    -generic IMEM_FILE=$root_dir/sw/kernel.hex \
    -generic DMEM_FILE=$root_dir/sw/kernel_data.hex

report_utilization -file "$build_dir/utilization_synth.rpt"

opt_design
place_design
phys_opt_design
route_design

report_utilization    -file "$build_dir/utilization.rpt"
report_timing_summary -file "$build_dir/timing_summary.rpt"
write_checkpoint -force "$build_dir/fpga_top_routed.dcp"

puts "=== SYNTHESIS + IMPLEMENTATION COMPLETE ==="

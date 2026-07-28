open_checkpoint [file dirname [info script]]/build/fpga_top_routed.dcp

set cells [get_cells -hierarchical -filter {REF_NAME =~ "RAMB*"}]
foreach c $cells {
    puts "BRAM CELL: $c  (REF_NAME=[get_property REF_NAME $c])"
}
puts "Total BRAM primitives: [llength $cells]"

set lutram [get_cells -hierarchical -filter {IS_PRIMITIVE && (RAM_ADDRESS_SPACE != "")}]
puts "---"
set distram [get_cells -hierarchical -filter {REF_NAME =~ "RAM64*" || REF_NAME =~ "RAM32*" || REF_NAME =~ "RAM128*" || REF_NAME =~ "RAM256*"}]
foreach c $distram {
    puts "DISTRAM CELL: $c  (REF_NAME=[get_property REF_NAME $c])"
}
puts "Total distributed RAM primitives: [llength $distram]"

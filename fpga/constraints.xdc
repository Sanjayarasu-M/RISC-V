# constraints.xdc -- timing constraints for fpga_top (Phase 4: synthesis and
# timing closure only, no real board available). No specific board is
# targeted, so pin LOCs below are commented-out placeholders -- fill in your
# board's actual clock/reset/UART pins and IOSTANDARD before generating a
# bitstream for real hardware.

create_clock -name clk -period 20.000 [get_ports clk]

# set_property -dict { PACKAGE_PIN <pin> IOSTANDARD LVCMOS33 } [get_ports clk]
# set_property -dict { PACKAGE_PIN <pin> IOSTANDARD LVCMOS33 } [get_ports rst]
# set_property -dict { PACKAGE_PIN <pin> IOSTANDARD LVCMOS33 } [get_ports uart_tx_pin]

set_input_delay  -clock clk -max 2.000 [get_ports rst]
set_input_delay  -clock clk -min 0.500 [get_ports rst]
set_output_delay -clock clk -max 2.000 [get_ports uart_tx_pin]
set_output_delay -clock clk -min 0.500 [get_ports uart_tx_pin]

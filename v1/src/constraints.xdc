## ============================================================
## RG Sonic32 v1 - Alchitry Au V2 constraints
## Device: xc7a35tftg256-2
## ============================================================

## Clock - 100 MHz on-board oscillator
## Set to 75 bMHZ since 100 caused timing issues in the MUL path
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -name clk -period 13.333 -waveform {0.000 6.667} [get_ports { clk }] 
## Reset - active low button (P6)
set_property -dict { PACKAGE_PIN P6  IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

## Halt LED - lights when CPU halts (LED0 = K13)
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { halt_out }]

## All 8 onboard LEDs for reference (comment in as needed)
# set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
# set_property -dict { PACKAGE_PIN K12 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
# set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
# set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]
# set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports { led[4] }]
# set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[5] }]
# set_property -dict { PACKAGE_PIN M12 IOSTANDARD LVCMOS33 } [get_ports { led[6] }]
# set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports { led[7] }]

## Required config voltage properties
set_property CONFIG_VOLTAGE 3.3        [current_design]
set_property CFGBVS        VCCO       [current_design]
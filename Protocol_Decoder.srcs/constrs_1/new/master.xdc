## This file is a general .xdc for the EDGE Artix 7 board
## To use it in a project:
## - comment the lines corresponding to unused pins
## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

# Clock signal
set_property -dict {PACKAGE_PIN N11 IOSTANDARD LVCMOS33} [get_ports clk]

# Switches

# LEDs

# Push Button

#7 segment display


# Bluetooth

# Buzzer

# SPI DAC (MCP4921)

# HDMI

# 2x16 LCD
#LCD R/W pin is connected to ground by default.No need to assign LCD R/W Pin.

#256Mb SDRAM (Only available with latest version of board)






# SPI TFT 1.8 inch

# USB UART

# WiFi

# CMOS Camera

#20 pin expansion connector
#pin1 5V
#pin2 NC
#pin3 3V3
#pin4 GND

# XADC Single Ended Input available at J13 Connector

# Audio Jack

# SRAM 512 KB  (SRAM replaced with SDRAM in the latest version of board) only required for older boards
#set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[0]}];
#set_property -dict { PACKAGE_PIN C8 IOSTANDARD LVCMOS33  } [get_ports {sram_addr[1]}];
#set_property -dict { PACKAGE_PIN C9 IOSTANDARD LVCMOS33  } [get_ports {sram_addr[2]}];
#set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33  } [get_ports {sram_addr[3]}];
#set_property -dict { PACKAGE_PIN A9 IOSTANDARD LVCMOS33  } [get_ports {sram_addr[4]}];
#set_property -dict { PACKAGE_PIN B9 IOSTANDARD LVCMOS33  } [get_ports {sram_addr[5]}];
#set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[6]}];
#set_property -dict { PACKAGE_PIN B10 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[7]}];
#set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[8]}];
#set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[9]}];
#set_property -dict { PACKAGE_PIN A12 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[10]}];
#set_property -dict { PACKAGE_PIN D8 IOSTANDARD LVCMOS33  } [get_ports {sram_addr[11]}];
#set_property -dict { PACKAGE_PIN D9 IOSTANDARD LVCMOS33  } [get_ports {sram_addr[12]}];
#set_property -dict { PACKAGE_PIN A13 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[13]}];
#set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[14]}];
#set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[15]}];
#set_property -dict { PACKAGE_PIN B14 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[16]}];
#set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[17]}];
#set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports {sram_addr[18]}];

#set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports {sram_data[0]}];
#set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {sram_data[1]}];
#set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports {sram_data[2]}];
#set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports {sram_data[3]}];
#set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports {sram_data[4]}];
#set_property -dict { PACKAGE_PIN C13 IOSTANDARD LVCMOS33 } [get_ports {sram_data[5]}];
#set_property -dict { PACKAGE_PIN E12 IOSTANDARD LVCMOS33 } [get_ports {sram_data[6]}];
#set_property -dict { PACKAGE_PIN E13 IOSTANDARD LVCMOS33 } [get_ports {sram_data[7]}];

#set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 } [get_ports {sram_we_n}];
#set_property -dict { PACKAGE_PIN E11 IOSTANDARD LVCMOS33 } [get_ports {sram_oe_n}];
#set_property -dict { PACKAGE_PIN D11 IOSTANDARD LVCMOS33 } [get_ports {sram_ce_a_n}];

# -----------------------------------------------------------------------------
# Analyzer top-level mappings
# -----------------------------------------------------------------------------

# Mode select switches (LSBs)
set_property -dict {PACKAGE_PIN L5 IOSTANDARD LVCMOS33} [get_ports {sw_mode[0]}]
set_property -dict {PACKAGE_PIN L4 IOSTANDARD LVCMOS33} [get_ports {sw_mode[1]}]

# Optional reset from push button (active-high)

# CAN interface
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS33} [get_ports can_rx]
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports can_tx]

# USB-UART interface
# usb_uart_txd (C4): USB-UART TXD -> FPGA input
# usb_uart_rxd (D4): FPGA output  -> USB-UART RXD
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports uart_out_rx]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports uart_laptop_tx]
#set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports uart_laptop_tx]

# I2C monitor inputs on expansion header pins
set_property -dict {PACKAGE_PIN P10 IOSTANDARD LVCMOS33} [get_ports scl]
set_property -dict {PACKAGE_PIN P11 IOSTANDARD LVCMOS33} [get_ports sda]

# User LED
set_property -dict {PACKAGE_PIN J3 IOSTANDARD LVCMOS33} [get_ports user_led]

set_property IOSTANDARD LVCMOS33 [get_ports user_led_2]

set_property PACKAGE_PIN J1 [get_ports user_led_2]

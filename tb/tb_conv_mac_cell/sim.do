if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv -dpiheader utils.h utils.c "tb_conv_mac_cell.sv" "../../common/*.v" "../../generic/*.v" "../../sub_module/conv_mac_cell.v"

# 仿真
vsim -voptargs=+acc -c tb_conv_mac_cell
do wave.do
run 1us

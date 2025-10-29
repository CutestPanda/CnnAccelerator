if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../generic/fifo_based_on_regs.v" "../../sub_module/conv_data_sfc_gen.v"

# 仿真
vsim -voptargs=+acc -c tb_conv_data_sfc_gen
do wave.do

if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../common/*.v" "../../generic/*.v" "../../sub_module/conv_buffer_core.v" "../../sub_module/conv_buffer.v"

# 仿真
vsim -voptargs=+acc -c tb_conv_buffer
do wave.do
run 1us

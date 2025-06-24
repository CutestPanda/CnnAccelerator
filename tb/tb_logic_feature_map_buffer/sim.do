if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../common/*.v" "../../generic/*.v" "../../sub_module/conv_buffer.v" "../../sub_module/conv_buffer_core.v" "../../sub_module/logic_feature_map_buffer.v"

# 仿真
vsim -voptargs=+acc -c tb_logic_feature_map_buffer
do wave.do

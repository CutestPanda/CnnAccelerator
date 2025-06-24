if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../sub_module/kernal_pos_logic_to_phy.v"

# 仿真
vsim -voptargs=+acc -c tb_kernal_pos_logic_to_phy
do wave.do

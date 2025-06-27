if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../common/div_u16_u3.v" "../../sub_module/surface_pos_logic_to_phy.v"

# 仿真
vsim -voptargs=+acc -c tb_surface_pos_logic_to_phy
do wave.do
